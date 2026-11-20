import Foundation
import GameCore
import DDPersistence

/// Turns the Screen Time shield (apps the player picked) on and off. The app provides the
/// real implementation (ManagedSettings + a DeviceActivity safety net); tests use a fake.
@MainActor
public protocol FocusShielding: AnyObject {
    /// Blocks the picked apps until `until` (a safety net lifts the block then, even if the app is gone).
    /// Returns false if it couldn't (no Screen Time access), so the next reconcile tries again.
    func engage(until: Date, bossName: String) -> Bool
    /// Lifts the block.
    func release()
}

/// The player's "Block apps while focusing" settings, shared through the App Group.
public enum FocusBlockSettings {
    public static let enabledKey = "settings.focusBlock.enabled"
    /// JSON of the `FamilyActivitySelection` (iOS only; opaque here).
    public static let selectionKey = "settings.focusBlock.selection"
    /// How many apps, categories and websites are picked (readable without FamilyControls).
    public static let pickedCountKey = "settings.focusBlock.pickedCount"

    public static var isEnabled: Bool {
        get { AppGroup.defaults.bool(forKey: enabledKey) }
        set { AppGroup.defaults.set(newValue, forKey: enabledKey) }
    }

    public static var pickedCount: Int {
        get { AppGroup.defaults.integer(forKey: pickedCountKey) }
        set { AppGroup.defaults.set(newValue, forKey: pickedCountKey) }
    }
}

/// Keeps the shield in step with the focus timer. `GameActions.changed` calls `reconcile()`
/// after every change (app buttons, the Live Activity, the Control and Siri all go through it),
/// and the app calls it at launch and when it becomes active.
@MainActor
public enum FocusShield {
    /// Nil in tests, widgets and `-uiTesting`: then nothing touches Screen Time.
    public static var shielder: (any FocusShielding)?

    /// What was last sent to the shielder, so repeated reconciles don't redo the work.
    public private(set) static var current: FocusShieldPlan?

    /// Works out whether apps should be blocked now and tells the shielder if that changed.
    public static func reconcile(now: Date? = nil) {
        guard let shielder else { return }
        let plan = plan(now: now ?? GameActions.store.clock())
        guard plan != current else { return }
        switch plan {
        case .off:
            shielder.release()
            current = plan
        case .on(let until):
            let session = GameActions.store.activeFocusSession(memberID: GameActions.me.memberID)
            let bossName = session.flatMap { GameActions.store.raid($0.raidID)?.bossName } ?? ""
            // Not cached when it didn't apply (access missing), so granting access later works.
            current = shielder.engage(until: until, bossName: bossName) ? plan : nil
        }
    }

    /// Forgets what was sent last, so the next reconcile re-applies it (launch, new selection).
    public static func invalidate() {
        current = nil
    }

    public static func plan(now: Date) -> FocusShieldPlan {
        let store = GameActions.store
        let me = GameActions.me.memberID
        let session = store.activeFocusSession(memberID: me)
        var remaining = 0
        if let session, let raid = store.raid(session.raidID) {
            let context = DamageCalculator.Context(
                memberID: me, attacks: store.attacks(raid.id), memberCount: 1, lockedMaxHP: nil, now: now
            )
            remaining = store.calculator.remainingFocusSeconds(context)
        }
        return FocusShieldPlan.decide(
            enabled: FocusBlockSettings.isEnabled, hasSelection: FocusBlockSettings.pickedCount > 0,
            session: session, remainingCapSeconds: remaining, now: now, calendar: store.calculator.calendar
        )
    }
}
