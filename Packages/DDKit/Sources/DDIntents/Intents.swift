import AppIntents
import Foundation
import GameCore
import DDPersistence
import DDDesign

// Every write intent also conforms to `LiveActivityIntent` (see the bottom of this file).
// That makes the system run it in the app's process even when it's triggered from a
// widget, the Live Activity or a Control, so the app's store, Live Activity and sync
// all see the change at once.

public struct CompleteTaskIntent: AppIntent {
    public static let title: LocalizedStringResource = "Complete Task"
    public static let description = IntentDescription("Marks a task as done and hits the boss.")

    @Parameter(title: "Task")
    public var task: TaskEntity

    public init() {}
    public init(task: TaskEntity) { self.task = task }

    public static var parameterSummary: some ParameterSummary {
        Summary("Complete \(\.$task)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let attack = try GameActions.completeTask(task.id)
        if let attack {
            return .result(dialog: "Hit for \(attack.damage) damage!")
        }
        return .result(dialog: "Task done.")
    }
}

public struct StartFightIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Boss Fight"
    public static let description = IntentDescription("Locks the boss's health and starts the fight.")

    @Parameter(title: "Raid")
    public var raid: RaidEntity?

    public init() {}
    public init(raid: RaidEntity?) { self.raid = raid }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try GameActions.startFight(raid?.id)
        return .result()
    }
}

public struct StartFocusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Focus"
    public static let description = IntentDescription("Starts a focus timer that deals damage over time.")

    @Parameter(title: "Raid")
    public var raid: RaidEntity?

    public init() {}
    public init(raid: RaidEntity?) { self.raid = raid }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try GameActions.startFocus(raid?.id)
        return .result(dialog: "Focus started. Go get that boss.")
    }
}

public struct PauseFocusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pause Focus"

    @Parameter(title: "Raid")
    public var raid: RaidEntity?

    public init() {}
    public init(raid: RaidEntity?) { self.raid = raid }

    @MainActor
    public func perform() async throws -> some IntentResult {
        try GameActions.pauseFocus(raid?.id)
        return .result()
    }
}

public struct StopFocusIntent: AppIntent {
    public static let title: LocalizedStringResource = "Stop Focus"
    public static let description = IntentDescription("Stops the focus timer and deals its damage.")

    @Parameter(title: "Raid")
    public var raid: RaidEntity?

    public init() {}
    public init(raid: RaidEntity?) { self.raid = raid }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        if let attack = try GameActions.stopFocus(raid?.id) {
            return .result(dialog: "Focus done: \(attack.damage) damage.")
        }
        return .result(dialog: "Focus stopped.")
    }
}

/// Backs the Control Center / Lock Screen / Action button toggle.
public struct ToggleFocusIntent: SetValueIntent {
    public static let title: LocalizedStringResource = "Toggle Focus"

    @Parameter(title: "Focusing")
    public var value: Bool

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        if value {
            try GameActions.startFocus(nil)
        } else {
            try GameActions.stopFocus(nil)
        }
        return .result()
    }
}

public struct OpenRaidIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Raid"
    public static let openAppWhenRun = true

    @Parameter(title: "Raid")
    public var raid: RaidEntity

    public init() {}
    public init(raid: RaidEntity) { self.raid = raid }

    @MainActor
    public func perform() async throws -> some IntentResult {
        LocalIdentity.currentRaidID = raid.id
        return .result()
    }
}

#if os(iOS)
extension CompleteTaskIntent: LiveActivityIntent {}
extension StartFightIntent: LiveActivityIntent {}
extension StartFocusIntent: LiveActivityIntent {}
extension PauseFocusIntent: LiveActivityIntent {}
extension StopFocusIntent: LiveActivityIntent {}
extension ToggleFocusIntent: LiveActivityIntent {}
#endif

/// Lets the app and widget extension pick up the intents defined in this package.
public struct DDIntentsPackage: AppIntentsPackage {}
