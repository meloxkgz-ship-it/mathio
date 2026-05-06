import SwiftUI
import StoreKit
import UserNotifications
import AudioToolbox

// MARK: - Premium store
//
// Native StoreKit 2. Three subscription products keyed by App Store Connect ID.
// Local testing uses Mathio.storekit. Production reads the same product IDs
// from App Store Connect. No external dependencies.

@MainActor
@Observable
final class PremiumStore {
    static let weeklyID    = "mathio_weekly"
    static let annualID    = "mathio_annual"
    static let retentionID = "mathio_retention"
    private static let allIDs: [String] = [weeklyID, annualID, retentionID]

    var isPremium: Bool = false
    var weekly:    Product?
    var annual:    Product?
    var retention: Product?
    var loaded: Bool = false
    var purchaseInFlight: Bool = false

    init() {
        Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let tx) = update {
                    await tx.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        await loadProducts()
        await refreshEntitlements()
        loaded = true
    }

    private func loadProducts() async {
        do {
            let products = try await Product.products(for: Self.allIDs)
            for product in products {
                switch product.id {
                case Self.weeklyID:    weekly = product
                case Self.annualID:    annual = product
                case Self.retentionID: retention = product
                default: break
                }
            }
        } catch {
            // UI falls back to placeholder prices.
        }
    }

    func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let tx) = result else { continue }
            if Self.allIDs.contains(tx.productID),
               tx.revocationDate == nil,
               tx.expirationDate.map({ $0 > .now }) ?? true {
                active = true
            }
        }
        isPremium = active
    }

    func purchase(_ product: Product) async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let tx) = verification {
                await tx.finish()
                await refreshEntitlements()
            }
        } catch {
            // Silent — store errors and user cancels are equivalent here.
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    /// Headline price line: "$1.15 / week" derived from the annual price.
    func annualPerWeek() -> String? {
        guard let p = annual else { return nil }
        let perWeek = (p.price as NSDecimalNumber).doubleValue / 52.0
        return Decimal(perWeek).formatted(p.priceFormatStyle.precision(.fractionLength(2)))
    }
}

// MARK: - Notifications

enum NotificationManager {
    static let dailyId = "mathio.daily.reminder"

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch { return false }
    }

    static func scheduleDailyReminder(hour: Int = 19, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [dailyId])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Keep your streak alive")
        content.body  = String(localized: "Two minutes of math today is enough.")
        content.sound = .default
        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: dailyId, content: content, trigger: trigger)
        center.add(request)
    }

    static func cancelDailyReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [dailyId])
    }
}

// MARK: - Root

