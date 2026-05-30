import SwiftUI
import RevenueCat
import StoreKit
import UserNotifications
import AudioToolbox

// MARK: - Premium store
//
// RevenueCat-first subscription store. When a public RevenueCat SDK key is
// present in `RevenueCatAPIKey`, offerings, purchases, restore, and entitlement
// checks run through RevenueCat. Without a key, we keep the StoreKit 2 path as
// a local fallback so screenshots, previews, and App Review override still work.

enum PremiumPlan {
    case weekly
    case annual
    case retention
}

@MainActor
@Observable
final class PremiumStore {
    static let weeklyID    = "mathio_weekly"
    static let annualID    = "mathio_annual"
    static let retentionID = "mathio_retention"
    private static let allIDs: [String] = [weeklyID, annualID, retentionID]
    private static let entitlementIDs = ["premium", "plus"]
    private static var revenueCatConfigured = false

    /// `UserDefaults` key for the reviewer-override flag. Toggled by 7-tapping
    /// the version label in Settings — the documented reviewer demo path.
    /// Persisted so a relaunch during App Review keeps premium unlocked.
    private static let kReviewerOverride = "mathio.reviewer.override"

    /// True if a real subscription transaction is currently entitled.
    private var storeKitEntitlementActive: Bool = false
    private var revenueCatEntitlementActive: Bool = false

    /// True if the reviewer-override flag is set in `UserDefaults`. Survives
    /// relaunches; cleared by tapping the version label again 7 times or by
    /// "Reset all progress" in Settings.
    private(set) var reviewerOverride: Bool = UserDefaults.standard.bool(forKey: kReviewerOverride)

    /// Public premium gate. Gives access if **either** the App Store reports
    /// an active entitlement **or** the reviewer-override flag is set.
    var isPremium: Bool {
        revenueCatEntitlementActive || storeKitEntitlementActive || reviewerOverride
    }

    private(set) var revenueCatEnabled = false
    private(set) var purchaseMessage: LocalizedStringResource?

    private var weekly:    StoreKit.Product?
    private var annual:    StoreKit.Product?
    private var retention: StoreKit.Product?
    private var offerings: Offerings?
    var loaded: Bool = false
    var purchaseInFlight: Bool = false

    init() {
        revenueCatEnabled = Self.configureRevenueCatIfPossible()

        if !revenueCatEnabled {
            Task { [weak self] in
                for await update in Transaction.updates {
                    if case .verified(let tx) = update {
                        await tx.finish()
                        await self?.refreshEntitlements()
                    }
                }
            }
        }
        Task { [weak self] in await self?.refresh() }
    }

    func refresh() async {
        if revenueCatEnabled {
            await refreshRevenueCat()
        } else {
            await loadProducts()
            await refreshEntitlements()
        }
        loaded = true
    }

    /// Toggle the reviewer-override flag. Mutates `isPremium` in lockstep so
    /// any `@Observable` subscribers re-render. Used only by the 7-tap
    /// gesture on the version label in Settings.
    func toggleReviewerOverride() {
        reviewerOverride.toggle()
        UserDefaults.standard.set(reviewerOverride, forKey: Self.kReviewerOverride)
    }

    private static func configureRevenueCatIfPossible() -> Bool {
        guard let apiKey = revenueCatAPIKey else { return false }
        guard !revenueCatConfigured else { return true }

        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
        revenueCatConfigured = true
        return true
    }

    private static var revenueCatAPIKey: String? {
        let bundleValue = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String
        let envValue = ProcessInfo.processInfo.environment["REVENUECAT_API_KEY"]
        return [envValue, bundleValue]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty && !$0.contains("$(") && !$0.contains("REPLACE") && $0.hasPrefix("appl_") }
    }

    private func refreshRevenueCat() async {
        do {
            async let fetchedInfo = Purchases.shared.customerInfo()
            async let fetchedOfferings = Purchases.shared.offerings()
            let (customerInfo, offerings) = try await (fetchedInfo, fetchedOfferings)
            self.offerings = offerings
            apply(customerInfo: customerInfo)
            purchaseMessage = currentOffering == nil
                ? "Premium is temporarily unavailable. Please try again soon."
                : nil
        } catch {
            purchaseMessage = "Premium is temporarily unavailable. Please try again soon."
        }
    }

    private func apply(customerInfo: CustomerInfo) {
        revenueCatEntitlementActive = Self.entitlementIDs.contains {
            customerInfo.entitlements[$0]?.isActive == true
        }
    }

    private func loadProducts() async {
        do {
            let products = try await StoreKit.Product.products(for: Self.allIDs)
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
        storeKitEntitlementActive = active
    }

    func purchase(_ plan: PremiumPlan) async {
        purchaseInFlight = true
        purchaseMessage = nil
        defer { purchaseInFlight = false }

        if revenueCatEnabled {
            await purchaseRevenueCat(plan)
        } else {
            await purchaseStoreKit(plan)
        }
    }

    private func purchaseRevenueCat(_ plan: PremiumPlan) async {
        guard let package = package(for: plan) ?? package(for: .annual) else {
            purchaseMessage = "Premium is temporarily unavailable. Please try again soon."
            return
        }

        do {
            let (_, customerInfo, userCancelled) = try await Purchases.shared.purchase(package: package)
            guard !userCancelled else { return }
            apply(customerInfo: customerInfo)
            purchaseMessage = isPremium ? "Premium unlocked." : nil
        } catch {
            purchaseMessage = "Purchase could not be completed. Please try again."
        }
    }

    private func purchaseStoreKit(_ plan: PremiumPlan) async {
        let product: StoreKit.Product?
        switch plan {
        case .weekly:    product = weekly
        case .annual:    product = annual
        case .retention: product = retention ?? annual
        }
        guard let product else {
            purchaseMessage = "Premium is temporarily unavailable. Please try again soon."
            return
        }

        do {
            let result = try await product.purchase()
            if case .success(let verification) = result,
               case .verified(let tx) = verification {
                await tx.finish()
                await refreshEntitlements()
                purchaseMessage = isPremium ? "Premium unlocked." : nil
            }
        } catch {
            purchaseMessage = "Purchase could not be completed. Please try again."
        }
    }

    func restore() async {
        purchaseMessage = nil
        if revenueCatEnabled {
            do {
                let customerInfo = try await Purchases.shared.restorePurchases()
                apply(customerInfo: customerInfo)
                purchaseMessage = isPremium
                    ? "Purchases restored."
                    : "No active subscription found."
            } catch {
                purchaseMessage = "Restore failed. Please try again."
            }
        } else {
            try? await AppStore.sync()
            await refreshEntitlements()
            purchaseMessage = isPremium
                ? "Purchases restored."
                : "No active subscription found."
        }
    }

    func price(for plan: PremiumPlan, fallback: String) -> String {
        if let package = package(for: plan) {
            return package.storeProduct.localizedPriceString
        }

        let product: StoreKit.Product?
        switch plan {
        case .weekly:    product = weekly
        case .annual:    product = annual
        case .retention: product = retention
        }
        return product?.displayPrice ?? fallback
    }

    /// Headline price line: "$1.15 / week" derived from the annual price.
    func annualPerWeek() -> String? {
        guard let p = annual else { return nil }
        let perWeek = (p.price as NSDecimalNumber).doubleValue / 52.0
        return Decimal(perWeek).formatted(p.priceFormatStyle.precision(.fractionLength(2)))
    }

    private var currentOffering: Offering? {
        offerings?.current ?? offerings?.offering(identifier: "default")
    }

    private func package(for plan: PremiumPlan) -> Package? {
        switch plan {
        case .weekly:
            return currentOffering?.weekly ?? package(productID: Self.weeklyID)
        case .annual:
            return currentOffering?.annual ?? package(productID: Self.annualID)
        case .retention:
            return package(productID: Self.retentionID)
        }
    }

    private func package(productID: String) -> Package? {
        currentOffering?.availablePackages.first {
            $0.storeProduct.productIdentifier == productID
        }
    }
}

// MARK: - Notifications

enum NotificationManager {
    static let dailyId = "mathio.daily.reminder"
    private static let reminderHourKey = "mathio.notifications.hour"
    static var preferredHour: Int {
        UserDefaults.standard.object(forKey: reminderHourKey) as? Int ?? 19
    }

