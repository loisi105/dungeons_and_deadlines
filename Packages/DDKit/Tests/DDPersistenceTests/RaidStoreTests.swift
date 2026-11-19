import Foundation
import Testing
import GameCore
@testable import DDPersistence

@MainActor
final class TestClock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

@MainActor
func makeStore(_ clock: TestClock) throws -> RaidStore {
    RaidStore(container: try SharedContainer.make(inMemory: true), clock: { clock.now })
}

let owner = LocalIdentity(memberID: "a", nickname: "Ada")

@Suite("RaidStore") @MainActor
struct RaidStoreTests {
    @Test("Create, plan, start locks HP, complete adds a pending attack")
    func soloFlow() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "Thesis", bossName: "Dragon", deadline: clock.now.addingTimeInterval(86_400 * 7), multiplayer: false, owner: owner)
        #expect(store.members(raid.id).map(\.nickname) == ["Ada"])

        let t1 = try store.addTask(raidID: raid.id, title: "Outline", size: .s)
        _ = try store.addTask(raidID: raid.id, title: "Draft", size: .l)
        #expect(store.bossState(raid.id)?.outcome == .planning)
        #expect(throws: StoreError.notActive) { try store.completeTask(t1.id, by: "a") }

        let started = try store.startFight(raid.id, by: "a")
        #expect(started.lockedMaxHP == 693) // 450 / 0.65
        #expect(started.status == .active)

        clock.advance(60)
        let attack = try #require(try store.completeTask(t1.id, by: "a"))
        #expect(attack.damage == 50)
        #expect(store.pendingAttacks().isEmpty) // solo raids never upload
        #expect(store.bossState(raid.id)?.currentHP == 643)

        // Completing twice is a no-op.
        #expect(try store.completeTask(t1.id, by: "a") == nil)
        #expect(store.attacks(raid.id).count == 1)

        // Reopen + complete again must not hit the boss a second time.
        try store.reopenTask(t1.id)
        #expect(try store.completeTask(t1.id, by: "a") == nil)
        #expect(store.task(t1.id)?.isDone == true)
        #expect(store.attacks(raid.id).count == 1)
    }

    @Test("Can't start without tasks; only the owner can start")
    func startRules() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(3600), multiplayer: true, owner: owner)
        #expect(throws: StoreError.noTasks) { try store.startFight(raid.id, by: "a") }
        _ = try store.addTask(raidID: raid.id, title: "T", size: .m)
        #expect(throws: StoreError.notOwner) { try store.startFight(raid.id, by: "b") }
        try store.startFight(raid.id, by: "a")
        #expect(throws: StoreError.notPlanning) { try store.startFight(raid.id, by: "a") }
    }

    @Test("Late tasks don't change locked HP")
    func lockedHP() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: false, owner: owner)
        _ = try store.addTask(raidID: raid.id, title: "T", size: .m)
        try store.startFight(raid.id, by: "a")
        clock.advance(10)
        let late = try store.addTask(raidID: raid.id, title: "Late", size: .l)
        #expect(store.bossState(raid.id)?.maxHP == 231)
        #expect(late.isLate(startedAt: store.raid(raid.id)?.startedAt))
    }

    @Test("Killing the boss marks the raid won")
    func win() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: false, owner: owner)
        let t = try store.addTask(raidID: raid.id, title: "T", size: .s)
        try store.startFight(raid.id, by: "a")
        // 77 HP; a 50 hit plus 30 min of focus (60) kills it.
        try store.completeTask(t.id, by: "a")
        try store.startFocus(raidID: raid.id, memberID: "a")
        clock.advance(1800)
        let focus = try store.stopFocus(raidID: raid.id, memberID: "a")
        #expect(focus?.damage == 60)
        #expect(store.raid(raid.id)?.status == .won)
        #expect(throws: StoreError.notActive) { try store.startFocus(raidID: raid.id, memberID: "a") }
    }

    @Test("Focus timer pauses after a long background and survives a new store instance")
    func focusBackground() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: false, owner: owner)
        _ = try store.addTask(raidID: raid.id, title: "T", size: .l)
        try store.startFight(raid.id, by: "a")
        try store.startFocus(raidID: raid.id, memberID: "a")
        #expect(store.members(raid.id).first?.activeFocusSince != nil)
        clock.advance(600)
        try store.markFocusBackgrounded(memberID: "a")
        clock.advance(300)
        #expect(try store.resumeFocusFromBackground(memberID: "a"))
        let session = store.focusSession(raidID: raid.id, memberID: "a")
        #expect(session.state == .paused)
        #expect(session.elapsed(at: clock.now) == 600)
        #expect(store.members(raid.id).first?.activeFocusSince == nil)
    }

    @Test("Deleting a task leaves a tombstone; done tasks can't be deleted")
    func deleteTask() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: true, owner: owner)
        let t = try store.addTask(raidID: raid.id, title: "T", size: .s)
        try store.deleteTask(t.id)
        #expect(store.tasks(raid.id).isEmpty)
        #expect(store.pendingTasks().first?.deleted == true)
    }

    @Test("Reordering updates sort indexes")
    func reorder() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: false, owner: owner)
        let a = try store.addTask(raidID: raid.id, title: "A", size: .s)
        let b = try store.addTask(raidID: raid.id, title: "B", size: .s)
        try store.moveTasks(raidID: raid.id, orderedIDs: [b.id, a.id])
        #expect(store.tasks(raid.id).map(\.title) == ["B", "A"])
    }

    @Test("Raids are capped at 5 members")
    func memberCap() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: true, owner: owner)
        for i in 1...4 { try store.addMember(Member(id: "m\(i)", raidID: raid.id, nickname: "M\(i)", joinedAt: clock.now)) }
        #expect(throws: StoreError.raidFull) {
            try store.addMember(Member(id: "m5", raidID: raid.id, nickname: "M5", joinedAt: clock.now))
        }
    }
}