struct RootView: View {
    @Bindable var store: Store
    @Bindable var premiumStore: PremiumStore
    @Bindable var settings: UserSettings
    @State private var showPaywall = false

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            if !store.hasOnboarded {
                OnboardingView(store: store) {
                    store.completeOnboarding()
                    showPaywall = true
                }
                .transition(.opacity)
            } else {
                HomeView(store: store, premiumStore: premiumStore, settings: settings)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(settings.theme.preferredColorScheme)
        .animation(.easeInOut(duration: 0.25), value: store.hasOnboarded)
        .sheet(isPresented: $showPaywall) {
            PaywallView(premiumStore: premiumStore, mode: .onboarding)
        }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    let store: Store
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                ZStack {
                    Circle().fill(Palette.terracottaSoft).frame(width: 140, height: 140)
                    Text("π")
                        .font(.system(size: 80, weight: .bold, design: .serif))
                        .foregroundStyle(Palette.terracotta)
                }
                .accessibilityHidden(true)

                VStack(spacing: 12) {
                    Text("Math, made simple.")
                        .font(.displayL).foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                    Text("Algebra to calculus. One small step a day.")
                        .font(.bodyL).foregroundStyle(Palette.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            Spacer()
            VStack(spacing: 12) {
                bulletRow("brain.head.profile", "Adaptive — we pick what's next for you")
                bulletRow("lightbulb.max", "Step-by-step solutions, every time")
                bulletRow("flame.fill", "Build a daily streak, no leaderboards")
            }
            .padding(.horizontal, 28).padding(.bottom, 32)

            PrimaryButton(title: "Get started", icon: "arrow.right", action: onContinue)
                .padding(.horizontal, 24).padding(.bottom, 32)
        }
    }

    private func bulletRow(_ icon: String, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(Palette.terracotta)
                .frame(width: 28, height: 28)
                .background(Palette.terracottaSoft)
                .clipShape(Circle())
                .accessibilityHidden(true)
            Text(text).font(.bodyL).foregroundStyle(Palette.ink)
            Spacer()
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @Bindable var store: Store
    @Bindable var premiumStore: PremiumStore
    @Bindable var settings: UserSettings

    @State private var presented: Lesson?
    @State private var presentedTopic: Topic?
    @State private var showStats = false
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showFormulas = false
    @State private var showReview = false

    private var topics: [Topic] { Curriculum.topics }
    private var nextUp: (Topic, Lesson)? { store.nextLesson(in: topics, premium: premiumStore.isPremium) }
    private var reviewCount: Int { store.reviewQueue(in: topics).count }

    /// Set by `PracticeMathIntent` (Siri / Spotlight). Honored once on appear.
    private static let pendingPracticeKey = "mathio.intent.pendingPractice"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    DailyGoalView(progress: store.correctToday(), goal: settings.dailyGoal)
                    if reviewCount > 0 { reviewBanner }
                    nextUpCard
                    topicsList
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            .background(Palette.background)
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $presentedTopic) { topic in
                TopicView(topic: topic, store: store, premiumStore: premiumStore) { lesson in
                    presentedTopic = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        presented = lesson
                    }
                }
            }
            .navigationDestination(item: $presented) { lesson in
                LessonView(lesson: lesson, store: store)
            }
            .navigationDestination(isPresented: $showReview) {
                PracticeView(lesson: reviewLesson(), store: store, isReview: true)
            }
            .sheet(isPresented: $showStats)    { StatsView(store: store, topics: topics) }
            .sheet(isPresented: $showSettings) { SettingsView(store: store, premiumStore: premiumStore, settings: settings) }
            .sheet(isPresented: $showPaywall)  { PaywallView(premiumStore: premiumStore, mode: .upgrade) }
            .sheet(isPresented: $showFormulas) { FormulaReferenceView(store: store, topics: topics) }
            .onAppear(perform: handlePendingIntent)
        }
    }

    /// If launched via Siri / Spotlight "Practice Math", jump straight into
    /// the review queue (or the suggested next lesson if nothing is due).
    private func handlePendingIntent() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.pendingPracticeKey) else { return }
        defaults.set(false, forKey: Self.pendingPracticeKey)
        if reviewCount > 0 {
            showReview = true
        } else if let (_, lesson) = nextUp,
                  premiumStore.isPremium || lesson.isFree(in: topics.first { $0.lessons.contains(lesson) } ?? topics[0]) {
            presented = lesson
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mathio")
                    .font(.displayM).foregroundStyle(Palette.ink)
                Text(greeting)
                    .font(.bodyM).foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            if store.streakDays > 0 { StreakBadge(days: store.streakDays) }
            IconButton(symbol: "book.closed", label: "Formula reference") { showFormulas = true }
            IconButton(symbol: "chart.bar.xaxis", label: "Statistics") { showStats = true }
            IconButton(symbol: "gearshape", label: "Settings") { showSettings = true }
        }
        .padding(.top, 8)
    }

    private var greeting: LocalizedStringResource {
        let h = Calendar.current.component(.hour, from: .now)
        if h < 12 { return "Good morning." }
        if h < 18 { return "Ready to think?" }
        return "Evening session?"
    }

    private var reviewBanner: some View {
        Button { showReview = true } label: {
            Card(padding: 16, background: Palette.amberSoft) {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.terracotta)
                        .frame(width: 36, height: 36)
                        .background(Palette.terracottaSoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Review due").font(.titleM).foregroundStyle(Palette.ink)
                        Text("\(reviewCount) questions to refresh")
                            .font(.bodyM).foregroundStyle(Palette.inkSoft)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Palette.inkFaint)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var nextUpCard: some View {
        if let (topic, lesson) = nextUp {
            Button {
                if !premiumStore.isPremium && !lesson.isFree(in: topic) {
                    showPaywall = true
                } else {
                    presented = lesson
                }
            } label: {
                Card(padding: 24, background: Palette.ink) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Continue").textCase(.uppercase).tracking(1.4)
                                .font(.label).foregroundStyle(Palette.amber)
                            Spacer()
                            if !premiumStore.isPremium && !lesson.isFree(in: topic) {
                                Image(systemName: "lock.fill").foregroundStyle(Palette.amber)
                            }
                        }
                        Text(lesson.title).font(.displayM).foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Image(systemName: topic.icon).font(.system(size: 13))
                            Text(topic.title).font(.label)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                        HStack {
                            ProgressBar(progress: store.mastery(for: lesson),
                                        color: Palette.amber, height: 6)
                                .frame(maxWidth: 180)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 44, height: 44)
                                .background(Palette.amber).clipShape(Circle())
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Continue with \(lesson.title) in \(topic.title)"))
        } else {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("All mastered").font(.titleM).foregroundStyle(Palette.ink)
                    Text("Pick any topic to keep practicing.")
                        .font(.bodyM).foregroundStyle(Palette.inkSoft)
                }
            }
        }
    }

    private var topicsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "All topics").padding(.leading, 4)
            ForEach(topics) { topic in
                Button { presentedTopic = topic } label: {
                    TopicRow(topic: topic, mastery: store.mastery(for: topic))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("\(topic.title), \(Int(store.mastery(for: topic) * 100)) percent mastered"))
            }
        }
    }

    /// Build a synthetic lesson from the spaced-repetition queue.
    private func reviewLesson() -> Lesson {
        let qs = store.reviewQueue(in: topics, limit: 10)
        return Lesson(
            id: "__review__",
            title: "Review",
            intro: "Refresh what you've learned.",
            formulas: [],
            questions: qs
        )
    }
}

// MARK: - Topic row

struct TopicRow: View {
    let topic: Topic
    let mastery: Double

