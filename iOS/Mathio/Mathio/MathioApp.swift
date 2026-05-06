import SwiftUI

@main
struct MathioApp: App {
    @State private var store = Store()
    @State private var premiumStore = PremiumStore()
    @State private var settings = UserSettings()

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
