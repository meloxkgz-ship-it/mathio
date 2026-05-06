import SwiftUI

@main
struct MathioApp: App {
    @State private var store = Store()
    @State private var premiumStore = PremiumStore()
    @State private var settings = UserSettings()

    var body: some Scene {
        WindowGroup {
            RootView(store: store, premiumStore: premiumStore, settings: settings)
                .tint(Palette.terracotta)
                .background(Palette.background.ignoresSafeArea())
        }
    }
}