    var body: some View {
        Card {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(topic.color.opacity(0.15)).frame(width: 50, height: 50)
                    Image(systemName: topic.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(topic.color)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(topic.title).font(.titleM).foregroundStyle(Palette.ink)
                    Text("\(topic.lessons.count) lessons · \(Int(mastery * 100))%")
                        .font(.bodyM).foregroundStyle(Palette.inkSoft)
                    ProgressBar(progress: mastery, color: topic.color, height: 4)
                }
                Image(systemName: "chevron.right").foregroundStyle(Palette.inkFaint)
            }
        }
    }
}

// MARK: - Topic detail

struct TopicView: View {
    let topic: Topic
    @Bindable var store: Store
    @Bindable var premiumStore: PremiumStore
    let onLessonTap: (Lesson) -> Void
    @State private var showPaywall = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(topic.color.opacity(0.15)).frame(width: 56, height: 56)
                        Image(systemName: topic.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(topic.color)
                    }
                    VStack(alignment: .leading) {
                        Text(topic.title).font(.displayM).foregroundStyle(Palette.ink)
                        Text(topic.subtitle).font(.bodyM).foregroundStyle(Palette.inkSoft)
                    }
                }
                .padding(.top, 4)

                ForEach(Array(topic.lessons.enumerated()), id: \.element.id) { index, lesson in
                    let locked = !premiumStore.isPremium && index > 0
                    Button {
                        if locked { showPaywall = true } else { onLessonTap(lesson) }
                    } label: {
                        LessonRow(
                            lesson: lesson,
                            mastery: store.mastery(for: lesson),
                            color: topic.color,
                            locked: locked
                        )
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.background)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView(premiumStore: premiumStore, mode: .upgrade)
        }
    }
}

extension Lesson {
    /// First lesson of a topic is always free.
    func isFree(in topic: Topic) -> Bool {
        topic.lessons.first?.id == self.id
    }
}

struct LessonRow: View {
    let lesson: Lesson
    let mastery: Double
    let color: Color
    let locked: Bool

    var body: some View {
        Card {
            HStack(spacing: 14) {
                ProgressRing(progress: mastery, size: 36, lineWidth: 4, color: color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(lesson.title).font(.titleM).foregroundStyle(Palette.ink)
                    Text("\(lesson.questions.count) questions")
                        .font(.bodyM).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Image(systemName: locked ? "lock.fill" : "chevron.right")
                    .foregroundStyle(Palette.inkFaint)
            }
        }
    }
}

// MARK: - Lesson view

struct LessonView: View {
    let lesson: Lesson
    @Bindable var store: Store
    @State private var showPractice = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(lesson.title).font(.displayM).foregroundStyle(Palette.ink)
                    .padding(.top, 4)
                Text(lesson.intro).font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .padding(.bottom, 4)

                ForEach(lesson.formulas, id: \.id) { formula in
                    FormulaCard(formula: formula, store: store)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, 20)
        }
        .background(Palette.background)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Start practice", icon: "arrow.right") {
                showPractice = true
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .background(LinearGradient(
                colors: [Palette.background.opacity(0), Palette.background],
                startPoint: .top, endPoint: .bottom
            ))
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showPractice) {
            PracticeView(lesson: lesson, store: store, isReview: false)
        }
    }
}

struct FormulaCard: View {
    let formula: Formula
    @Bindable var store: Store

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(formula.name).font(.titleM).foregroundStyle(Palette.ink)
                    Spacer()
                    Button {
                        store.toggleBookmark(formula.key)
                    } label: {
                        Image(systemName: store.isBookmarked(formula.key) ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(store.isBookmarked(formula.key) ? Palette.terracotta : Palette.inkFaint)
                    }
                    .accessibilityLabel(Text(store.isBookmarked(formula.key)
                        ? "Remove bookmark" : "Bookmark formula"))
                }
                MathBlock(raw: formula.math)
                Text(formula.explanation).font(.bodyM).foregroundStyle(Palette.inkSoft)
            }
        }
    }
}

// MARK: - Practice

struct PracticeView: View {
    let lesson: Lesson
    @Bindable var store: Store
    let isReview: Bool
    @Environment(\.dismiss) private var dismiss

    @State private var index: Int = 0
    @State private var input: String = ""
    @State private var selectedChoice: Int? = nil
    @State private var trueFalseValue: Bool? = nil
    @State private var state: AnswerState = .pending
    @State private var showHint: Bool = false
    @State private var sessionCorrect: Int = 0
    @State private var showQuitConfirm: Bool = false
    @State private var didCelebrate: Bool = false

    enum AnswerState: Equatable { case pending, correct, incorrect }

