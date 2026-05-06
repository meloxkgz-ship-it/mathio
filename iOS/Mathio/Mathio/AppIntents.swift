import AppIntents
import SwiftUI

// MARK: - App Intents
//
// "Practice Math" — opens the app and starts today's review queue.
// "Open Mathio" — plain launcher, useful for Siri suggestions.
//
// On launch, the app reads the `mathio.intent.pendingPractice` UserDefaults
// flag and, if set, jumps straight into review (or any free lesson if the
// queue is empty).

struct PracticeMathIntent: AppIntent {
    static let title: LocalizedStringResource = "Practice Math"
    static let description = IntentDescription("Start today's Mathio review session.")

    /// Lets Siri / Shortcuts open the app with this intent.
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "mathio.intent.pendingPractice")
        return .result()
    }
}

struct OpenMathioIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Mathio"
    static let openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - App Shortcuts

/// Registers built-in phrases so users discover the intent in Siri / Spotlight
/// without manually adding a shortcut.
struct MathioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PracticeMathIntent(),
            phrases: [
                "Practice math with \(.applicationName)",
                "Start \(.applicationName)",
                "Open \(.applicationName) practice"
            ],
            shortTitle: "Practice math",
            systemImageName: "function"
        )
        AppShortcut(
            intent: OpenMathioIntent(),
            phrases: [
                "Open \(.applicationName)"
            ],
            shortTitle: "Open Mathio",
            systemImageName: "infinity"
        )
    }
}
