import Foundation
import GameCore
import DDPersistence
#if canImport(WidgetKit)
import WidgetKit
#endif

/// The single place where user actions happen. Intents (and the app's buttons through them)
/// call these; each one writes to the store, then refreshes every surface.
@MainActor
public enum GameActions {
    public static var store: RaidStore { DDStore.shared }
    public static var me: LocalIdentity { LocalIdentity.current }

    /// Set by the app to push the outbox to Firebase after each change.
    public static var onChange: (@MainActor (UUID?) -> Void)?

    public enum ActionError: LocalizedError {
        case noRaid
        public var errorDescription: String? { String(localized: "There's no raid to act on. Create or join one in the app.") }
    }

    static func raidID(_ id: UUID?) throws -> UUID {
        if let id { return id }
        guard let raid = store.currentRaid() else { throw ActionError.noRaid }
        return raid.id
    }

    @discardableResult
    public static func completeTask(_ taskID: UUID) throws -> Attack? {
        let attack = try store.completeTask(taskID, by: me.memberID)
        changed(store.task(taskID)?.raidID)
        return attack
    }

    public static func startFight(_ raidID: UUID?) throws {
        let id = try self.raidID(raidID)
        try store.startFight(id, by: me.memberID)
        changed(id)
    }

    /// Brings a finished boss back for follow-up tasks with a new deadline.
    public static func resumeFight(_ raidID: UUID, deadline: Date) throws {
        try store.resumeFight(raidID, by: me.memberID, deadline: deadline)
        changed(raidID)
    }

    @discardableResult
    public static func startFocus(_ raidID: UUID?) throws -> FocusSession {
        let id = try self.raidID(raidID)
        // Only one timer at a time: stop a timer running in another raid first.
        if let other = store.activeFocusSession(memberID: me.memberID), other.raidID != id {
            try store.stopFocus(raidID: other.raidID, memberID: me.memberID)
            changed(other.raidID)
        }
        let session = try store.startFocus(raidID: id, memberID: me.memberID)
        changed(id)
        return session
    }

    public static func pauseFocus(_ raidID: UUID?) throws {
        let id = try activeOrCurrentRaidID(raidID)
        try store.pauseFocus(raidID: id, memberID: me.memberID)
        changed(id)
    }

    @discardableResult
    public static func stopFocus(_ raidID: UUID?) throws -> Attack? {
        let id = try activeOrCurrentRaidID(raidID)
        let attack = try store.stopFocus(raidID: id, memberID: me.memberID)
        changed(id)
        return attack
    }

    public static func isFocusRunning() -> Bool {
        store.activeFocusSession(memberID: me.memberID)?.state == .running
    }

    static func activeOrCurrentRaidID(_ raidID: UUID?) throws -> UUID {
        if let raidID { return raidID }
        if let active = store.activeFocusSession(memberID: me.memberID) { return active.raidID }
        return try self.raidID(nil)
    }

    /// Refresh widgets, controls and the Live Activity, then let the app sync.
    public static func changed(_ raidID: UUID?) {
        reloadSystemSurfaces()
        #if os(iOS)
        if let raidID { LiveActivityController.sync(raidID: raidID) }
        #endif
        onChange?(raidID)
    }

    public static func reloadSystemSurfaces() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #if os(iOS)
        ControlCenter.shared.reloadAllControls()
        #endif
        #endif
    }
}