    private var question: Question? {
        guard index < lesson.questions.count else { return nil }
        return lesson.questions[index]
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                progressBar
                ScrollView {
                    if lesson.questions.isEmpty {
                        emptyView
                            .padding(20)
                    } else if let q = question {
                        questionBody(q).padding(20)
                    } else {
                        completionView.padding(20)
                    }
                }
                if question != nil { bottomBar }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if shouldConfirmQuit { showQuitConfirm = true }
                    else { dismiss() }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel(Text("Close practice"))
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: state == .correct)
        .sensoryFeedback(.error, trigger: state == .incorrect)
        .confirmationDialog("Quit this practice?",
                            isPresented: $showQuitConfirm, titleVisibility: .visible) {
            Button("Keep practicing", role: .cancel) { }
            Button("Quit", role: .destructive) { dismiss() }
        } message: {
            Text("You're at \(index + 1) of \(lesson.questions.count). Progress on answered questions is saved.")
        }
    }

    /// Confirm quit only if the user is mid-lesson (not at the very start, not at completion).
    private var shouldConfirmQuit: Bool {
        guard !lesson.questions.isEmpty else { return false }
        if index >= lesson.questions.count { return false }   // at completion screen
        if index == 0 && state == .pending { return false }   // hasn't started
        return true
    }

    private var progressBar: some View {
        // Show "current/total" — current = index+1 while answering, capped at total.
        let total = max(1, lesson.questions.count)
        let current = min(index + 1, total)
        return ProgressBar(
            progress: Double(current) / Double(total),
            color: isReview ? Palette.calculus : Palette.terracotta,
            height: 4
        )
        .padding(.horizontal, 20).padding(.top, 8)
        .accessibilityLabel(Text("Question \(current) of \(total)"))
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 60)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60)).foregroundStyle(Palette.success)
            Text("Nothing to review").font(.displayM).foregroundStyle(Palette.ink)
            Text("Come back tomorrow — your spaced-repetition queue is empty.")
                .font(.bodyL).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
            PrimaryButton(title: "Done", icon: "checkmark") { dismiss() }
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func questionBody(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                Text(q.prompt).font(.titleL).foregroundStyle(Palette.ink)
                if let math = q.math { MathBlock(raw: math) }
            }

            switch q.kind {
            case .multipleChoice(let options, _):
                VStack(spacing: 10) {
                    ForEach(Array(options.enumerated()), id: \.offset) { i, opt in
                        ChoiceRow(
                            label: opt.label, math: opt.math,
                            selected: selectedChoice == i,
                            state: stateForChoice(i)
                        ) {
                            if state == .pending { selectedChoice = i }
                        }
                    }
                }
            case .freeAnswer:
                FreeAnswerField(text: $input, locked: state != .pending)
            case .trueFalse:
                HStack(spacing: 12) {
                    TrueFalseButton(label: "True", selected: trueFalseValue == true,
                                    state: stateForTrueFalse(true)) {
                        if state == .pending { trueFalseValue = true }
                    }
                    TrueFalseButton(label: "False", selected: trueFalseValue == false,
                                    state: stateForTrueFalse(false)) {
                        if state == .pending { trueFalseValue = false }
                    }
                }
            }

            if showHint {
                Card(padding: 16, background: Palette.amberSoft) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lightbulb.max.fill")
                            .foregroundStyle(Palette.warning)
                        Text(q.hint).font(.bodyM).foregroundStyle(Palette.ink)
                    }
                }
            }

            if state == .incorrect {
                solutionCard(q)
            } else if state == .correct {
                Card(padding: 16, background: Palette.surfaceMuted) {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.success)
                        Text("Nice. Tap continue.")
                            .font(.bodyM).foregroundStyle(Palette.ink)
                    }
                }
            }
        }
    }

    private func solutionCard(_ q: Question) -> some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.error)
                    Text("Not quite — here's why:")
                        .font(.label).fontWeight(.semibold).foregroundStyle(Palette.ink)
                }
                ForEach(Array(q.solutionSteps.enumerated()), id: \.offset) { i, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(i + 1).")
                            .font(.bodyM).fontWeight(.semibold)
                            .foregroundStyle(Palette.terracotta)
                        Text(step).font(.bodyM).foregroundStyle(Palette.ink)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button { showHint.toggle() } label: {
                Image(systemName: showHint ? "lightbulb.max.fill" : "lightbulb.max")
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 54, height: 54)
                    .background(Palette.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel(Text("Show hint"))

            switch state {
            case .pending:
                PrimaryButton(title: "Check", enabled: canCheck) { check() }
            case .correct, .incorrect:
                PrimaryButton(title: "Continue", icon: "arrow.right") { advance() }
            }
        }
        .padding(.horizontal, 20).padding(.bottom, 16).padding(.top, 8)
        .background(Palette.background)
    }

    private var completionView: some View {
        ZStack {
            if didCelebrate { Confetti().allowsHitTesting(false) }

            VStack(spacing: 24) {
                Spacer(minLength: 40)
                ZStack {
                    Circle().fill(Palette.amberSoft).frame(width: 120, height: 120)
                    Image(systemName: ribbon)
                        .font(.system(size: 50)).foregroundStyle(Palette.terracotta)
                }
                .accessibilityHidden(true)
                Text(isReview ? "Review complete" : "Lesson complete")
                    .font(.displayM).foregroundStyle(Palette.ink)
                Text(scoreLine)
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                if isPerfect {
                    Text("Perfect run.")
                        .font(.titleM).foregroundStyle(Palette.terracotta)
                        .padding(.top, -8)
                }
                PrimaryButton(title: "Done", icon: "checkmark") { dismiss() }
                    .padding(.top, 12)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !didCelebrate, lesson.questions.count > 0 else { return }
            didCelebrate = true
            if isPerfect {
                AudioServicesPlaySystemSound(1025)   // Tink — gentle success ping
            }
        }
    }

    private var isPerfect: Bool {
        sessionCorrect == lesson.questions.count && lesson.questions.count > 0
    }

    private var ribbon: String {
        isPerfect ? "rosette" : "sparkles"
    }

    private var scoreLine: LocalizedStringResource {
        if lesson.questions.isEmpty {
            return "Nothing to score."
        }
        return "You scored \(sessionCorrect) out of \(lesson.questions.count)."
    }

    private var canCheck: Bool {
        guard let q = question else { return false }
        switch q.kind {
        case .multipleChoice: return selectedChoice != nil
        case .freeAnswer:     return !input.trimmingCharacters(in: .whitespaces).isEmpty
        case .trueFalse:      return trueFalseValue != nil
        }
    }

    private func stateForChoice(_ i: Int) -> AnswerState {
        guard let q = question else { return .pending }
        if state == .pending { return .pending }
        if case .multipleChoice(_, let correct) = q.kind {
            if i == correct { return .correct }
            if i == selectedChoice { return .incorrect }
        }
        return .pending
    }

    private func stateForTrueFalse(_ value: Bool) -> AnswerState {
        guard let q = question else { return .pending }
        if state == .pending { return .pending }
        if case .trueFalse(let answer) = q.kind {
            if value == answer { return .correct }
            if value == trueFalseValue { return .incorrect }
        }
        return .pending
    }

    private func check() {
        guard let q = question else { return }
        let isCorrect: Bool
        switch q.kind {
        case .multipleChoice(_, let correctIndex):
            isCorrect = selectedChoice == correctIndex
        case .freeAnswer(let accepted):
            isCorrect = MathInput.matches(input, accepted: accepted)
        case .trueFalse(let answer):
            isCorrect = trueFalseValue == answer
        }
        state = isCorrect ? .correct : .incorrect
        if isCorrect { sessionCorrect += 1 }
        store.record(questionId: q.id, correct: isCorrect)
    }

    private func advance() {
        index += 1
        input = ""; selectedChoice = nil; trueFalseValue = nil
        state = .pending; showHint = false
    }
}

