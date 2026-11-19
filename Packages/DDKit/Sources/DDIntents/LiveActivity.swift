#if os(iOS)
import ActivityKit
import Foundation
import GameCore
import DDPersistence

/// Shared between the app (starts/updates) and the widget extension (draws).
public struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// `Text(timerInterval: reference...)` shows the running time without updates.
        public var timerReference: Date
        public var isRunning: Bool
        public var elapsedSeconds: Int
        public var currentHP: Int
        public var maxHP: Int
        public var phaseRaw: Int
        /// Teammates focusing right now ("X is attacking").
        public var attackers: [String]

        public var phase: Phase { Phase(rawValue: phaseRaw) ?? .calm }

        public init(timerReference: Date, isRunning: Bool, elapsedSeconds: Int, currentHP: Int, maxHP: Int, phaseRaw: Int, attackers: [String]) {
            self.timerReference = timerReference
            self.isRunning = isRunning
            self.elapsedSeconds = elapsedSeconds
            self.currentHP = currentHP
            self.maxHP = maxHP
            self.phaseRaw = phaseRaw
            self.attackers = attackers
        }
    }

    public var raidID: UUID
    public var raidName: String
    public var bossName: String

    public init(raidID: UUID, raidName: String, bossName: String) {
        self.raidID = raidID
        self.raidName = raidName
        self.bossName = bossName
    }
}

/// Starts, updates and ends the focus Live Activity from local state.
@MainActor
public enum LiveActivityController {
    public static func sync(raidID: UUID) {
        let store = DDStore.shared
        let me = LocalIdentity.current
        guard let raid = store.raid(raidID), let state = store.bossState(raidID) else {
            end(raidID: raidID)
            return
        }
        let session = store.focusSession(raidID: raidID, memberID: me.memberID)
        let existing = Activity<FocusActivityAttributes>.activities.first { $0.attributes.raidID == raidID }

        guard session.state != .idle, state.outcome == .ongoing else {
            if existing != nil { end(raidID: raidID) }
            return
        }

        let now = Date()
        let attackers = store.members(raidID)
            .filter { $0.id != me.memberID && $0.activeFocusSince != nil }
            .map(\.nickname)
        let content = FocusActivityAttributes.ContentState(
            timerReference: session.timerReferenceDate(at: now),
            isRunning: session.state == .running,
            elapsedSeconds: Int(session.elapsed(at: now)),
            currentHP: state.currentHP, maxHP: state.maxHP, phaseRaw: state.phase.rawValue,
            attackers: attackers
        )
        let activityContent = ActivityContent(state: content, staleDate: raid.deadline)

        if existing != nil {
            Task { await update(raidID: raidID, content: activityContent) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            let attributes = FocusActivityAttributes(raidID: raidID, raidName: raid.name, bossName: raid.bossName)
            _ = try? Activity.request(attributes: attributes, content: activityContent, pushType: nil)
        }
    }

    public static func end(raidID: UUID) {
        Task { await endActivities(raidID: raidID) }
    }

    // `Activity` isn't Sendable, so it is looked up and used off the main actor.
    nonisolated static func update(raidID: UUID, content: ActivityContent<FocusActivityAttributes.ContentState>) async {
        for activity in Activity<FocusActivityAttributes>.activities where activity.attributes.raidID == raidID {
            await activity.update(content)
        }
    }

    nonisolated static func endActivities(raidID: UUID) async {
        for activity in Activity<FocusActivityAttributes>.activities where activity.attributes.raidID == raidID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// Ends activities whose raid or session is gone (e.g. after the app was killed).
    public static func reconcile() {
        for activity in Activity<FocusActivityAttributes>.activities {
            sync(raidID: activity.attributes.raidID)
        }
        if let active = DDStore.shared.activeFocusSession(memberID: LocalIdentity.current.memberID) {
            sync(raidID: active.raidID)
        }
    }
}
#endif