    static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch { return false }
    }

    static func scheduleDailyReminder(hour: Int = preferredHour, minute: Int = 0) {
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

    static func formattedTime(hour: Int = preferredHour) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? .now
        return date.formatted(date: .omitted, time: .shortened)
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
                OnboardingView(store: store, settings: settings) {
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
//
// Three-page paged intro. Every page is wrapped in a height-matched
// `ScrollView`, so content stays vertically centered on tall iPhones and
// scrolls instead of clipping on an iPhone SE. A fixed bottom bar carries
// the page dots and the primary action so the button never moves.

struct OnboardingView: View {
    let store: Store
    @Bindable var settings: UserSettings
    let onContinue: () -> Void

    @State private var page = 0
    @State private var selectedGoal: LearningGoal = .exam
    @State private var confidence = 3
    @State private var diagnosticAnswers: [Int?] = Array(repeating: nil, count: DiagnosticQuestion.samples.count)
    private let pageCount = 6

    private var diagnosticCorrect: Int {
        zip(diagnosticAnswers, DiagnosticQuestion.samples).reduce(0) { total, item in
            total + (item.0 == item.1.correctIndex ? 1 : 0)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            skipBar
            TabView(selection: $page) {
                welcomePage.tag(0)
                howItWorksPage.tag(1)
                goalPage.tag(2)
                diagnosticPage.tag(3)
                planPage.tag(4)
                habitPage.tag(5)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar
        }
    }

    // MARK: Chrome

    private var skipBar: some View {
        HStack {
            Spacer()
            Button("Skip") { onContinue() }
                .font(.bodyM)
                .foregroundStyle(Palette.inkFaint)
                .opacity(page < pageCount - 1 ? 1 : 0)
                .disabled(page == pageCount - 1)
                .accessibilityHidden(page == pageCount - 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .frame(height: 32)
    }

    private var bottomBar: some View {
        VStack(spacing: 20) {
            HStack(spacing: 7) {
                ForEach(0..<pageCount, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Palette.terracotta : Palette.hairline)
                        .frame(width: i == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: page)
            .accessibilityHidden(true)

            PrimaryButton(
                title: page == pageCount - 1 ? "Start my plan" : "Continue",
                icon: page == pageCount - 1 ? "arrow.right" : nil
            ) {
                if page < pageCount - 1 {
                    withAnimation(.easeInOut(duration: 0.3)) { page += 1 }
                } else {
                    store.saveLearningProfile(
                        goal: selectedGoal,
                        confidence: confidence,
                        diagnosticCorrect: diagnosticCorrect,
                        diagnosticTotal: DiagnosticQuestion.samples.count
                    )
                    settings.dailyGoal = selectedGoal == .exam ? 8 : 5
                    onContinue()
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    // MARK: Pages

    private var welcomePage: some View {
        OnboardingPage {
            ZStack {
                Circle().fill(Palette.terracottaSoft).frame(width: 152, height: 152)
                Text("π")
                    .font(.system(size: 84, weight: .bold, design: .serif))
                    .foregroundStyle(Palette.terracotta)
            }
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text("Math, made simple.")
                    .font(.displayL).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Algebra to calculus. One small step a day.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var howItWorksPage: some View {
        OnboardingPage {
            VStack(spacing: 10) {
                Text("How Mathio works")
                    .font(.displayM).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("A quieter way to get better at math.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                featureCard("brain.head.profile", "Adaptive practice",
                            "Mathio picks your next lesson from what you've mastered — never busywork.")
                featureCard("lightbulb.max.fill", "Step-by-step solutions",
                            "Miss a question and you'll see exactly how to reach the answer, line by line.")
                featureCard("arrow.triangle.2.circlepath", "Spaced repetition",
                            "Questions return right before you'd forget them, so it actually sticks.")
            }
        }
    }

    private var goalPage: some View {
        OnboardingPage {
            VStack(spacing: 10) {
                Text("What should Mathio help with?")
                    .font(.displayM).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Your answer shapes the first two weeks.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                ForEach(LearningGoal.allCases) { goal in
                    Button { selectedGoal = goal } label: {
                        goalOption(goal)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var diagnosticPage: some View {
        OnboardingPage {
            VStack(spacing: 10) {
                Text("Quick level check")
                    .font(.displayM).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Five tiny questions. No pressure — this just tunes your first plan.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 14) {
                ForEach(Array(DiagnosticQuestion.samples.enumerated()), id: \.offset) { index, item in
                    diagnosticCard(item, index: index)
                }
            }

            VStack(spacing: 12) {
                Text("How confident do you feel right now?")
                    .font(.titleM)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    ForEach(1...5, id: \.self) { value in
                        Button { confidence = value } label: {
                            Text("\(value)")
                                .font(.titleM)
                                .foregroundStyle(confidence == value ? Palette.heroInk : Palette.ink)
                                .frame(width: 42, height: 42)
                                .background(confidence == value ? Palette.terracotta : Palette.surfaceMuted)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("1 = lost, 5 = ready for a challenge")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
            .padding(.top, 4)
        }
    }

    private var planPage: some View {
        OnboardingPage {
            ZStack {
                Circle().fill(Palette.calculus.opacity(0.14)).frame(width: 152, height: 152)
                Image(systemName: selectedGoal.icon)
                    .font(.system(size: 58, weight: .semibold))
                    .foregroundStyle(Palette.calculus)
            }
            .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("Your first plan is ready")
                    .font(.displayL).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text(profilePreviewLine)
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                miniStat("target", selectedGoal.title)
                miniStat("chart.line.uptrend.xyaxis", DiagnosticQuestion.level(for: diagnosticCorrect,
                                                                               total: DiagnosticQuestion.samples.count,
                                                                               confidence: confidence).title)
                miniStat("calendar.badge.clock", "A 14-day starter path will appear on Home")
            }

            firstWeekPreview
        }
    }

    private var habitPage: some View {
        OnboardingPage {
            ZStack {
                Circle().fill(Palette.amberSoft).frame(width: 152, height: 152)
                Image(systemName: "flame.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Palette.terracotta)
            }
            .accessibilityHidden(true)

            VStack(spacing: 14) {
                Text("Build the habit")
                    .font(.displayL).foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)
                Text("Two minutes a day is enough. Mathio holds your streak and picks up exactly where you left off.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                miniStat("flame.fill", "Daily streaks, with freezes for the days you miss")
                miniStat("target", "A daily goal small enough to actually hit")
                miniStat("chart.bar.xaxis", "Progress tracked across every topic")
            }
        }
    }

    // MARK: Page pieces

    private func featureCard(_ icon: String,
                             _ title: LocalizedStringResource,
                             _ body: LocalizedStringResource) -> some View {
        Card(padding: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(Palette.terracotta)
                    .frame(width: 40, height: 40)
                    .background(Palette.terracottaSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.titleM).foregroundStyle(Palette.ink)
                    Text(body).font(.bodyM).foregroundStyle(Palette.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func goalOption(_ goal: LearningGoal) -> some View {
        let active = selectedGoal == goal
        return Card(padding: 14, background: active ? Palette.terracottaSoft : Palette.surface) {
            HStack(spacing: 12) {
                Image(systemName: goal.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Palette.terracotta)
                    .frame(width: 38, height: 38)
                    .background(Palette.surfaceMuted)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(goal.title).font(.titleM).foregroundStyle(Palette.ink)
                    Text(goal.subtitle).font(.bodyM).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Palette.success : Palette.inkFaint)
            }
        }
    }

    private func diagnosticCard(_ item: DiagnosticQuestion, index: Int) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.prompt)
                    .font(.titleM)
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    ForEach(Array(item.options.enumerated()), id: \.offset) { optionIndex, option in
                        Button { diagnosticAnswers[index] = optionIndex } label: {
                            Text(option)
                                .font(.bodyM)
                                .foregroundStyle(diagnosticAnswers[index] == optionIndex ? Palette.heroInk : Palette.ink)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(diagnosticAnswers[index] == optionIndex ? Palette.terracotta : Palette.surfaceMuted)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var profilePreviewLine: LocalizedStringResource {
        let correct = diagnosticCorrect
        let total = DiagnosticQuestion.samples.count
        return "Based on \(correct) of \(total) and your goal, Mathio will start small and adapt each day."
    }

    private func miniStat(_ icon: String, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(Palette.terracotta)
                .frame(width: 26)
                .accessibilityHidden(true)
            Text(text).font(.bodyM).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var firstWeekPreview: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.clock")
                        .foregroundStyle(Palette.terracotta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("7-day focus")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("Seven small sessions from your recommended path.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 8) {
                    starterPlanRow(index: 1, icon: "target", title: "Daily goal",
                                   detail: "A daily goal small enough to actually hit")
                    starterPlanRow(index: 2, icon: "map.fill", title: "Guided paths",
                                   detail: "Mathio picks your next lesson from what you've mastered — never busywork.")
                    starterPlanRow(index: 3, icon: "lightbulb.max.fill", title: "Step-by-step solutions",
                                   detail: "Miss a question and you'll see exactly how to reach the answer, line by line.")
                    starterPlanRow(index: 4, icon: "arrow.triangle.2.circlepath", title: "Spaced repetition",
                                   detail: "Questions return right before you'd forget them, so it actually sticks.")
                }
            }
        }
    }

    private func starterPlanRow(index: Int,
                                icon: String,
                                title: LocalizedStringResource,
                                detail: LocalizedStringResource) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Palette.heroInk)
                .frame(width: 24, height: 24)
                .background(Palette.terracotta, in: Circle())
                .accessibilityHidden(true)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.terracotta)
                .frame(width: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyM)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct DiagnosticQuestion {
    let prompt: LocalizedStringResource
    let options: [LocalizedStringResource]
    let correctIndex: Int

    static let samples: [DiagnosticQuestion] = [
        DiagnosticQuestion(prompt: "1/2 + 1/4 = ?", options: ["3/4", "2/6", "1/8"], correctIndex: 0),
        DiagnosticQuestion(prompt: "Solve: 2x + 3 = 11", options: ["x = 4", "x = 7", "x = 8"], correctIndex: 0),
        DiagnosticQuestion(prompt: "25% of 80 = ?", options: ["20", "25", "40"], correctIndex: 0),
        DiagnosticQuestion(prompt: "A right triangle uses which idea?", options: ["Pythagoras", "Mean", "Interest"], correctIndex: 0),
        DiagnosticQuestion(prompt: "Derivative of x²?", options: ["2x", "x", "x²"], correctIndex: 0)
    ]

    static func level(for correct: Int, total: Int, confidence: Int) -> DiagnosticLevel {
        LearningProfile(
            goal: .exam,
            confidence: confidence,
            diagnosticCorrect: correct,
            diagnosticTotal: total,
            createdAt: .now
        ).level
    }
}

/// A single onboarding page: content is vertically centered when it fits and
/// scrolls when it doesn't, so the layout holds from iPhone SE to Pro Max.
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 28) { content() }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .frame(minHeight: geo.size.height, alignment: .center)
            }
        }
    }
}

// MARK: - Home

private struct WeeklyActivityDay: Identifiable {
    let date: Date
    let correct: Int
    let isToday: Bool

    var id: Date { date }
}

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
    @State private var showDailyChallenge = false
    @State private var showWeakSpotDrill = false
    @State private var showExamSprint = false
    @State private var showMistakeDrill = false

    private var topics: [Topic] { Curriculum.topics }
    private var learningPaths: [LearningPath] { LearningPath.defaultPaths }
    private var recommendedPath: LearningPath { LearningPath.recommended(for: store.learningProfile) }
    private var nextUp: (Topic, Lesson)? { store.nextLesson(in: topics, premium: premiumStore.isPremium) }
    private var weakSpot: (Topic, Lesson)? {
        let candidates: [(Topic, Lesson, Double)] = topics.flatMap { topic in
            topic.lessons.map { lesson in
                (topic, lesson, store.mastery(for: lesson))
            }
        }
        .filter { $0.2 < 1.0 }

        guard !candidates.isEmpty else { return nil }
        let accessible = candidates.filter { topic, lesson, _ in
            premiumStore.isPremium || lesson.isFree(in: topic)
        }
        let pool = accessible.isEmpty ? candidates : accessible
        let best = pool.min { lhs, rhs in
            if lhs.2 == rhs.2 { return lhs.1.questions.count > rhs.1.questions.count }
            return lhs.2 < rhs.2
        }!
        return (best.0, best.1)
    }
    private var mistakeFocus: [MistakeFocus] {
        topics.flatMap { topic in
            topic.lessons.flatMap { lesson in
                lesson.questions.compactMap { question -> MistakeFocus? in
                    guard let entry = store.answered[question.id],
                          entry.attempts > 0,
                          entry.attempts - entry.correct > 0 || !entry.isMastered else { return nil }
                    return MistakeFocus(topic: topic, lesson: lesson, question: question, entry: entry)
                }
            }
        }
        .sorted { lhs, rhs in
            if lhs.misses != rhs.misses { return lhs.misses > rhs.misses }
            if lhs.entry.attempts != rhs.entry.attempts { return lhs.entry.attempts > rhs.entry.attempts }
            return lhs.entry.lastAt > rhs.entry.lastAt
        }
        .prefix(5)
        .map { $0 }
    }
    private var mistakeDrillLesson: Lesson {
        Lesson(
            id: "__home_mistake_drill__",
            title: "Mistake drill",
            intro: "A focused set built from questions you have missed before.",
            formulas: [],
            questions: mistakeFocus.map(\.question)
        )
    }
    private var reviewCount: Int { store.reviewQueue(in: topics).count }
    private var lessonCount: Int { topics.reduce(0) { $0 + $1.lessons.count } }
    private var questionCount: Int { topics.reduce(0) { $0 + $1.questionCount } }
    private var monthsOfPractice: Int {
        max(1, Int(ceil(Double(questionCount) / Double(max(settings.dailyGoal, 1)) / 30.0)))
    }
    private var totalCorrect: Int { store.answered.values.reduce(0) { $0 + $1.correct } }
    private var nextCorrectMilestone: Int {
        [25, 50, 100, 250, 500, 1_000].first { $0 > totalCorrect }
            ?? ((totalCorrect / 500) + 1) * 500
    }
    private var milestoneProgress: Double {
        min(1, Double(totalCorrect) / Double(max(nextCorrectMilestone, 1)))
    }
    private var weeklyActivity: [WeeklyActivityDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let activity = store.dailyActivity()
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return WeeklyActivityDay(date: date, correct: activity[date, default: 0], isToday: offset == 0)
        }
    }
    private var activeDaysThisWeek: Int { weeklyActivity.filter { $0.correct > 0 }.count }
    private var weeklyCorrect: Int { weeklyActivity.reduce(0) { $0 + $1.correct } }
    private var weeklyTarget: Int { max(settings.dailyGoal * 7, 1) }
    private var weeklyProgress: Double { min(1, Double(weeklyCorrect) / Double(weeklyTarget)) }
    private var hasReviewHistory: Bool {
        store.answered.values.contains { $0.attempts > 0 }
    }
    private var reviewsDueTomorrow: Int {
        reviewDueCount(daysAhead: 1)
    }
    private var reviewsDueThisWeek: Int {
        reviewDueCount(daysAhead: 7)
    }
    private var sevenDayFocusLessons: [Lesson] {
        let unfinished = recommendedPath.lessons.filter { store.mastery(for: $0) < 1.0 }
        let pool = unfinished.isEmpty ? recommendedPath.lessons : unfinished
        return Array(pool.prefix(7))
    }
    private var sevenDayFocusProgress: Double {
        min(1, Double(activeDaysThisWeek) / 7.0)
    }
    private var nextFocusLesson: Lesson? {
        sevenDayFocusLessons.first { store.mastery(for: $0) < 1.0 } ?? sevenDayFocusLessons.first
    }
    private var nextFocusDay: Int {
        min(max(activeDaysThisWeek + 1, 1), 7)
    }
    private var examReadinessProgress: Double {
        let mastery = topics.isEmpty ? 0 : topics.reduce(0.0) { $0 + store.mastery(for: $1) } / Double(topics.count)
        let review = reviewCount == 0 ? 1.0 : max(0.15, 1.0 - Double(min(reviewCount, 10)) / 12.0)
        let daily = min(1.0, Double(store.correctToday()) / Double(max(settings.dailyGoal, 1)))
        return min(1.0, mastery * 0.55 + review * 0.25 + daily * 0.20)
    }
    private var examReadinessPercent: Int {
        Int((examReadinessProgress * 100).rounded())
    }
    private var daysSinceLastPractice: Int? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let pastPracticeDays = store.dailyActivity().keys
            .map { calendar.startOfDay(for: $0) }
            .filter { $0 < today }
        guard let last = pastPracticeDays.max(),
              let days = calendar.dateComponents([.day], from: last, to: today).day,
              days > 0 else { return nil }
        return days
    }
    private var shouldShowComebackCard: Bool {
        store.correctToday() == 0 && daysSinceLastPractice != nil && totalCorrect > 0
    }

    /// Set by `PracticeMathIntent` (Siri / Spotlight). Honored once on appear.
    private static let pendingPracticeKey = "mathio.intent.pendingPractice"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    DailyGoalView(progress: store.correctToday(), goal: settings.dailyGoal)
                    if shouldShowComebackCard { comebackCard }
                    dailyChallengeCard
                    if weakSpot != nil { weakSpotCard }
                    if !mistakeFocus.isEmpty { mistakeNotebookCard }
                    examSprintCard
                    todayPlanCard
                    momentumCard
                    weeklyRhythmCard
                    reviewForecastCard
                    sevenDayFocusCard
                    nextUpCard
                    personalPlanCard
                    learningPathsSection
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
                LessonView(lesson: lesson, store: store) {
                    guard let (_, next) = store.nextLesson(in: topics, premium: premiumStore.isPremium),
                          next.id != lesson.id else { return nil }
                    return next
                }
            }
            .navigationDestination(isPresented: $showReview) {
                PracticeView(lesson: reviewLesson(), store: store, isReview: true)
            }
            .navigationDestination(isPresented: $showDailyChallenge) {
                PracticeView(lesson: dailyChallengeLesson(), store: store, isReview: reviewCount > 0)
            }
            .navigationDestination(isPresented: $showWeakSpotDrill) {
                PracticeView(lesson: weakSpotDrillLesson(), store: store, isReview: false)
            }
            .navigationDestination(isPresented: $showMistakeDrill) {
                PracticeView(lesson: mistakeDrillLesson, store: store, isReview: false)
            }
            .navigationDestination(isPresented: $showExamSprint) {
                PracticeView(lesson: examSprintLesson(), store: store, isReview: true)
            }
            .sheet(isPresented: $showStats)    { StatsView(store: store, settings: settings, topics: topics) }
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

    private var todayPlanCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Your start plan", systemImage: "checklist")
                        .font(.titleM)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(store.correctToday())/\(settings.dailyGoal)")
                        .font(.label)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.surface, in: Capsule())
                }

                if reviewCount > 0 {
                    Button { showReview = true } label: {
                        planRow(
                            title: "Review due",
                            subtitle: "\(reviewCount) questions to refresh",
                            icon: "arrow.triangle.2.circlepath",
                            tint: Palette.terracotta
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    planRow(
                        title: "Review",
                        subtitle: "Refresh what you've learned.",
                        icon: "checkmark.circle.fill",
                        tint: Palette.success
                    )
                }

                if let (topic, lesson) = nextUp {
                    Button {
                        if !premiumStore.isPremium && !lesson.isFree(in: topic) {
                            showPaywall = true
                        } else {
                            presented = lesson
                        }
                    } label: {
                        planRow(
                            title: "Continue",
                            subtitle: lesson.title,
                            icon: topic.icon,
                            tint: topic.color,
                            trailing: !premiumStore.isPremium && !lesson.isFree(in: topic) ? "lock.fill" : "arrow.right"
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    planRow(
                        title: "All mastered",
                        subtitle: "Pick any topic to keep practicing.",
                        icon: "checkmark.seal.fill",
                        tint: Palette.success
                    )
                }

                planRow(
                    title: "Daily goal",
                    subtitle: dailyGoalSubtitle,
                    icon: store.correctToday() >= settings.dailyGoal ? "checkmark.circle.fill" : "target",
                    tint: store.correctToday() >= settings.dailyGoal ? Palette.success : Palette.calculus
                )
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var comebackCard: some View {
        Button {
            if dailyChallengeRequiresPremium {
                showPaywall = true
            } else {
                showDailyChallenge = true
            }
        } label: {
            Card(padding: 18, background: Palette.surface) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.uturn.left.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.success)
                            .frame(width: 44, height: 44)
                            .background(Palette.success.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Welcome back")
                                .font(.label)
                                .foregroundStyle(Palette.inkFaint)
                                .textCase(.uppercase)
                                .tracking(1.2)
                            Text("Restart gently")
                                .font(.titleL)
                                .foregroundStyle(Palette.ink)
                            Text(comebackSubtitle)
                                .font(.bodyM)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    HStack(spacing: 10) {
                        Label("5 questions", systemImage: "timer")
                        Label("No pressure", systemImage: "leaf")
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)

                    HStack {
                        Text("Restart with 5 questions")
                            .font(.bodyM.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Image(systemName: dailyChallengeRequiresPremium ? "lock.fill" : "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .frame(width: 38, height: 38)
                            .background(Palette.success.opacity(0.2), in: Circle())
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var comebackSubtitle: LocalizedStringResource {
        guard let days = daysSinceLastPractice else {
            return "A short session is enough to rebuild the rhythm."
        }
        return "\(days) days away. Start with a small set and keep the streak realistic."
    }

    private var dailyChallengeCard: some View {
        Button {
            if dailyChallengeRequiresPremium {
                showPaywall = true
            } else {
                showDailyChallenge = true
            }
        } label: {
            Card(padding: 18, background: Palette.heroSurface) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle().fill(Palette.amber.opacity(0.18)).frame(width: 54, height: 54)
                        Image(systemName: dailyChallengeIcon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.amber)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Daily challenge")
                            .font(.label)
                            .foregroundStyle(Palette.heroInkSoft)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        Text(dailyChallengeTitle)
                            .font(.titleL)
                            .foregroundStyle(Palette.heroInk)
                        Text(dailyChallengeSubtitle)
                            .font(.bodyM)
                            .foregroundStyle(Palette.heroInkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: dailyChallengeRequiresPremium ? "lock.fill" : "arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .frame(width: 42, height: 42)
                        .background(Palette.amber, in: Circle())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var dailyChallengeIcon: String {
        if reviewCount > 0 { return "arrow.triangle.2.circlepath" }
        if store.correctToday() >= settings.dailyGoal { return "sparkles" }
        return "target"
    }

    private var dailyChallengeTitle: LocalizedStringResource {
        if reviewCount > 0 { return "Refresh before you forget" }
        if store.correctToday() >= settings.dailyGoal { return "Bonus round" }
        return "Finish today's goal"
    }

    private var dailyChallengeSubtitle: LocalizedStringResource {
        if reviewCount > 0 {
            return "\(min(reviewCount, 5)) quick review questions waiting."
        }
        let remaining = max(settings.dailyGoal - store.correctToday(), 1)
        if store.correctToday() >= settings.dailyGoal {
            return "You hit your goal. Keep the session warm with 5 more questions."
        }
        return "\(remaining) correct answers left. Start with a short, focused set."
    }

    private var dailyChallengeRequiresPremium: Bool {
        guard reviewCount == 0,
              let (topic, lesson) = nextUp else { return false }
        return !premiumStore.isPremium && !lesson.isFree(in: topic)
    }

    private var weakSpotCard: some View {
        guard let (topic, lesson) = weakSpot else {
            return AnyView(EmptyView())
        }
        return AnyView(
            Button {
                if !premiumStore.isPremium && !lesson.isFree(in: topic) {
                    showPaywall = true
                } else {
                    showWeakSpotDrill = true
                }
            } label: {
                Card(padding: 16, background: Palette.surfaceMuted) {
                    HStack(spacing: 12) {
                        Image(systemName: "scope")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(topic.color)
                            .frame(width: 42, height: 42)
                            .background(topic.color.opacity(0.14), in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Weak spot drill")
                                .font(.titleM)
                                .foregroundStyle(Palette.ink)
                            Text("\(lesson.title) · \(Int(store.mastery(for: lesson) * 100))% mastery")
                                .font(.bodyM)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: (!premiumStore.isPremium && !lesson.isFree(in: topic)) ? "lock.fill" : "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        )
    }

    private var mistakeNotebookCard: some View {
        Card(padding: 16, background: Palette.terracottaSoft.opacity(0.5)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Mistake notebook", systemImage: "exclamationmark.circle.fill")
                        .font(.titleM)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(mistakeFocus.count) to revisit")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }

                Text("Mathio turns missed answers into a focused drill, so weak spots do not disappear into the history.")
                    .font(.bodyM)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(mistakeFocus.prefix(2)) { item in
                    mistakeRow(item)
                }

                PrimaryButton(title: "Practice missed questions", icon: "scope") {
                    showMistakeDrill = true
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func mistakeRow(_ item: MistakeFocus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.terracotta)
                .frame(width: 36, height: 36)
                .background(Palette.surface, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.lesson.title)
                    .font(.bodyM.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(item.question.prompt)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                Text("\(item.misses) misses · \(item.entry.correct) correct")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var examSprintCard: some View {
        Button {
            if premiumStore.isPremium {
                showExamSprint = true
            } else {
                showPaywall = true
            }
        } label: {
            Card(padding: 16, background: Palette.surface) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "stopwatch.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Palette.terracotta)
                            .frame(width: 42, height: 42)
                            .background(Palette.terracottaSoft, in: Circle())
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Exam sprint")
                                .font(.titleM)
                                .foregroundStyle(Palette.ink)
                            Text("10 mixed questions from reviews, weak spots, and your next lesson.")
                                .font(.bodyM)
                                .foregroundStyle(Palette.inkSoft)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: premiumStore.isPremium ? "arrow.right" : "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.inkFaint)
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("Readiness")
                                .font(.caption)
                                .foregroundStyle(Palette.inkFaint)
                            Spacer()
                            Text("\(examReadinessPercent)%")
                                .font(.label)
                                .foregroundStyle(Palette.ink)
                        }
                        ProgressBar(progress: examReadinessProgress, color: Palette.terracotta, height: 6)
                        Text(examReadinessSubtitle)
                            .font(.caption)
                            .foregroundStyle(Palette.inkFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 8) {
                        sprintChip("Review", value: "\(min(reviewCount, 4))")
                        sprintChip("Weak", value: weakSpot == nil ? "0" : "3")
                        sprintChip("New", value: nextUp == nil ? "0" : "3")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private var examReadinessSubtitle: LocalizedStringResource {
        if reviewCount > 0 {
            return "\(min(reviewCount, 10)) review questions can lift your readiness."
        }
        if store.correctToday() < settings.dailyGoal {
            return "Finish today's goal to raise your exam rhythm."
        }
        return "Strong rhythm. Use a sprint to keep exam skills sharp."
    }

    private func sprintChip(_ label: LocalizedStringResource, value: String) -> some View {
        HStack(spacing: 5) {
            Text(value)
                .font(.label)
                .foregroundStyle(Palette.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Palette.surfaceMuted, in: Capsule())
    }

    private var dailyGoalSubtitle: LocalizedStringResource {
        if store.correctToday() >= settings.dailyGoal {
            return "Daily goal reached. \(store.correctToday()) correct out of \(settings.dailyGoal)."
        }
        return "A daily goal small enough to actually hit"
    }

    private var momentumCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                        .frame(width: 30, height: 30)
                        .background(Palette.amberSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Next milestone")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("\(nextCorrectMilestone - totalCorrect) correct answers until \(nextCorrectMilestone) total.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                ProgressBar(progress: milestoneProgress, color: Palette.amber, height: 6)
                HStack {
                    Text("\(totalCorrect) correct so far")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                    Spacer()
                    Text("Keep going while the session is warm.")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var weeklyRhythmCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.calculus)
                        .frame(width: 30, height: 30)
                        .background(Palette.calculus.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("This week")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text(weeklyRhythmSubtitle)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text("\(activeDaysThisWeek)/7 days")
                        .font(.label)
                        .foregroundStyle(Palette.inkSoft)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.surface, in: Capsule())
                }

                ProgressBar(progress: weeklyProgress, color: Palette.calculus, height: 6)

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(weeklyActivity) { day in
                        VStack(spacing: 6) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.surface)
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(day.correct > 0 ? Palette.calculus : Palette.hairline)
                                    .frame(height: weeklyDayHeight(for: day.correct))
                            }
                            .frame(height: 42)
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(day.isToday ? Palette.calculus : Palette.hairline, lineWidth: day.isToday ? 1.2 : 0.5)
                            )
                            Text(day.date, format: .dateTime.weekday(.narrow))
                                .font(.caption)
                                .foregroundStyle(day.isToday ? Palette.ink : Palette.inkFaint)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text(weeklyRhythmPrompt)
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Weekly rhythm. \(activeDaysThisWeek) active days, \(weeklyCorrect) correct answers."))
    }

    private var weeklyRhythmSubtitle: LocalizedStringResource {
        if weeklyCorrect == 0 {
            return "Start with one short session today."
        }
        return "\(activeDaysThisWeek) active days, \(weeklyCorrect) correct answers"
    }

    private var weeklyRhythmPrompt: LocalizedStringResource {
        if store.correctToday() >= settings.dailyGoal {
            return "Come back tomorrow to keep the rhythm."
        }
        return "Great rhythm. A short review keeps it alive."
    }

    private func weeklyDayHeight(for correct: Int) -> CGFloat {
        guard correct > 0 else { return 4 }
        let pct = min(1, Double(correct) / Double(max(settings.dailyGoal, 1)))
        return 10 + CGFloat(pct) * 32
    }

    private var reviewForecastCard: some View {
        Card(padding: 16, background: Palette.surface) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.terracotta)
                        .frame(width: 34, height: 34)
                        .background(Palette.terracottaSoft, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Review forecast")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text(reviewForecastSubtitle)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    forecastPill(value: "\(reviewCount)", label: "Today", active: reviewCount > 0)
                    forecastPill(value: "\(reviewsDueTomorrow)", label: "Tomorrow", active: reviewsDueTomorrow > 0)
                    forecastPill(value: "\(reviewsDueThisWeek)", label: "7 days", active: reviewsDueThisWeek > 0)
                }

                if reviewCount > 0 {
                    Button { showReview = true } label: {
                        HStack {
                            Text("Start due review")
                                .font(.bodyM.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(12)
                        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Review forecast. \(reviewCount) due today, \(reviewsDueTomorrow) tomorrow, \(reviewsDueThisWeek) in seven days."))
    }

    private var reviewForecastSubtitle: LocalizedStringResource {
        if reviewCount > 0 {
            return "Clear today's due questions before they fade."
        }
        if reviewsDueTomorrow > 0 {
            return "\(reviewsDueTomorrow) questions are scheduled for tomorrow."
        }
        if reviewsDueThisWeek > 0 {
            return "\(reviewsDueThisWeek) questions are coming back this week."
        }
        if hasReviewHistory {
            return "No reviews are due yet. New lessons will seed the next cycle."
        }
        return "Answer a few questions to start your personal review cycle."
    }

    private func forecastPill(value: String, label: LocalizedStringResource, active: Bool) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.titleM)
                .foregroundStyle(active ? Palette.ink : Palette.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(active ? Palette.amberSoft : Palette.surfaceMuted,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reviewDueCount(daysAhead: Int) -> Int {
        let calendar = Calendar.current
        guard let deadline = calendar.date(byAdding: .day, value: daysAhead, to: .now) else { return 0 }
        return store.reviewDueCount(in: topics, after: .now, through: deadline)
    }

    private var sevenDayFocusCard: some View {
        Card(padding: 16, background: Palette.surface) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.success)
                        .frame(width: 34, height: 34)
                        .background(Palette.success.opacity(0.14), in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("7-day focus")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("Seven small sessions from your recommended path.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: "\(activeDaysThisWeek)/7")
                            .font(.label)
                            .foregroundStyle(Palette.ink)
                        Text("active days")
                            .font(.caption)
                            .foregroundStyle(Palette.inkFaint)
                    }
                }

                ProgressBar(progress: sevenDayFocusProgress, color: Palette.success, height: 6)

                HStack(spacing: 7) {
                    ForEach(0..<7, id: \.self) { index in
                        Circle()
                            .fill(index < activeDaysThisWeek ? Palette.success : Palette.hairline)
                            .frame(width: 10, height: 10)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }
                }

                if let lesson = nextFocusLesson {
                    Button {
                        if isLocked(lesson) {
                            showPaywall = true
                        } else {
                            presented = lesson
                        }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Next focus")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkFaint)
                                    .textCase(.uppercase)
                                    .tracking(1.0)
                                Text(lesson.title)
                                    .font(.bodyM.weight(.semibold))
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                Text("Day \(nextFocusDay) of 7")
                                    .font(.caption)
                                    .foregroundStyle(Palette.inkSoft)
                            }
                            Spacer(minLength: 0)
                            Text(isLocked(lesson) ? "Premium session" : "Start next session")
                                .font(.label)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.76)
                            Image(systemName: isLocked(lesson) ? "lock.fill" : "arrow.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.inkFaint)
                        }
                        .padding(12)
                        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Text("Keep the chain warm: one short session is enough.")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func planRow(
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        icon: String,
        tint: Color,
        trailing: String? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.bodyM.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
            }
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                Card(padding: 24, background: Palette.heroSurface) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Continue").textCase(.uppercase).tracking(1.4)
                                .font(.label).foregroundStyle(Palette.amber)
                            Spacer()
                            if !premiumStore.isPremium && !lesson.isFree(in: topic) {
                                Image(systemName: "lock.fill").foregroundStyle(Palette.amber)
                            }
                        }
                        Text(lesson.title).font(.displayM).foregroundStyle(Palette.heroInk)
                        HStack(spacing: 6) {
                            Image(systemName: topic.icon).font(.system(size: 13))
                            Text(topic.title).font(.label)
                        }
                        .foregroundStyle(Palette.heroInkSoft)
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

    private var learningPathsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Guided paths").padding(.leading, 4)
            ForEach(learningPaths) { path in
                Button { open(path) } label: {
                    LearningPathRow(
                        path: path,
                        progress: progress(for: path),
                        locked: firstLesson(in: path).map(isLocked(_:)) ?? false,
                        nextLessonTitle: firstLesson(in: path)?.title ?? path.title
                    )
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var personalPlanCard: some View {
        Card(padding: 18, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: store.learningProfile?.goal.icon ?? "calendar.badge.clock")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.calculus)
                        .frame(width: 42, height: 42)
                        .background(Palette.calculus.opacity(0.14))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your start plan")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text(planSummary)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button { open(recommendedPath) } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(recommendedPath.color.opacity(0.15)).frame(width: 42, height: 42)
                            Image(systemName: recommendedPath.icon)
                                .foregroundStyle(recommendedPath.color)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(recommendedPath.title).font(.titleM).foregroundStyle(Palette.ink)
                            Text(recommendedPath.subtitle).font(.bodyM).foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        Text("\(recommendedPath.durationDays)d")
                            .font(.label)
                            .foregroundStyle(Palette.inkFaint)
                        Image(systemName: isLocked(firstLesson(in: recommendedPath) ?? recommendedPath.lessons[0]) ? "lock.fill" : "arrow.right")
                            .foregroundStyle(Palette.inkFaint)
                    }
                    .padding(12)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    planPill(store.learningProfile?.level.title ?? "Foundation", icon: "1.circle.fill")
                    planPill("Daily goal", icon: "target")
                    planPill("Review loop", icon: "arrow.triangle.2.circlepath")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Next 3 sessions")
                        .font(.label)
                        .foregroundStyle(Palette.inkFaint)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    ForEach(Array(nextPlanLessons.enumerated()), id: \.element.id) { index, lesson in
                        Button {
                            if isLocked(lesson) {
                                showPaywall = true
                            } else {
                                presented = lesson
                            }
                        } label: {
                            sessionStep(index: index + 1, lesson: lesson)
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Roadmap preview")
                        .font(.label)
                        .foregroundStyle(Palette.inkFaint)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    roadmapStep(
                        icon: "1.circle.fill",
                        title: "Week 1",
                        subtitle: roadmapFirstStep,
                        tint: Palette.terracotta
                    )
                    roadmapStep(
                        icon: "2.circle.fill",
                        title: "Weeks 2-4",
                        subtitle: "Build momentum through your guided path.",
                        tint: recommendedPath.color
                    )
                    roadmapStep(
                        icon: "3.circle.fill",
                        title: "Month 2+",
                        subtitle: "Use spaced repetition and advanced topics to make it stick.",
                        tint: Palette.calculus
                    )
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var planSummary: LocalizedStringResource {
        if let profile = store.learningProfile {
            return "\(profile.goal.title) · \(profile.level.title) · \(recommendedPath.durationDays)-day first track"
        }
        return "\(lessonCount) lessons · \(questionCount) questions · about \(monthsOfPractice) months at your current goal"
    }

    private var nextPlanLessons: [Lesson] {
        let unfinished = recommendedPath.lessons.filter { store.mastery(for: $0) < 1.0 }
        let pool = unfinished.isEmpty ? recommendedPath.lessons : unfinished
        return Array(pool.prefix(3))
    }

    private var roadmapFirstStep: LocalizedStringResource {
        if let lesson = firstLesson(in: recommendedPath) {
            return "Start with \(lesson.title)."
        }
        return "Start with a short diagnostic-friendly lesson."
    }

    private func planPill(_ title: LocalizedStringResource, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(Palette.surface, in: Capsule())
    }

    private func roadmapStep(
        icon: String,
        title: LocalizedStringResource,
        subtitle: LocalizedStringResource,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.bodyM.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sessionStep(index: Int, lesson: Lesson) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(index)")
                .font(.label)
                .foregroundStyle(Palette.ink)
                .frame(width: 30, height: 30)
                .background(Palette.amberSoft, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(lesson.title)
                    .font(.bodyM.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ProgressBar(progress: store.mastery(for: lesson),
                                color: topic(containing: lesson)?.color ?? Palette.amber,
                                height: 5)
                        .frame(maxWidth: 86)
                    Text(verbatim: "\(Int(store.mastery(for: lesson) * 100))%")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: isLocked(lesson) ? "lock.fill" : "arrow.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.inkFaint)
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func progress(for path: LearningPath) -> Double {
        guard !path.lessons.isEmpty else { return 0 }
        return path.lessons.reduce(0.0) { $0 + store.mastery(for: $1) } / Double(path.lessons.count)
    }

    private func topic(containing lesson: Lesson) -> Topic? {
        topics.first { $0.lessons.contains(lesson) }
    }

    private func firstLesson(in path: LearningPath) -> Lesson? {
        path.lessons.first { store.mastery(for: $0) < 1.0 } ?? path.lessons.first
    }

    private func isLocked(_ lesson: Lesson) -> Bool {
        guard let topic = topic(containing: lesson) else { return false }
        return !premiumStore.isPremium && !lesson.isFree(in: topic)
    }

    private func open(_ path: LearningPath) {
        guard let lesson = firstLesson(in: path) else { return }
        if isLocked(lesson) {
            showPaywall = true
        } else {
            presented = lesson
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

    /// A short daily entry point: review comes first; otherwise use the next
    /// adaptive lesson and cap the set so starting never feels heavy.
    private func dailyChallengeLesson() -> Lesson {
        if reviewCount > 0 {
            return Lesson(
                id: "__daily_review__",
                title: "Daily challenge",
                intro: "Refresh what is about to fade.",
                formulas: [],
                questions: store.reviewQueue(in: topics, limit: 5)
            )
        }
        guard let (_, lesson) = nextUp else {
            return Lesson(
                id: "__daily_mastered__",
                title: "Daily challenge",
                intro: "Keep your math rhythm alive.",
                formulas: [],
                questions: Array(topics.flatMap { $0.lessons.flatMap(\.questions) }.prefix(5))
            )
        }
        return Lesson(
            id: "__daily_\(lesson.id)__",
            title: "Daily challenge",
            intro: "A short focused set from your next lesson.",
            visual: lesson.visual,
            formulas: lesson.formulas,
            questions: Array(lesson.questions.prefix(5))
        )
    }

    private func weakSpotDrillLesson() -> Lesson {
        guard let (topic, lesson) = weakSpot else {
            return dailyChallengeLesson()
        }
        return Lesson(
            id: "__weak_\(lesson.id)__",
            title: "Weak spot drill",
            intro: "A quick set from \(topic.title), focused where practice pays off fastest.",
            visual: lesson.visual,
            formulas: lesson.formulas,
            questions: Array(lesson.questions.prefix(5))
        )
    }

    private func examSprintLesson() -> Lesson {
        var questions: [Question] = []
        var seen: Set<String> = []

        func append(_ candidates: [Question], limit: Int) {
            for question in candidates where questions.count < 10 {
                guard !seen.contains(question.id) else { continue }
                questions.append(question)
                seen.insert(question.id)
                if questions.count >= limit { break }
            }
        }

        append(store.reviewQueue(in: topics, limit: 4), limit: 4)
        if let (_, lesson) = weakSpot {
            append(Array(lesson.questions.prefix(3)), limit: 7)
        }
        if let (_, lesson) = nextUp {
            append(Array(lesson.questions.prefix(3)), limit: 10)
        }

        let lowestMasteryQuestions = topics
            .flatMap { $0.lessons }
            .flatMap { lesson in lesson.questions.map { (lesson, $0) } }
            .sorted { lhs, rhs in
                let leftMastery = store.answered[lhs.1.id]?.isMastered == true ? 1 : 0
                let rightMastery = store.answered[rhs.1.id]?.isMastered == true ? 1 : 0
                if leftMastery == rightMastery { return lhs.0.id < rhs.0.id }
                return leftMastery < rightMastery
            }
            .map(\.1)
        append(lowestMasteryQuestions, limit: 10)

        return Lesson(
            id: "__exam_sprint__",
            title: "Exam sprint",
            intro: "A mixed mini-test built from review, weak spots, and the next useful lesson.",
            visual: .barChart,
            formulas: [],
            questions: Array(questions.prefix(10))
        )
    }
}

struct LearningPath: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let icon: String
    let color: Color
    let lessons: [Lesson]
    let durationDays: Int

    static let defaultPaths: [LearningPath] = [
        LearningPath(
            id: "foundation-reset",
            title: "30-Day Foundation Reset",
            subtitle: "Fractions, percents, ratios, roots",
            icon: "number",
            color: Palette.terracotta,
            lessons: [Curriculum.preAlgFractions, Curriculum.preAlgDecimals, Curriculum.preAlgPercents,
                      Curriculum.percentChange, Curriculum.preAlgRatios, Curriculum.preAlgRoots,
                      Curriculum.scientificNotation],
            durationDays: 30
        ),
        LearningPath(
            id: "algebra-foundation",
            title: "Algebra Foundation",
            subtitle: "Equations, lines, factoring",
            icon: "function",
            color: Palette.algebra,
            lessons: [Curriculum.linearEquations, Curriculum.linesAndSlope, Curriculum.factoring,
                      Curriculum.inequalities, Curriculum.systems, Curriculum.absoluteValueEquations,
                      Curriculum.wordProblems, Curriculum.rationalExpressions],
            durationDays: 21
        ),
        LearningPath(
            id: "functions-bootcamp",
            title: "21-Day Functions Bootcamp",
            subtitle: "Lines, functions, exponents, logs",
            icon: "point.topleft.down.curvedto.point.bottomright.up",
            color: Palette.algebra,
            lessons: [Curriculum.linesAndSlope, Curriculum.algFunctions, Curriculum.exponents,
                      Curriculum.logarithms, Curriculum.quadratics, Curriculum.polynomials,
                      Curriculum.rationalExpressions],
            durationDays: 21
        ),
        LearningPath(
            id: "calculus-starter",
            title: "Calculus Starter",
            subtitle: "Limits, derivatives, integrals",
            icon: "chart.xyaxis.line",
            color: Palette.calculus,
            lessons: [Curriculum.limits, Curriculum.derivatives, Curriculum.chainRule,
                      Curriculum.integrals, Curriculum.definiteIntegrals, Curriculum.optimizationBasics,
                      Curriculum.relatedRates],
            durationDays: 30
        ),
        LearningPath(
            id: "exam-essentials",
            title: "Exam Essentials",
            subtitle: "Mixed practice across core topics",
            icon: "checklist",
            color: Palette.terracotta,
            lessons: [Curriculum.preAlgFractions, Curriculum.linearEquations, Curriculum.pythagoras,
                      Curriculum.wordProblems, Curriculum.trigBasics, Curriculum.descriptiveStats,
                      Curriculum.standardDeviation, Curriculum.correlationRegression],
            durationDays: 14
        ),
        LearningPath(
            id: "stats-starter",
            title: "Statistics Starter",
            subtitle: "Data, probability, regression",
            icon: "chart.bar.xaxis",
            color: Palette.calculus,
            lessons: [Curriculum.descriptiveStats, Curriculum.probabilityBasics, Curriculum.dataDisplays,
                      Curriculum.sampling, Curriculum.distributions, Curriculum.standardDeviation,
                      Curriculum.correlationRegression,
                      Curriculum.normalDistribution, Curriculum.confidenceIntervals],
            durationDays: 21
        ),
        LearningPath(
            id: "geometry-trig-lab",
            title: "Geometry & Trig Lab",
            subtitle: "Shapes, angles, unit circle",
            icon: "angle",
            color: Palette.geometry,
            lessons: [Curriculum.pythagoras, Curriculum.trianglesArea, Curriculum.angles,
                      Curriculum.circles, Curriculum.trigBasics, Curriculum.unitCircle,
                      Curriculum.coordinateGeometry, Curriculum.radians, Curriculum.lawOfSinesCosines],
            durationDays: 28
        ),
        LearningPath(
            id: "linear-algebra-starter",
            title: "Linear Algebra Starter",
            subtitle: "Vectors, matrices, transformations",
            icon: "square.grid.3x3",
            color: Palette.algebra,
            lessons: [Curriculum.vectors, Curriculum.matrices, Curriculum.dotProducts,
                      Curriculum.transformations, Curriculum.systemsMatrices],
            durationDays: 21
        ),
        LearningPath(
            id: "discrete-thinking",
            title: "Discrete Thinking",
            subtitle: "Logic, sets, counting, graphs",
            icon: "switch.2",
            color: Palette.precalc,
            lessons: [Curriculum.logic, Curriculum.sets, Curriculum.counting,
                      Curriculum.truthTables, Curriculum.modularArithmetic, Curriculum.graphs,
                      Curriculum.sequencesDiscrete],
            durationDays: 28
        ),
        LearningPath(
            id: "money-math",
            title: "Money Math",
            subtitle: "Interest, loans, inflation",
            icon: "banknote",
            color: Palette.trig,
            lessons: [Curriculum.simpleInterest, Curriculum.compoundInterest, Curriculum.budgeting,
                      Curriculum.unitPrices, Curriculum.inflationRealValue, Curriculum.loansPayments,
                      Curriculum.taxesDiscounts],
            durationDays: 14
        )
    ]

    static func recommended(for profile: LearningProfile?) -> LearningPath {
        guard let profile else { return defaultPaths[0] }
        switch profile.goal {
        case .school:
            return profile.level == .starter ? defaultPaths[0] : defaultPaths[1]
        case .exam:
            return defaultPaths.first { $0.id == "exam-essentials" } ?? defaultPaths[0]
        case .selfStudy:
            return profile.level == .advanced
                ? (defaultPaths.first { $0.id == "functions-bootcamp" } ?? defaultPaths[1])
                : defaultPaths[0]
        case .university:
            return profile.level == .advanced
                ? (defaultPaths.first { $0.id == "calculus-starter" } ?? defaultPaths[0])
                : (defaultPaths.first { $0.id == "algebra-foundation" } ?? defaultPaths[0])
        case .money:
            return defaultPaths.first { $0.id == "money-math" } ?? defaultPaths[0]
        }
    }
}

struct LearningPathRow: View {
    let path: LearningPath
    let progress: Double
    let locked: Bool
    let nextLessonTitle: LocalizedStringResource

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(path.color.opacity(0.15)).frame(width: 46, height: 46)
                        Image(systemName: path.icon)
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(path.color)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(path.title)
                                .font(.titleM)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.82)
                            Spacer(minLength: 0)
                            Text("\(path.durationDays)d")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Palette.inkSoft)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Palette.surfaceMuted, in: Capsule())
                        }
                        Text(path.subtitle)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(2)
                        ProgressBar(progress: progress, color: path.color, height: 4)
                    }
                    Image(systemName: locked ? "lock.fill" : "arrow.right")
                        .foregroundStyle(Palette.inkFaint)
                }

                HStack(spacing: 8) {
                    Label("\(path.lessons.count) lessons", systemImage: "books.vertical.fill")
                    Spacer(minLength: 8)
                    Label("Next: \(nextLessonTitle)", systemImage: "arrow.turn.down.right")
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                    .foregroundStyle(Palette.inkFaint)
                    .font(.caption)
            }
        }
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
                    Text("\(topic.lessons.count) lessons · \(topic.questionCount) questions · \(Int(mastery * 100))%")
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

                HStack(spacing: 8) {
                    metricPill(value: "\(topic.lessons.count)", label: "Lessons")
                    metricPill(value: "\(topic.questionCount)", label: "Questions")
                    metricPill(value: "\(Int(store.mastery(for: topic) * 100))%", label: "Mastery")
                }

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

    private func metricPill(value: String, label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.titleM)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(value) \(label)"))
    }
}

extension Topic {
    var questionCount: Int {
        lessons.reduce(0) { $0 + $1.questions.count }
    }
}

extension Lesson {
    /// First lesson of a topic is always free.
    func isFree(in topic: Topic) -> Bool {
        topic.lessons.first?.id == self.id
    }

    var estimatedMinutes: Int {
        max(3, questions.count)
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
                    Text("\(lesson.questions.count) questions · \(lesson.estimatedMinutes) min")
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
    let followUpLesson: () -> Lesson?
    @State private var showPractice = false
    @State private var queuedLesson: Lesson?

    init(lesson: Lesson, store: Store, followUpLesson: @escaping () -> Lesson? = { nil }) {
        self.lesson = lesson
        self.store = store
        self.followUpLesson = followUpLesson
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(lesson.title).font(.displayM).foregroundStyle(Palette.ink)
                    .padding(.top, 4)
                Text(lesson.intro).font(.bodyL).foregroundStyle(Palette.inkSoft)
                    .padding(.bottom, 4)

                if let visual = lesson.visual {
                    LessonVisualCard(visual: visual)
                }

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
            PracticeView(
                lesson: lesson,
                store: store,
                isReview: false,
                nextLessonProvider: followUpLesson
            ) { next in
                queuedLesson = next
                showPractice = false
            }
        }
        .navigationDestination(item: $queuedLesson) { next in
            LessonView(lesson: next, store: store, followUpLesson: followUpLesson)
        }
    }
}

struct LessonVisualCard: View {
    let visual: LessonVisual

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.titleM)
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text("Visual")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                        .textCase(.uppercase)
                        .tracking(1.1)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)

                visualBody
                    .frame(height: 168)
                    .frame(maxWidth: .infinity)
                    .background(Palette.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var title: LocalizedStringResource {
        switch visual {
        case .numberLine: return "See the movement"
        case .triangle: return "See the shape"
        case .parabola: return "See the curve"
        case .derivativeSlope: return "See the slope"
        case .unitCircle: return "See the angle"
        case .barChart: return "See the data"
        case .vectorPlane: return "See the vector"
        case .compoundGrowth: return "See the growth"
        }
    }

    private var symbol: String {
        switch visual {
        case .numberLine: return "arrow.left.and.right"
        case .triangle: return "triangle"
        case .parabola, .derivativeSlope: return "chart.xyaxis.line"
        case .unitCircle: return "circle.dotted"
        case .barChart: return "chart.bar"
        case .vectorPlane: return "arrow.up.right"
        case .compoundGrowth: return "chart.line.uptrend.xyaxis"
        }
    }

    private var accessibilityLabel: LocalizedStringResource {
        switch visual {
        case .numberLine: return "Number line visual showing movement left and right."
        case .triangle: return "Triangle visual showing sides and height."
        case .parabola: return "Parabola visual showing a quadratic curve."
        case .derivativeSlope: return "Curve visual showing a tangent slope."
        case .unitCircle: return "Unit circle visual showing an angle and radius."
        case .barChart: return "Bar chart visual showing different values."
        case .vectorPlane: return "Coordinate plane visual showing a vector."
        case .compoundGrowth: return "Growth curve visual showing compounding."
        }
    }

    @ViewBuilder
    private var visualBody: some View {
        switch visual {
        case .numberLine:
            NumberLineVisual()
        case .triangle:
            TriangleVisual()
        case .parabola:
            CurveVisual(mode: .parabola)
        case .derivativeSlope:
            CurveVisual(mode: .slope)
        case .unitCircle:
            UnitCircleVisual()
        case .barChart:
            BarChartVisual()
        case .vectorPlane:
            VectorPlaneVisual()
        case .compoundGrowth:
            CurveVisual(mode: .growth)
        }
    }
}

private struct NumberLineVisual: View {
    var body: some View {
        GeometryReader { geo in
            let mid = geo.size.height * 0.52
            let w = geo.size.width
            Canvas { ctx, size in
                var axis = Path()
                axis.move(to: CGPoint(x: 24, y: mid))
                axis.addLine(to: CGPoint(x: w - 24, y: mid))
                ctx.stroke(axis, with: .color(Palette.inkFaint), lineWidth: 2)
                for i in 0...6 {
                    let x = 24 + (w - 48) * CGFloat(i) / 6
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: mid - 7))
                    tick.addLine(to: CGPoint(x: x, y: mid + 7))
                    ctx.stroke(tick, with: .color(Palette.inkFaint), lineWidth: 1.5)
                }
                var arc = Path()
                arc.move(to: CGPoint(x: w * 0.28, y: mid))
                arc.addQuadCurve(to: CGPoint(x: w * 0.68, y: mid),
                                 control: CGPoint(x: w * 0.48, y: mid - 58))
                ctx.stroke(arc, with: .color(Palette.terracotta), style: StrokeStyle(lineWidth: 4, lineCap: .round))
            }
            HStack {
                Text("-3")
                Spacer()
                Text("0")
                Spacer()
                Text("3")
            }
            .font(.caption)
            .foregroundStyle(Palette.inkSoft)
            .padding(.horizontal, 20)
            .offset(y: mid + 12)
        }
    }
}

private struct TriangleVisual: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, _ in
                let a = CGPoint(x: size.width * 0.18, y: size.height * 0.78)
                let b = CGPoint(x: size.width * 0.78, y: size.height * 0.78)
                let c = CGPoint(x: size.width * 0.48, y: size.height * 0.24)
                var tri = Path()
                tri.move(to: a); tri.addLine(to: b); tri.addLine(to: c); tri.closeSubpath()
                ctx.fill(tri, with: .color(Palette.geometry.opacity(0.18)))
                ctx.stroke(tri, with: .color(Palette.geometry), lineWidth: 4)
                var h = Path()
                h.move(to: c); h.addLine(to: CGPoint(x: c.x, y: a.y))
                ctx.stroke(h, with: .color(Palette.terracotta), style: StrokeStyle(lineWidth: 3, dash: [6, 5]))
            }
        }
    }
}

private struct CurveVisual: View {
    enum Mode { case parabola, slope, growth }
    let mode: Mode

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 24
            var axes = Path()
            axes.move(to: CGPoint(x: inset, y: size.height - inset))
            axes.addLine(to: CGPoint(x: size.width - inset, y: size.height - inset))
            axes.move(to: CGPoint(x: inset, y: size.height - inset))
            axes.addLine(to: CGPoint(x: inset, y: inset))
            ctx.stroke(axes, with: .color(Palette.inkFaint.opacity(0.7)), lineWidth: 1.5)

            var curve = Path()
            for i in 0...80 {
                let t = CGFloat(i) / 80
                let x = inset + t * (size.width - inset * 2)
                let y: CGFloat
                switch mode {
                case .parabola:
                    y = size.height - inset - pow((t - 0.5) * 2, 2) * (size.height - inset * 2)
                case .slope:
                    y = size.height - inset - (0.18 + 0.62 * t + 0.12 * sin(t * .pi * 2)) * (size.height - inset * 2)
                case .growth:
                    y = size.height - inset - (pow(t, 2.2) * 0.82 + 0.06) * (size.height - inset * 2)
                }
                if i == 0 { curve.move(to: CGPoint(x: x, y: y)) }
                else { curve.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(curve, with: .color(Palette.calculus), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

            if mode == .slope {
                var tangent = Path()
                tangent.move(to: CGPoint(x: size.width * 0.42, y: size.height * 0.55))
                tangent.addLine(to: CGPoint(x: size.width * 0.72, y: size.height * 0.30))
                ctx.stroke(tangent, with: .color(Palette.terracotta), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
    }
}

private struct UnitCircleVisual: View {
    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = min(size.width, size.height) * 0.34
            ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                       with: .color(Palette.trig), lineWidth: 4)
            var axes = Path()
            axes.move(to: CGPoint(x: center.x - r - 18, y: center.y))
            axes.addLine(to: CGPoint(x: center.x + r + 18, y: center.y))
            axes.move(to: CGPoint(x: center.x, y: center.y - r - 18))
            axes.addLine(to: CGPoint(x: center.x, y: center.y + r + 18))
            ctx.stroke(axes, with: .color(Palette.inkFaint), lineWidth: 1.5)
            let end = CGPoint(x: center.x + r * 0.72, y: center.y - r * 0.72)
            var radius = Path()
            radius.move(to: center); radius.addLine(to: end)
            ctx.stroke(radius, with: .color(Palette.terracotta), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }
}

private struct BarChartVisual: View {
    private let values: [CGFloat] = [0.38, 0.68, 0.52, 0.86, 0.46]
    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(index == 3 ? Palette.stats : Palette.stats.opacity(0.42))
                    .frame(height: 118 * value)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
    }
}

private struct VectorPlaneVisual: View {
    var body: some View {
        Canvas { ctx, size in
            let center = CGPoint(x: size.width * 0.42, y: size.height * 0.62)
            var grid = Path()
            for i in 1...4 {
                let x = size.width * CGFloat(i) / 5
                grid.move(to: CGPoint(x: x, y: 18)); grid.addLine(to: CGPoint(x: x, y: size.height - 18))
                let y = size.height * CGFloat(i) / 5
                grid.move(to: CGPoint(x: 18, y: y)); grid.addLine(to: CGPoint(x: size.width - 18, y: y))
            }
            ctx.stroke(grid, with: .color(Palette.hairline), lineWidth: 1)
            let end = CGPoint(x: size.width * 0.70, y: size.height * 0.30)
            var vector = Path()
            vector.move(to: center); vector.addLine(to: end)
            ctx.stroke(vector, with: .color(Palette.algebra), style: StrokeStyle(lineWidth: 5, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 7, y: end.y - 7, width: 14, height: 14)), with: .color(Palette.algebra))
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
    var nextLessonProvider: (() -> Lesson?)? = nil
    var onStartNextLesson: ((Lesson) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// Modern SwiftUI in-app review prompt — shown at most once per app
    /// version per device by Apple, regardless of how often we call it.
    /// Triggered by `ReviewPromptGate` after a meaningful progress milestone.
    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL
    @AppStorage("mathio.notifications.enabled") private var notificationsEnabled = false

    @State private var index: Int = 0
    @State private var input: String = ""
    @State private var selectedChoice: Int? = nil
    @State private var trueFalseValue: Bool? = nil
    @State private var state: AnswerState = .pending
    @State private var showHint: Bool = false
    @State private var sessionCorrect: Int = 0
    @State private var sessionMissedQuestions: [Question] = []
    @State private var retryLesson: Lesson?
    @State private var showQuitConfirm: Bool = false
    @State private var didCelebrate: Bool = false
    @State private var hideReviewOffer: Bool = false
    @State private var hideReminderOffer: Bool = false
    @State private var reminderFeedback: LocalizedStringResource?

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
        .navigationDestination(item: $retryLesson) { retry in
            PracticeView(lesson: retry, store: store, isReview: false)
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
                if lesson.questions.count > 0 {
                    sessionInsightCard
                }
                if shouldShowShareOffer {
                    shareWinCard
                }
                if shouldShowRetryOffer {
                    retryMissesCard
                }
                if shouldShowReviewOffer {
                    reviewOfferCard
                }
                if shouldShowReminderOffer {
                    reminderOfferCard
                }
                if let next = nextLessonProvider?(), !isReview {
                    nextLessonCard(next)
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

    private var shouldShowReviewOffer: Bool {
        !hideReviewOffer && ReviewPromptGate.shouldOfferAfterCompletion(
            store: store,
            sessionCorrect: sessionCorrect,
            questionCount: lesson.questions.count,
            isReview: isReview
        )
    }

    private var shouldShowReminderOffer: Bool {
        !notificationsEnabled
        && !hideReminderOffer
        && lesson.questions.count > 0
        && sessionCorrect >= min(3, lesson.questions.count)
    }

    private var shouldShowShareOffer: Bool {
        lesson.questions.count > 0
        && sessionCorrect >= min(3, lesson.questions.count)
    }

    private var shouldShowRetryOffer: Bool {
        !sessionMissedQuestions.isEmpty
    }

    private var sessionAccuracyPercent: Int {
        guard lesson.questions.count > 0 else { return 0 }
        return Int((Double(sessionCorrect) / Double(lesson.questions.count) * 100).rounded())
    }

    private var sessionModeLabel: LocalizedStringResource {
        if isReview { return "Review" }
        if lesson.id.hasPrefix("__exam_sprint__") { return "Exam sprint" }
        if lesson.id.hasPrefix("__daily") { return "Daily challenge" }
        if lesson.id.hasPrefix("__weak") { return "Weak spot drill" }
        return "Lesson"
    }

    private var nextBestStep: LocalizedStringResource {
        if shouldShowRetryOffer {
            return "Retry misses while the solution is still fresh."
        }
        if isReview {
            return "Your review queue is cleaner. Continue with the next lesson."
        }
        if nextLessonProvider?() != nil {
            return "Start the next lesson while the rhythm is warm."
        }
        return "Come back tomorrow for another short session."
    }

    private var sessionInsightCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.success)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Session insight")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text(nextBestStep)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 10) {
                    insightMetric(value: "\(sessionAccuracyPercent)%", label: "Accuracy")
                    insightMetric(value: "\(sessionMissedQuestions.count)", label: "Missed")
                    insightMetric(value: String(localized: sessionModeLabel), label: "Mode")
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func insightMetric(value: String, label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.titleM)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkFaint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var retryMissesLesson: Lesson {
        Lesson(
            id: "__retry_misses__\(lesson.id)",
            title: "Retry missed questions",
            intro: "A short second pass through the questions you missed in this session.",
            formulas: lesson.formulas,
            questions: sessionMissedQuestions
        )
    }

    private var retryMissesCard: some View {
        Card(padding: 16, background: Palette.terracottaSoft.opacity(0.55)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.counterclockwise.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.terracotta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fix the misses now")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("\(sessionMissedQuestions.count) missed questions are ready for a quick second pass.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                PrimaryButton(title: "Retry missed questions", icon: "arrow.counterclockwise") {
                    retryLesson = retryMissesLesson
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var shareMessage: String {
        String(localized: "I practiced with Mathio today. Building my math streak one day at a time: https://apps.apple.com/app/id6767033115")
    }

    private var shareWinCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.calculus)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share your progress")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("You just finished a focused Mathio session. Let a friend know you're building the habit.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                ShareLink(item: shareMessage) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share progress").fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Palette.ink)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var reviewOfferCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Palette.terracotta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enjoying Mathio?")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("Is it helping you learn? A quick rating helps more learners find it.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                HStack(spacing: 10) {
                    SecondaryButton(title: "Send feedback") {
                        ReviewPromptGate.markPrompted()
                        hideReviewOffer = true
                        openURL(Links.support)
                    }
                    PrimaryButton(title: "Rate Mathio", icon: "star.fill") {
                        ReviewPromptGate.markPrompted()
                        hideReviewOffer = true
                        requestReview()
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private var reminderOfferCard: some View {
        Card(padding: 16, background: Palette.amberSoft) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(Palette.terracotta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Practice again tomorrow")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("Let Mathio remind you at \(NotificationManager.formattedTime()), after today's progress has settled.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                    }
                }
                if let reminderFeedback {
                    Text(reminderFeedback)
                        .font(.label)
                        .foregroundStyle(Palette.success)
                }
                HStack(spacing: 10) {
                    SecondaryButton(title: "Not now") {
                        withAnimation(.easeOut(duration: 0.2)) {
                            hideReminderOffer = true
                        }
                    }
                    PrimaryButton(title: "Remind me tomorrow", icon: "bell.fill") {
                        enableTomorrowReminder()
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func nextLessonCard(_ next: Lesson) -> some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.forward.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.calculus)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keep learning")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text(next.title)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                PrimaryButton(title: "Next lesson", icon: "arrow.right") {
                    onStartNextLesson?(next)
                }
            }
        }
    }

    private func enableTomorrowReminder() {
        Task {
            let granted = await NotificationManager.requestAuthorization()
            await MainActor.run {
                if granted {
                    notificationsEnabled = true
                    NotificationManager.scheduleDailyReminder()
                    reminderFeedback = "Reminder set"
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        hideReminderOffer = true
                    }
                }
            }
        }
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
        if isCorrect {
            sessionCorrect += 1
        } else if !sessionMissedQuestions.contains(where: { $0.id == q.id }) {
            sessionMissedQuestions.append(q)
        }
        store.record(questionId: q.id, correct: isCorrect)

        // Review prompts are intentionally delayed until the completion screen,
        // after the user has felt the full value moment.
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

private struct Achievement: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let icon: String
    let unlocked: Bool
    let progress: Double
}

private struct RoadmapPhase: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let subtitle: LocalizedStringResource
    let lessonCount: Int
    let progress: Double
    let color: Color
}

private struct MistakeFocus: Identifiable {
    let topic: Topic
    let lesson: Lesson
    let question: Question
    let entry: AnsweredEntry

    var id: String { question.id }
    var misses: Int { max(0, entry.attempts - entry.correct) }
}

private struct LessonTarget: Identifiable {
    let topic: Topic
    let lesson: Lesson
    let mastery: Double

    var id: String { lesson.id }
    var remainingQuestions: Int {
        max(0, lesson.questions.count - Int((mastery * Double(lesson.questions.count)).rounded()))
    }
}

struct StatsView: View {
    @Bindable var store: Store
    @Bindable var settings: UserSettings
    let topics: [Topic]
    @Environment(\.dismiss) private var dismiss
    @State private var mistakeDrill: Lesson?

    private var totalQuestions: Int {
        topics.reduce(0) { $0 + $1.questionCount }
    }
    private var totalCorrect: Int {
        store.answered.values.reduce(0) { $0 + $1.correct }
    }
    private var masteredQuestions: Int {
        min(totalQuestions, Int((overallMastery * Double(totalQuestions)).rounded()))
    }
    private var remainingQuestions: Int {
        max(0, totalQuestions - masteredQuestions)
    }
    private var estimatedDaysRemaining: Int {
        guard remainingQuestions > 0 else { return 0 }
        return Int(ceil(Double(remainingQuestions) / Double(max(settings.dailyGoal, 1))))
    }
    private var estimatedMonthsRemaining: Int {
        guard estimatedDaysRemaining > 0 else { return 0 }
        return max(1, Int(ceil(Double(estimatedDaysRemaining) / 30.0)))
    }
    private var overallMastery: Double {
        guard totalQuestions > 0 else { return 0 }
        let weighted = topics.reduce(0.0) { total, topic in
            total + store.mastery(for: topic) * Double(topic.questionCount)
        }
        return weighted / Double(totalQuestions)
    }
    private var focusTopics: [Topic] {
        topics.filter { store.mastery(for: $0) < 1.0 }
              .sorted { store.mastery(for: $0) < store.mastery(for: $1) }
              .prefix(3)
              .map { $0 }
    }
    private var hasAnyProgress: Bool {
        store.answered.values.contains { $0.attempts > 0 }
    }
    private var lessonTargets: [LessonTarget] {
        topics.flatMap { topic in
            topic.lessons.map { lesson in
                LessonTarget(topic: topic, lesson: lesson, mastery: store.mastery(for: lesson))
            }
        }
        .filter { $0.mastery < 1.0 }
        .sorted { lhs, rhs in
            if lhs.mastery != rhs.mastery { return lhs.mastery < rhs.mastery }
            return lhs.lesson.questions.count > rhs.lesson.questions.count
        }
        .prefix(4)
        .map { $0 }
    }
    private var mistakeFocus: [MistakeFocus] {
        topics.flatMap { topic in
            topic.lessons.flatMap { lesson in
                lesson.questions.compactMap { question -> MistakeFocus? in
                    guard let entry = store.answered[question.id],
                          entry.attempts > 0,
                          entry.attempts - entry.correct > 0 || !entry.isMastered else { return nil }
                    return MistakeFocus(topic: topic, lesson: lesson, question: question, entry: entry)
                }
            }
        }
        .sorted { lhs, rhs in
            if lhs.misses != rhs.misses { return lhs.misses > rhs.misses }
            if lhs.entry.attempts != rhs.entry.attempts { return lhs.entry.attempts > rhs.entry.attempts }
            return lhs.entry.lastAt > rhs.entry.lastAt
        }
        .prefix(5)
        .map { $0 }
    }
    private var mistakeDrillLesson: Lesson {
        Lesson(
            id: "__mistake_drill__",
            title: "Mistake drill",
            intro: "A focused set built from questions you have missed before.",
            formulas: [],
            questions: mistakeFocus.map(\.question)
        )
    }
    private var achievements: [Achievement] {
        [
            Achievement(
                id: "first-spark",
                title: "First spark",
                subtitle: "Answer one question correctly.",
                icon: "sparkles",
                unlocked: totalCorrect >= 1,
                progress: min(1, Double(totalCorrect))
            ),
            Achievement(
                id: "daily-finisher",
                title: "Daily finisher",
                subtitle: "Hit today's daily goal.",
                icon: "target",
                unlocked: store.correctToday() >= settings.dailyGoal,
                progress: min(1, Double(store.correctToday()) / Double(max(settings.dailyGoal, 1)))
            ),
            Achievement(
                id: "three-day-rhythm",
                title: "Three-day rhythm",
                subtitle: "Build a 3-day streak.",
                icon: "flame.fill",
                unlocked: store.streakDays >= 3,
                progress: min(1, Double(store.streakDays) / 3.0)
            ),
            Achievement(
                id: "momentum-maker",
                title: "Momentum maker",
                subtitle: "Reach 25 correct answers.",
                icon: "bolt.fill",
                unlocked: totalCorrect >= 25,
                progress: min(1, Double(totalCorrect) / 25.0)
            ),
            Achievement(
                id: "halfway-explorer",
                title: "Halfway explorer",
                subtitle: "Master 50% of the roadmap.",
                icon: "map.fill",
                unlocked: overallMastery >= 0.5,
                progress: min(1, overallMastery / 0.5)
            ),
            Achievement(
                id: "century-club",
                title: "Century club",
                subtitle: "Reach 100 correct answers.",
                icon: "100.circle.fill",
                unlocked: totalCorrect >= 100,
                progress: min(1, Double(totalCorrect) / 100.0)
            )
        ]
    }
    private var unlockedAchievementCount: Int {
        achievements.filter(\.unlocked).count
    }
    private var roadmapPhases: [RoadmapPhase] {
        [
            phase(
                id: "foundations",
                title: "Foundations",
                subtitle: "Pre-Algebra, Algebra, Geometry",
                topicIDs: ["prealgebra", "algebra", "geometry"],
                color: Palette.algebra
            ),
            phase(
                id: "exam-core",
                title: "Exam core",
                subtitle: "Trigonometry, Calculus, Statistics",
                topicIDs: ["trig", "calculus", "statistics"],
                color: Palette.calculus
            ),
            phase(
                id: "extension",
                title: "Extension",
                subtitle: "Finance, Linear Algebra, Discrete Math",
                topicIDs: ["financialmath", "linearalgebra", "discretemath"],
                color: Palette.precalc
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerStats
                    forecastCard
                    if !lessonTargets.isEmpty { studyTargetsCard }
                    achievementsCard
                    activityCard
                    masteryCard
                    if !mistakeFocus.isEmpty { mistakeNotebookCard }
                    if hasAnyProgress, !focusTopics.isEmpty { focusCard }
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
            .navigationDestination(item: $mistakeDrill) { lesson in
                PracticeView(lesson: lesson, store: store, isReview: false)
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

    private var achievementsCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(title: "Achievements")
                    Spacer()
                    Text("\(unlockedAchievementCount)/\(achievements.count) unlocked")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }

                ForEach(achievements) { achievement in
                    achievementRow(achievement)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        HStack(spacing: 12) {
            Image(systemName: achievement.unlocked ? "checkmark.seal.fill" : achievement.icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(achievement.unlocked ? Palette.success : Palette.terracotta)
                .frame(width: 38, height: 38)
                .background((achievement.unlocked ? Palette.success : Palette.terracotta).opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(achievement.title)
                        .font(.bodyM.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    Text(achievement.unlocked ? "Unlocked" : "\(Int(achievement.progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(achievement.unlocked ? Palette.success : Palette.inkFaint)
                }
                Text(achievement.subtitle)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                ProgressBar(progress: achievement.progress,
                            color: achievement.unlocked ? Palette.success : Palette.terracotta,
                            height: 4)
            }
        }
        .padding(12)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var forecastCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "map")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Palette.calculus)
                        .frame(width: 38, height: 38)
                        .background(Palette.calculus.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Learning forecast")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text(forecastSummary)
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ProgressBar(progress: overallMastery, color: Palette.calculus, height: 6)

                HStack(spacing: 10) {
                    forecastMetric(value: "\(masteredQuestions)", label: "Mastered")
                    forecastMetric(value: "\(remainingQuestions)", label: "Remaining")
                    forecastMetric(value: forecastTimeValue, label: forecastTimeLabel)
                }

                VStack(spacing: 10) {
                    ForEach(roadmapPhases) { phase in
                        roadmapPhaseRow(phase)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Learning forecast. \(masteredQuestions) mastered, \(remainingQuestions) remaining."))
    }

    private var forecastSummary: LocalizedStringResource {
        if remainingQuestions == 0 {
            return "Full roadmap mastered. Keep reviews warm."
        }
        if estimatedMonthsRemaining > 1 {
            return "About \(estimatedMonthsRemaining) months left at your current daily goal."
        }
        return "About \(estimatedDaysRemaining) days left at your current daily goal."
    }

    private var forecastTimeValue: String {
        estimatedMonthsRemaining > 1 ? "\(estimatedMonthsRemaining)" : "\(estimatedDaysRemaining)"
    }

    private var forecastTimeLabel: LocalizedStringResource {
        estimatedMonthsRemaining > 1 ? "Months" : "Days"
    }

    private func forecastMetric(value: String, label: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.titleM)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption)
                .foregroundStyle(Palette.inkSoft)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func phase(id: String, title: LocalizedStringResource, subtitle: LocalizedStringResource,
                       topicIDs: Set<String>, color: Color) -> RoadmapPhase {
        let phaseTopics = topics.filter { topicIDs.contains($0.id) }
        let questionCount = phaseTopics.reduce(0) { $0 + $1.questionCount }
        let weightedMastery = phaseTopics.reduce(0.0) { total, topic in
            total + store.mastery(for: topic) * Double(topic.questionCount)
        }
        let progress = questionCount == 0 ? 0 : weightedMastery / Double(questionCount)
        let lessons = phaseTopics.reduce(0) { $0 + $1.lessons.count }
        return RoadmapPhase(
            id: id,
            title: title,
            subtitle: subtitle,
            lessonCount: lessons,
            progress: progress,
            color: color
        )
    }

    private func roadmapPhaseRow(_ phase: RoadmapPhase) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(phase.title)
                        .font(.bodyM.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text(phase.subtitle)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 8)
                Text("\(Int((phase.progress * 100).rounded()))% · \(phase.lessonCount) lessons")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
            ProgressBar(progress: phase.progress, color: phase.color, height: 5)
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var studyTargetsCard: some View {
        Card(padding: 16, background: Palette.surface) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "scope")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Palette.terracotta)
                        .frame(width: 38, height: 38)
                        .background(Palette.terracottaSoft, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Next study targets")
                            .font(.titleM)
                            .foregroundStyle(Palette.ink)
                        Text("These lessons can move your roadmap fastest right now.")
                            .font(.bodyM)
                            .foregroundStyle(Palette.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                ForEach(lessonTargets) { target in
                    lessonTargetRow(target)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func lessonTargetRow(_ target: LessonTarget) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: target.topic.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(target.topic.color)
                    .frame(width: 30, height: 30)
                    .background(target.topic.color.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(target.lesson.title)
                        .font(.bodyM.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    Text(target.topic.title)
                        .font(.caption)
                        .foregroundStyle(Palette.inkSoft)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text("\(target.remainingQuestions) left")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            HStack(spacing: 8) {
                ProgressBar(progress: target.mastery, color: target.topic.color, height: 5)
                Text("\(Int((target.mastery * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(12)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var mistakeNotebookCard: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(title: "Mistake notebook")
                    Spacer()
                    Text("\(mistakeFocus.count) to revisit")
                        .font(.caption)
                        .foregroundStyle(Palette.inkFaint)
                }

                Text("Mathio turns missed answers into a focused drill, so weak spots do not disappear into the history.")
                    .font(.bodyM)
                    .foregroundStyle(Palette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(mistakeFocus.prefix(3)) { item in
                    mistakeRow(item)
                }

                PrimaryButton(title: "Practice missed questions", icon: "scope") {
                    mistakeDrill = mistakeDrillLesson
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func mistakeRow(_ item: MistakeFocus) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.terracotta)
                .frame(width: 36, height: 36)
                .background(Palette.terracottaSoft, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(item.lesson.title)
                    .font(.bodyM.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(item.question.prompt)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .lineLimit(2)
                Text("\(item.misses) misses · \(item.entry.correct) correct")
                    .font(.caption)
                    .foregroundStyle(Palette.inkFaint)
            }
        }
        .padding(12)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var focusCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Focus next")
                Text("Your lowest-mastery areas are the best place to earn quick progress.")
                    .font(.bodyM)
                    .foregroundStyle(Palette.inkSoft)
                ForEach(focusTopics) { topic in
                    HStack(spacing: 12) {
                        Image(systemName: topic.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(topic.color)
                            .frame(width: 38, height: 38)
                            .background(topic.color.opacity(0.15), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(topic.title)
                                .font(.titleM)
                                .foregroundStyle(Palette.ink)
                            Text("\(Int(store.mastery(for: topic) * 100))% mastery · \(topic.lessons.count) lessons")
                                .font(.bodyM)
                                .foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        ProgressRing(progress: store.mastery(for: topic), size: 34, lineWidth: 4, color: topic.color)
                    }
                    .padding(12)
                    .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    /// Tap counter on the version label. When it hits 7 we toggle the
    /// reviewer-override flag in `PremiumStore`. Documented in the App
    /// Review notes so the reviewer can unlock premium without purchase.
    @State private var versionTapCount = 0
    /// True for ~1.4 s after the override is toggled — drives a small
    /// confirmation banner so the reviewer sees their action took effect.
    @State private var showOverrideToast = false

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
                    Toggle("Daily reminder", isOn: Binding(
                        get: { settings.notificationsEnabled },
                        set: { newValue in
                            settings.notificationsEnabled = newValue
                            Task { await applyNotificationPreference(newValue) }
                        }
                    ))
                    Picker("Reminder time", selection: Binding(
                        get: { settings.reminderHour },
                        set: { newValue in
                            settings.reminderHour = newValue
                            if settings.notificationsEnabled {
                                NotificationManager.scheduleDailyReminder(hour: newValue)
                            }
                        }
                    )) {
                        Text("17:00").tag(17)
                        Text("19:00").tag(19)
                        Text("21:00").tag(21)
                    }
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
                    Link("Privacy policy",   destination: Links.privacy)
                    Link("Terms of service", destination: Links.terms)
                    Link("Support",          destination: Links.support)
                }

                Section {
                    EmptyView()
                } footer: {
                    versionFooter
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .overlay(alignment: .top) {
                if showOverrideToast {
                    ReviewerOverlayToast(active: premiumStore.reviewerOverride)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
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
                NotificationManager.scheduleDailyReminder(hour: settings.reminderHour)
            } else {
                settings.notificationsEnabled = false
            }
        } else {
            NotificationManager.cancelDailyReminder()
        }
    }

    /// Footer line with the build version. Tapping it 7 times toggles the
    /// reviewer-override flag — the documented App Review demo path. The
    /// gesture is silent for casual users (no UI hint) and confirmed via a
    /// short toast once activated.
    private var versionFooter: some View {
        let bundle = Bundle.main.infoDictionary
        let version = bundle?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = bundle?["CFBundleVersion"] as? String ?? "1"
        let label = "Mathio \(version) (\(build))"
        return Text(label)
            .font(.system(size: 13, weight: .regular, design: .default))
            .foregroundStyle(Palette.inkFaint)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { handleVersionTap() }
            .accessibilityLabel(Text(label))
    }

    private func handleVersionTap() {
        versionTapCount += 1
        guard versionTapCount >= 7 else { return }
        versionTapCount = 0
        premiumStore.toggleReviewerOverride()
        withAnimation(.easeOut(duration: 0.2)) { showOverrideToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeIn(duration: 0.2)) { showOverrideToast = false }
        }
    }
}

/// Brief banner shown after the reviewer-override gesture toggles. Confirms
/// the new state so the App Review tester sees the action took effect.
private struct ReviewerOverlayToast: View {
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: active ? "lock.open.fill" : "lock.fill")
            Text(active ? "Premium unlocked for review" : "Reviewer override cleared")
                .font(.bodyM)
        }
        .foregroundStyle(Palette.background)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.ink, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
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
                    audience
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
                Text("Learn math with a full roadmap").font(.displayL).foregroundStyle(Palette.ink)
                Text("Premium unlocks the complete curriculum, guided paths, and every worked solution.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
            case .retention:
                Text("Wait — special offer").font(.displayL).foregroundStyle(Palette.ink)
                Text("Stay one more year for 25% off.")
                    .font(.bodyL).foregroundStyle(Palette.inkSoft)
            }
        }
    }

    private var audience: some View {
        Card(padding: 16, background: Palette.surfaceMuted) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Built for")
                    .font(.label)
                    .foregroundStyle(Palette.inkFaint)
                    .textCase(.uppercase)
                    .tracking(1.2)
                VStack(alignment: .leading, spacing: 8) {
                    row("graduationcap.fill", "Students preparing for homework, exams, and finals")
                    row("person.fill.checkmark", "Self-learners who want structure without distractions")
                    row("figure.and.child.holdinghands", "Parents who want clear practice instead of random drills")
                }
            }
        }
    }

    private var bullets: some View {
        VStack(alignment: .leading, spacing: 12) {
            row("books.vertical.fill", "81 lessons across algebra, calculus, geometry, statistics, finance, and more")
            row("map.fill", "Guided paths show exactly what to study next")
            row("brain.head.profile", "Adaptive practice focuses on weak spots")
            row("arrow.triangle.2.circlepath", "Spaced repetition brings back what you are about to forget")
            row("lightbulb.max.fill", "Worked solutions explain every missed answer")
        }
    }

    private func row(_ icon: String, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Palette.terracotta)
            Text(text)
                .font(.bodyL)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
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
                    Text("ANNUAL · 25% OFF").font(.label).foregroundStyle(Palette.terracotta)
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

    private func planSubtitle(_ plan: Plan) -> LocalizedStringResource {
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

    private var weeklyPrice: String    { premiumStore.price(for: .weekly, fallback: "$12.99") }
    private var annualPrice: String    { premiumStore.price(for: .annual, fallback: "$59.99") }
    private var retentionPrice: String { premiumStore.price(for: .retention, fallback: "$44.99") }

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
            if let purchaseMessage = premiumStore.purchaseMessage {
                Text(purchaseMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            HStack {
                Button("Restore purchases") { Task { await premiumStore.restore() } }
                Spacer()
                Link("Terms", destination: Links.terms)
                Spacer()
                Link("Privacy", destination: Links.privacy)
            }
            .font(.caption).foregroundStyle(Palette.inkFaint)
        }
    }

    private var ctaTitle: LocalizedStringResource {
        switch mode {
        case .retention: return "Keep my access at 25% off"
        default:
            return selected == .weekly
                ? "Start 3-day free trial"
                : "Start 7-day free trial"
        }
    }

    @MainActor
    private func purchase() async {
        let target: PremiumPlan
        switch mode {
        case .retention:
            target = .retention
        default:
            target = selected == .annual ? .annual : .weekly
        }
        await premiumStore.purchase(target)
        if premiumStore.isPremium { dismiss() }
    }
}