// MARK: - Confetti
//
// Pure-SwiftUI particle effect — 60 colored dots that drift down and fade.
// Lightweight (no SpriteKit), runs once and stops. ~30ms cost on iPhone 17.

private struct Confetti: View {
    @State private var phase: CGFloat = 0
    private let colors: [Color] = [
        Palette.terracotta, Palette.amber, Palette.calculus,
        Palette.geometry, Palette.stats, Palette.precalc,
    ]
    private let count = 60

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(0..<count, id: \.self) { i in
                    let seed = Double(i)
                    let xStart = Double.random(in: 0...1, seed: seed * 1.13) * geo.size.width
                    let drift  = Double.random(in: -0.08...0.08, seed: seed * 7.7) * geo.size.width
                    let delay  = Double.random(in: 0...0.4, seed: seed * 3.1)
                    let size   = CGFloat.random(in: 4...8, seed: seed * 2.3)
                    let color  = colors[i % colors.count]

                    Rectangle()
                        .fill(color)
                        .frame(width: size, height: size * 0.6)
                        .rotationEffect(.degrees(Double(i) * 23 + Double(phase * 360)))
                        .position(
                            x: xStart + drift * Double(phase),
                            y: -20 + Double(phase) * (geo.size.height + 40)
                        )
                        .opacity(1 - Double(phase))
                        .animation(.easeOut(duration: 1.6).delay(delay), value: phase)
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 1.6)) { phase = 1 }
            }
        }
    }
}

private extension Double {
    /// Deterministic pseudo-random in a range — keeps Confetti looking the same
    /// every time the same seed value is used for a particle index.
    static func random(in range: ClosedRange<Double>, seed: Double) -> Double {
        var x = seed.truncatingRemainder(dividingBy: 1.0)
        x = abs(sin(seed * 12.9898) * 43758.5453)
        x = x.truncatingRemainder(dividingBy: 1.0)
        return range.lowerBound + (range.upperBound - range.lowerBound) * x
    }
}

private extension CGFloat {
    static func random(in range: ClosedRange<CGFloat>, seed: Double) -> CGFloat {
        CGFloat(Double.random(in: Double(range.lowerBound)...Double(range.upperBound), seed: seed))
    }
}

// MARK: - Practice subviews

struct ChoiceRow: View {
    let label: LocalizedStringResource
    let math: String?
    let selected: Bool
    let state: PracticeView.AnswerState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: marker).foregroundStyle(markerColor)
                if let math {
                    MathText(raw: math, size: 18)
                } else {
                    Text(label).font(.bodyL).foregroundStyle(Palette.ink)
                }
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var marker: String {
        switch state {
        case .pending:   selected ? "circle.inset.filled" : "circle"
        case .correct:   "checkmark.circle.fill"
        case .incorrect: "xmark.circle.fill"
        }
    }
    private var markerColor: Color {
        switch state {
        case .pending:   selected ? Palette.terracotta : Palette.inkFaint
        case .correct:   Palette.success
        case .incorrect: Palette.error
        }
    }
    private var background: Color {
        switch state {
        case .correct:   Palette.success.opacity(0.08)
        case .incorrect: Palette.error.opacity(0.06)
        case .pending:   selected ? Palette.terracottaSoft.opacity(0.5) : Palette.surface
        }
    }
    private var borderColor: Color {
        switch state {
        case .correct:   Palette.success.opacity(0.4)
        case .incorrect: Palette.error.opacity(0.4)
        case .pending:   selected ? Palette.terracotta.opacity(0.4) : Palette.hairline
        }
    }
    private var borderWidth: CGFloat { state == .pending ? 0.5 : 1 }
}

