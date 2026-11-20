import Foundation
import Testing
import GameCore
import DDPersistence
@testable import DDIntents

/// Records what the shield was told to do.
@MainActor
final class FakeShielder: FocusShielding {
    enum Call: Equatable { case engage(until: Date, boss: String), release }
    var calls: [Call] = []
    var canEngage = true
    var isShielding: Bool {
        if case .engage = calls.last { return true }
        return false
    }
    func engage(until: Date, bossName: String) -> Bool {
        calls.append(.engage(until: until, boss: bossName))
        return canEngage
    }
    func release() { calls.append(.release) }
}

// Nested in the serialized "Intents" suite: both swap the process-wide `DDStore`,
// so they must not run at the same time.
extension IntentsTests {
@Suite("Focus shield hooks") @MainActor
struct FocusShieldTests {
    let store: RaidStore
    let raid: Raid
    let shielder = FakeShielder()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    var me: String { LocalIdentity.current.memberID }

    init() throws {
        store = RaidStore(container: try SharedContainer.make(inMemory: true))
        store.clock = { [start] in start }
        DDStore.use(store)
        raid = try store.createRaid(name: "Thesis", bossName: "Exam Dragon", deadline: start.addingTimeInterval(86_400 * 3), multiplayer: false, owner: LocalIdentity.current)
        LocalIdentity.currentRaidID = raid.id
        try store.addTask(raidID: raid.id, title: "Outline", size: .m)
        try store.startFight(raid.id, by: LocalIdentity.current.memberID)
        FocusBlockSettings.isEnabled = true
        FocusBlockSettings.pickedCount = 2
        FocusShield.invalidate()
        FocusShield.shielder = shielder
    }

    func tearDown() {
        FocusShield.shielder = nil
        FocusShield.invalidate()
        FocusBlockSettings.isEnabled = false
        FocusBlockSettings.pickedCount = 0
    }

    @Test("Start blocks, pause unblocks, resume blocks again, stop unblocks")
    func startPauseResumeStop() throws {
        defer { tearDown() }
        try GameActions.startFocus(raid.id)
        #expect(shielder.calls.count == 1)
        guard case .engage(let until, let boss) = shielder.calls.last else { Issue.record("not engaged"); return }
        #expect(boss == "Exam Dragon")
        #expect(until > start)

        store.clock = { [start] in start.addingTimeInterval(600) }
        try GameActions.pauseFocus(raid.id)
        #expect(shielder.calls.last == .release)

        try GameActions.startFocus(raid.id) // resume
        #expect(shielder.isShielding)

        try GameActions.stopFocus(raid.id)
        #expect(shielder.calls.last == .release)
    }

    @Test("Intents (Live Activity, Control Center, Siri) drive the shield too")
    func intents() async throws {
        defer { tearDown() }
        let toggle = ToggleFocusIntent()
        toggle.value = true
        _ = try await toggle.perform()
        #expect(shielder.isShielding)
        _ = try await PauseFocusIntent(raid: nil).perform()
        #expect(shielder.calls.last == .release)
        _ = try await StartFocusIntent(raid: nil).perform()
        #expect(shielder.isShielding)
        _ = try await StopFocusIntent(raid: nil).perform()
        #expect(shielder.calls.last == .release)
    }

    @Test("Unrelated changes don't re-apply the shield")
    func idempotent() throws {
        defer { tearDown() }
        try GameActions.startFocus(raid.id)
        GameActions.changed(raid.id)
        GameActions.changed(nil)
        #expect(shielder.calls.count == 1)
    }

    @Test("Nothing is blocked when the setting is off or no apps are picked")
    func settingOff() throws {
        defer { tearDown() }
        FocusBlockSettings.isEnabled = false
        try GameActions.startFocus(raid.id)
        #expect(!shielder.isShielding)

        FocusBlockSettings.isEnabled = true
        FocusBlockSettings.pickedCount = 0
        FocusShield.reconcile()
        #expect(!shielder.isShielding)

        FocusBlockSettings.pickedCount = 3
        FocusShield.reconcile()
        #expect(shielder.isShielding)
    }

    @Test("The shield ends when today's focus cap is used up")
    func capEndsShield() throws {
        defer { tearDown() }
        try GameActions.startFocus(raid.id)
        guard case .engage(let until, _) = shielder.calls.last else { Issue.record("not engaged"); return }
        let cap = TimeInterval(store.calculator.config.dailyFocusCapMinutes * 60)
        #expect(until <= start.addingTimeInterval(cap))
        // Launching the app after the cap: the timer still runs, but the block is lifted.
        FocusShield.reconcile(now: until.addingTimeInterval(1))
        #expect(shielder.calls.last == .release)
    }

    @Test("Deleting the raid with a running timer lifts the block")
    func deletingRaid() throws {
        defer { tearDown() }
        try GameActions.startFocus(raid.id)
        #expect(shielder.isShielding)
        // Leaving or deleting a boss (SyncEngine.leave) refreshes surfaces, not `changed`.
        try store.deleteRaidLocally(raid.id)
        GameActions.reloadSystemSurfaces()
        #expect(shielder.calls.last == .release)
    }

    @Test("A shield that couldn't go up (no Screen Time access) is retried on the next reconcile")
    func retriesWithoutAccess() throws {
        defer { tearDown() }
        shielder.canEngage = false
        try GameActions.startFocus(raid.id)
        #expect(FocusShield.current == nil)
        shielder.canEngage = true // access granted in Settings, app comes back
        GameActions.reloadSystemSurfaces()
        #expect(shielder.calls.count == 2)
        #expect(FocusShield.current != nil)
    }

    @Test("Without a shielder (tests, widgets, -uiTesting) nothing is touched")
    func noShielder() throws {
        defer { tearDown() }
        FocusShield.shielder = nil
        try GameActions.startFocus(raid.id)
        #expect(shielder.calls.isEmpty)
        #expect(FocusShield.current == nil)
    }
}
}
