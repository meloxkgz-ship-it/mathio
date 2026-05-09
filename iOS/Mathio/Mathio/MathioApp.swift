import SwiftUI

/// Centralised, force-unwrap-free outbound URLs. Each value falls back to a
/// guaranteed-non-nil `URL(filePath:)` so a future typo in a host string can
/// never crash the app — the worst case becomes "tapping does nothing".
enum Links {
    static let privacy: URL = URL(string: "https://meloxkgz-ship-it.github.io/mathio/privacy")
        ?? URL(filePath: "/")
    static let terms: URL = URL(string: "https://meloxkgz-ship-it.github.io/mathio/terms")
        ?? URL(filePath: "/")
    static let support: URL = URL(string: "mailto:meloxkgz@icloud.com")
        ?? URL(filePath: "/")
}

/// Decides when to fire the in-app `requestReview()` prompt. Strategy: only
/// after a **success moment with proven engagement** — namely 10+ lifetime
/// correct answers AND a 3-day streak — and at most once per `MARKETING_VERSION`.
/// SKStoreReviewController itself further caps Apple's UI to ~3/year, so a
/// false positive here costs nothing.
enum ReviewPromptGate {
    private static let kPromptedVersion = "mathio.review.promptedVersion"
    private static let kCorrectMilestone = 10
    private static let kStreakMilestone = 3

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static func shouldPrompt(store: Store) -> Bool {
        let already = UserDefaults.standard.string(forKey: kPromptedVersion)
        guard already != currentVersion else { return false }
        let totalCorrect = store.answered.values.reduce(0) { $0 + $1.correct }
        return totalCorrect >= kCorrectMilestone && store.streakDays >= kStreakMilestone
    }

    static func markPrompted() {
        UserDefaults.standard.set(currentVersion, forKey: kPromptedVersion)
    }
}

@main
struct MathioApp: App {
    @State private var store: Store
    @State private var premiumStore = PremiumStore()
    @State private var settings = UserSettings()

    init() {
        #if DEBUG
        // Apply test-only seeding BEFORE Store reads the JSON, so the
        // synthetic activity shows up immediately on first launch.
        SeedActivity.runIfRequested(into: Store())
        #endif
        _store = State(initialValue: Store())
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Debug-only env-var routing for App Store screenshot capture.
            // Set MATHIO_PREVIEW=home|paywall|stats|lesson|practice|formulas|settings
            // when launching via simctl. Stripped from release builds.
            if let preview = ProcessInfo.processInfo.environment["MATHIO_PREVIEW"] {
                PreviewWrapper(target: preview, store: store,
                               premiumStore: premiumStore, settings: settings)
                    .tint(Palette.terracotta)
            } else {
                RootView(store: store, premiumStore: premiumStore, settings: settings)
                    .tint(Palette.terracotta)
                    .background(Palette.background.ignoresSafeArea())
            }
            #else
            RootView(store: store, premiumStore: premiumStore, settings: settings)
                .tint(Palette.terracotta)
                .background(Palette.background.ignoresSafeArea())
            #endif
        }
    }
}

#if DEBUG
/// Routes to a specific view when `MATHIO_PREVIEW` is set. For App Store
/// screenshot capture from the simulator without manually navigating.
struct PreviewWrapper: View {
    let target: String
    @Bindable var store: Store
    @Bindable var premiumStore: PremiumStore
    @Bindable var settings: UserSettings

    var body: some View {
        switch target {
        case "paywall":
            PaywallView(premiumStore: premiumStore, mode: .onboarding)
        case "stats":
            StatsView(store: store, topics: Curriculum.topics)
        case "settings":
            SettingsView(store: store, premiumStore: premiumStore, settings: settings)
        case "formulas":
            FormulaReferenceView(store: store, topics: Curriculum.topics)
        case "lesson":
            NavigationStack {
                LessonView(lesson: Curriculum.derivatives, store: store)
            }
        case "practice":
            NavigationStack {
                PracticeView(lesson: Curriculum.derivatives, store: store, isReview: false)
            }
        default:
            RootView(store: store, premiumStore: premiumStore, settings: settings)
                .background(Palette.background.ignoresSafeArea())
        }
    }
}
#endif