struct TrueFalseButton: View {
    let label: LocalizedStringResource
    let selected: Bool
    let state: PracticeView.AnswerState
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label).font(.titleM).foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 60)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(borderColor, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch state {
        case .correct:   Palette.success.opacity(0.1)
        case .incorrect: Palette.error.opacity(0.08)
        case .pending:   selected ? Palette.terracottaSoft.opacity(0.5) : Palette.surface
        }
    }
    private var borderColor: Color {
        switch state {
        case .correct:   Palette.success.opacity(0.5)
        case .incorrect: Palette.error.opacity(0.5)
        case .pending:   selected ? Palette.terracotta : Palette.hairline
        }
    }
}

struct FreeAnswerField: View {
    @Binding var text: String
    let locked: Bool
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Your answer", text: $text)
                    .focused($focused)
                    .font(.system(size: 22, weight: .regular, design: .serif))
                    .foregroundStyle(Palette.ink)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(locked)
                if !text.isEmpty && !locked {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear answer"))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(focused ? Palette.terracotta : Palette.hairline, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("Type plain text. e.g. 6x+2, sqrt(2), pi")
                .font(.caption).foregroundStyle(Palette.inkFaint).padding(.leading, 4)
        }
    }
}

// MARK: - Stats

struct StatsView: View {
    @Bindable var store: Store
    let topics: [Topic]
    @Environment(\.dismiss) private var dismiss

    private var totalCorrect: Int {
        store.answered.values.reduce(0) { $0 + $1.correct }
    }
    private var overallMastery: Double {
        guard !topics.isEmpty else { return 0 }
        return topics.reduce(0.0) { $0 + store.mastery(for: $1) } / Double(topics.count)
    }
    private var weakest: Topic? {
        topics.filter { store.mastery(for: $0) < 1.0 }
              .min { store.mastery(for: $0) < store.mastery(for: $1) }
    }
    private var hasAnyProgress: Bool {
        store.answered.values.contains { $0.attempts > 0 }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerStats
                    activityCard
                    masteryCard
                    if hasAnyProgress, let weakest { focusCard(weakest) }
                }
                .padding(20)
            }
            .background(Palette.background)
            .navigationTitle("Your progress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.foregroundStyle(Palette.ink)
                }
            }
        }
    }

    private var headerStats: some View {
        HStack(spacing: 12) {
            statTile(value: "\(store.streakDays)", label: "Day streak",
                     icon: "flame.fill", color: Palette.terracotta)
            statTile(value: "\(store.streakFreezes)", label: "Freezes",
                     icon: "snowflake", color: Palette.calculus)
            statTile(value: "\(Int(overallMastery * 100))%", label: "Mastery",
                     icon: "graduationcap.fill", color: Palette.success)
        }
    }

    private func statTile(value: String, label: LocalizedStringResource,
                          icon: String, color: Color) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).foregroundStyle(color)
                Text(value).font(.displayM).foregroundStyle(Palette.ink)
                Text(label).font(.caption).foregroundStyle(Palette.inkSoft)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(value) \(label)"))
    }

    private var activityCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "Activity")
                CalendarHeatmap(activity: store.dailyActivity(), weeks: 12)
            }
        }
    }

    private var masteryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "By topic")
                ForEach(topics) { topic in
                    HStack(spacing: 12) {
                        Image(systemName: topic.icon)
                            .foregroundStyle(topic.color).frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(topic.title).font(.bodyL).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(Int(store.mastery(for: topic) * 100))%")
                                    .font(.bodyM).foregroundStyle(Palette.inkSoft)
                            }
                            ProgressBar(progress: store.mastery(for: topic),
                                        color: topic.color, height: 4)
                        }
                    }
                }
            }
        }
    }

    private func focusCard(_ topic: Topic) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(title: "Focus next")
                HStack(spacing: 12) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 22))
                        .foregroundStyle(topic.color)
                        .frame(width: 44, height: 44)
                        .background(topic.color.opacity(0.15)).clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(topic.title).font(.titleM).foregroundStyle(Palette.ink)
                        Text("\(Int(store.mastery(for: topic) * 100))% mastery")
                            .font(.bodyM).foregroundStyle(Palette.inkSoft)
                    }
                }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Bindable var store: Store
    @Bindable var premiumStore: PremiumStore
    @Bindable var settings: UserSettings
    @Environment(\.dismiss) private var dismiss
    @State private var showRetention = false
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("Daily practice") {
                    Stepper(value: $settings.dailyGoal, in: 1...30) {
                        HStack {
                            Text("Daily goal")
                            Spacer()
                            Text("\(settings.dailyGoal) correct")
                                .foregroundStyle(Palette.inkSoft)
                        }
                    }
                    Toggle("Daily reminder at 19:00", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { newValue in
                            settings.notificationsEnabled = newValue
                            Task { await applyNotificationPreference(newValue) }
                        }
                    ))
                }

                Section("Appearance") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(UserSettings.Theme.allCases) { theme in
                            Text(theme.label).tag(theme)
                        }
                    }
                }

                Section("Subscription") {
                    if premiumStore.isPremium {
                        HStack {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(Palette.success)
                            Text("Mathio Premium")
                        }
                        Button(role: .destructive) {
                            showRetention = true
                        } label: {
                            Text("Cancel subscription")
                        }
                    } else {
                        NavigationLink("Upgrade to Premium") {
                            PaywallView(premiumStore: premiumStore, mode: .upgrade)
                        }
                    }
                    Button("Restore purchases") {
                        Task { await premiumStore.restore() }
                    }
                }

                Section("Practice") {
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Text("Reset all progress")
                    }
                }

                Section("About") {
                    Link("Privacy policy",   destination: URL(string: "https://meloxkgz-ship-it.github.io/mathio/privacy")!)
                    Link("Terms of service", destination: URL(string: "https://meloxkgz-ship-it.github.io/mathio/terms")!)
                    Link("Support",          destination: URL(string: "mailto:meloxkgz@icloud.com")!)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRetention) {
                PaywallView(premiumStore: premiumStore, mode: .retention)
            }
            .confirmationDialog("Reset all progress?",
                                isPresented: $showResetConfirm,
                                titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) { store.reset() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This deletes your answers and streak. Cannot be undone.")
            }
        }
    }

    private func applyNotificationPreference(_ enabled: Bool) async {
        if enabled {
            let granted = await NotificationManager.requestAuthorization()
            if granted {
                NotificationManager.scheduleDailyReminder()
            } else {
                settings.notificationsEnabled = false
            }
        } else {
            NotificationManager.cancelDailyReminder()
        }
    }
}