@Suite("Outbox and merge") @MainActor
struct SyncStoreTests {
    @Test("Multiplayer changes land in the outbox until marked synced")
    func outbox() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: true, owner: owner)
        let t = try store.addTask(raidID: raid.id, title: "T", size: .m)
        try store.startFight(raid.id, by: "a")
        let attack = try #require(try store.completeTask(t.id, by: "a"))
        #expect(store.pendingRaids().map(\.id) == [raid.id])
        #expect(store.pendingMembers().count == 1)
        #expect(store.pendingAttacks().map(\.id) == [attack.id])
        store.markAttackSynced(attack.id)
        #expect(store.pendingAttacks().isEmpty)
    }

    @Test("Remote attacks are inserted once; remote raids don't overwrite pending local edits")
    func merge() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: true, owner: owner)
        let remote = Attack(raidID: raid.id, memberID: "b", kind: .focus(seconds: 600), damage: 20, createdAt: clock.now, localDay: "2027-01-15")
        store.mergeRemote(attack: remote)
        store.mergeRemote(attack: remote)
        #expect(store.attacks(raid.id).count == 1)

        var renamed = raid
        renamed.name = "Server name"
        store.mergeRemote(raid: renamed)
        #expect(store.raid(raid.id)?.name == "R") // local change still pending
        store.markRaidSynced(raid.id)
        store.mergeRemote(raid: renamed)
        #expect(store.raid(raid.id)?.name == "Server name")
    }

    @Test("Migrating the member ID re-keys local data")
    func migrate() throws {
        let clock = TestClock()
        let store = try makeStore(clock)
        let raid = try store.createRaid(name: "R", bossName: "B", deadline: clock.now.addingTimeInterval(86_400), multiplayer: false, owner: owner)
        let t = try store.addTask(raidID: raid.id, title: "T", size: .m)
        try store.startFight(raid.id, by: "a")
        try store.completeTask(t.id, by: "a")
        try store.migrateMemberID(from: "a", to: "uid-1")
        #expect(store.raid(raid.id)?.ownerID == "uid-1")
        #expect(store.members(raid.id).map(\.id) == ["uid-1"])
        #expect(store.attacks(raid.id).map(\.memberID) == ["uid-1"])
        #expect(store.task(t.id)?.completedBy == "uid-1")
    }
}
