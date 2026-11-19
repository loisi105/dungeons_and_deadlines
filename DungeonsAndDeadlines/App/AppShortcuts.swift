import AppIntents
import DDIntents

/// Siri, Spotlight, Shortcuts and Action button phrases.
struct DungeonsAndDeadlinesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Start focus in \(.applicationName)", "Attack the boss in \(.applicationName)"],
            shortTitle: "Start Focus",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: StopFocusIntent(),
            phrases: ["Stop focus in \(.applicationName)", "Finish my attack in \(.applicationName)"],
            shortTitle: "Stop Focus",
            systemImageName: "bolt.fill"
        )
        AppShortcut(
            intent: CompleteTaskIntent(),
            phrases: ["Complete a task in \(.applicationName)", "Hit the boss in \(.applicationName)"],
            shortTitle: "Complete Task",
            systemImageName: "checkmark.circle.fill"
        )
    }
}