// MARK: - Formula reference

struct FormulaReferenceView: View {
    @Bindable var store: Store
    let topics: [Topic]
    @Environment(\.dismiss) private var dismiss
    @State private var showOnlyBookmarked = false

    private var entries: [(Topic, Lesson, Formula)] {
        topics.flatMap { topic in
            topic.lessons.flatMap { lesson in
                lesson.formulas.map { (topic, lesson, $0) }
            }
        }
    }
    private var filtered: [(Topic, Lesson, Formula)] {
        showOnlyBookmarked
            ? entries.filter { store.isBookmarked($0.2.key) }
            : entries
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Picker("", selection: $showOnlyBookmarked) {
                        Text("All").tag(false)
                        Text("Bookmarked").tag(true)
                    }
                    .pickerStyle(.segmented)

                    if filtered.isEmpty {
                        empty
                    } else {
                        ForEach(filtered, id: \.2.id) { topic, lesson, formula in
                            referenceRow(topic: topic, lesson: lesson, formula: formula)
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.background)
            .navigationTitle("Formulas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func referenceRow(topic: Topic, lesson: Lesson, formula: Formula) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: topic.icon).font(.system(size: 12))
                            .foregroundStyle(topic.color)
                        Text(topic.title).font(.label).foregroundStyle(Palette.inkFaint)
                    }
                    Spacer()
                    Button {
                        store.toggleBookmark(formula.key)
                    } label: {
                        Image(systemName: store.isBookmarked(formula.key)
                              ? "bookmark.fill" : "bookmark")
                            .foregroundStyle(store.isBookmarked(formula.key)
                                           ? Palette.terracotta : Palette.inkFaint)
                    }
                    .accessibilityLabel(Text(store.isBookmarked(formula.key)
                        ? "Remove bookmark" : "Bookmark formula"))
                }
                Text(formula.name).font(.titleM).foregroundStyle(Palette.ink)
                MathBlock(raw: formula.math)
                Text(formula.explanation).font(.bodyM).foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 36)).foregroundStyle(Palette.inkFaint)
            Text("No bookmarks yet").font(.titleM).foregroundStyle(Palette.ink)
            Text("Tap the bookmark on any formula to save it here.")
                .font(.bodyM).foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 60)
    }
}

// MARK: - Paywall

struct PaywallView: View {
    @Bindable var premiumStore: PremiumStore
    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Plan = .annual

    enum Mode { case onboarding, upgrade, retention }
    enum Plan { case weekly, annual, retention }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    icon
                    headline
                    bullets
                    plans
                    if mode != .retention { footnote }
                }
                .padding(.horizontal, 22).padding(.top, 60).padding(.bottom, 140)
            }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.inkSoft)
                    .frame(width: 32, height: 32)
                    .background(Palette.surfaceMuted)
                    .clipShape(Circle())
            }
            .padding(.top, 12).padding(.trailing, 16)
            .accessibilityLabel(Text("Close"))

            VStack {
                Spacer()
                cta
                    .padding(.horizontal, 22).padding(.bottom, 22)
                    .background(LinearGradient(
                        colors: [Palette.background.opacity(0), Palette.background],
                        startPoint: .top, endPoint: .bottom
                    ))
            }
        }
    }

    private var icon: some View {
        ZStack {
            Circle().fill(Palette.terracottaSoft).frame(width: 80, height: 80)
            Image(systemName: "infinity")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(Palette.terracotta)
        }
        .accessibilityHidden(true)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch mode {
            case .onboarding, .upgrade:
                Text("Unlock all of Mathio").font(.displayL).foregroundStyle(Palette.ink)
                Text("Every topic. Every lesson. No ads.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
            case .retention:
                Text("Wait — special offer").font(.displayL).foregroundStyle(Palette.ink)
                Text("Stay one more year for 25 % off.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("books.vertical.fill", "All topics: algebra, calculus, geometry, trig")
            row("brain.head.profile", "Adaptive — picks the right next lesson")
            row("arrow.triangle.2.circlepath", "Spaced repetition keeps it stuck")
            row("lightbulb.max.fill", "Step-by-step solutions for every wrong answer")
            row("flame.fill", "Daily streak that actually motivates")
        }
    }

    private func row(_ icon: String, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Palette.terracotta)
            Text(text).font(.bodyL).foregroundStyle(Palette.ink)
        }
    }

    @ViewBuilder
    private var plans: some View {
        switch mode {
        case .retention:
            retentionPlanCard
        default:
            VStack(spacing: 10) {
                planCard(.annual, badge: "Best value")
                planCard(.weekly, badge: nil)
            }
        }
    }

    private func planCard(_ plan: Plan, badge: LocalizedStringResource?) -> some View {
        Button { selected = plan } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected == plan ? "circle.inset.filled" : "circle")
                    .foregroundStyle(selected == plan ? Palette.terracotta : Palette.inkFaint)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(plan == .annual ? "Annual" : "Weekly")
                            .font(.titleM).foregroundStyle(Palette.ink)
                        if let badge {
                            Text(badge).font(.caption).fontWeight(.semibold)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Palette.amber)
                                .foregroundStyle(Palette.ink).clipShape(Capsule())
                        }
                    }
                    Text(planSubtitle(plan))
                        .font(.bodyM).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Text(planPrice(plan)).font(.titleM).foregroundStyle(Palette.ink)
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
            .background(Palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected == plan ? Palette.terracotta : Palette.hairline,
                            lineWidth: selected == plan ? 2 : 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var retentionPlanCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("ANNUAL · 25 % OFF").font(.label).foregroundStyle(Palette.terracotta)
                    Spacer()
                }
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text(retentionPrice).font(.displayL).foregroundStyle(Palette.ink)
                    Text("/ year").font(.bodyM).foregroundStyle(Palette.inkSoft)
                    Spacer()
                    Text(annualPrice).font(.bodyM).strikethrough()
                        .foregroundStyle(Palette.inkFaint)
                }
                Text("One-time offer. Locked in for 12 months.")
                    .font(.bodyM).foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private func planSubtitle(_ plan: Plan) -> String {
        switch plan {
        case .annual:
            if let pw = premiumStore.annualPerWeek() {
                return "7-day free trial, then \(pw) per week"
            }
            return "7-day free trial, then billed yearly"
        case .weekly:    return "3-day free trial, then weekly"
        case .retention: return ""
        }
    }

    private func planPrice(_ plan: Plan) -> String {
        switch plan {
        case .annual:    annualPrice
        case .weekly:    weeklyPrice
        case .retention: retentionPrice
        }
    }

    private var weeklyPrice: String    { premiumStore.weekly?.displayPrice ?? "$12.99" }
    private var annualPrice: String    { premiumStore.annual?.displayPrice ?? "$59.99" }
    private var retentionPrice: String { premiumStore.retention?.displayPrice ?? "$44.99" }

    /// Inline auto-renewal disclaimer that meets App Store guideline 3.1.2.
    /// Must remain visible on the paywall (not behind a sheet).
    private var footnote: some View {
        VStack(spacing: 6) {
            Text(disclaimerText)
                .font(.caption2)
                .foregroundStyle(Palette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private var disclaimerText: LocalizedStringResource {
        switch selected {
        case .annual:
            "Free for 7 days, then \(annualPrice)/year. Renews automatically unless cancelled at least 24 h before the period ends. Manage in Settings."
        case .weekly:
            "Free for 3 days, then \(weeklyPrice)/week. Renews automatically unless cancelled at least 24 h before the period ends. Manage in Settings."
        case .retention:
            ""
        }
    }

    private var cta: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: ctaTitle, icon: nil,
                          enabled: !premiumStore.purchaseInFlight) {
                Task { await purchase() }
            }
            HStack {
                Button("Restore") { Task { await premiumStore.restore() } }
                Spacer()
                Link("Terms", destination: URL(string: "https://meloxkgz-ship-it.github.io/mathio/terms")!)
                Spacer()
                Link("Privacy", destination: URL(string: "https://meloxkgz-ship-it.github.io/mathio/privacy")!)
            }
            .font(.caption).foregroundStyle(Palette.inkFaint)
        }
    }

    private var ctaTitle: LocalizedStringResource {
        switch mode {
        case .retention: return "Keep my access at 25 % off"
        default:
            return selected == .weekly
                ? "Start 3-day free trial"
                : "Start 7-day free trial"
        }
    }

    @MainActor
    private func purchase() async {
        let target: Product?
        switch mode {
        case .retention: target = premiumStore.retention ?? premiumStore.annual
        default:
            target = selected == .annual ? premiumStore.annual : premiumStore.weekly
        }
        guard let target else { dismiss(); return }
        await premiumStore.purchase(target)
        if premiumStore.isPremium { dismiss() }
    }
}
