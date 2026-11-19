import Foundation
import Testing
import GameCore
import DDPersistence
@testable import DDIntents

@Suite("Intents", .serialized) @MainActor
struct IntentsTests {
    let store: RaidStore
    let raid: Raid
    let task: RaidTask

    init() throws {
        store = RaidStore(container: try SharedContainer.make(inMemory: true))
        DDStore.use(store)
        let me = LocalIdentity.current
        raid = try store.createRaid(name: "Thesis", bossName: "Dragon", deadline: .now.addingTimeInterval(86_400), multiplayer: false, owner: me)
        task = try store.addTask(raidID: raid.id, title: "Outline", size: .m)
        LocalIdentity.currentRaidID = raid.id
    }

    @Test("Start fight, then complete a task through its intent; completing twice is a no-op")
    func completeTask() async throws {
        _ = try await StartFightIntent(raid: RaidEntity(raid)).perform()
        let entity = TaskEntity(task)
        _ = try await CompleteTaskIntent(task: entity).perform()
        _ = try await CompleteTaskIntent(task: entity).perform()
        #expect(store.attacks(raid.id).count == 1)
        #expect(store.task(task.id)?.isDone == true)
    }

    @Test("Focus intents start and stop the timer on the current raid")
    func focus() async throws {
        _ = try await StartFightIntent(raid: nil).perform()
        _ = try await StartFocusIntent(raid: nil).perform()
        #expect(GameActions.isFocusRunning())
        _ = try await PauseFocusIntent(raid: nil).perform()
        #expect(!GameActions.isFocusRunning())
        _ = try await StopFocusIntent(raid: nil).perform()
        #expect(store.focusSession(raidID: raid.id, memberID: LocalIdentity.current.memberID).state == .idle)
    }

    @Test("Task query only suggests open tasks of the current raid")
    func query() async throws {
        let suggested = try await TaskQuery().suggestedEntities()
        #expect(suggested.map(\.id) == [task.id])
        let found = try await TaskQuery().entities(matching: "out")
        #expect(found.count == 1)
    }
}

@Suite("Widget snapshot", .serialized) @MainActor
struct BossSnapshotTests {
    @Test("Snapshot carries up to 6 open tasks and refresh dates at phase changes")
    func snapshot() throws {
        let store = RaidStore(container: try SharedContainer.make(inMemory: true))
        let me = LocalIdentity(memberID: "a", nickname: "Ada")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let raid = try store.createRaid(name: "Thesis", bossName: "Dragon", deadline: start.addingTimeInterval(1000), multiplayer: false, owner: me)
        for i in 0..<5 { try store.addTask(raidID: raid.id, title: "T\(i)", size: .s) }
        let planning = try #require(BossSnapshot.make(raidID: raid.id, at: start, store: store))
        #expect(planning.openTasks.count == 5) // up to 6 for the large widget
        #expect(!planning.canComplete)
        #expect(planning.refreshDates(after: start).isEmpty)

        store.clock = { start }
        try store.startFight(raid.id, by: "a")
        let fighting = try #require(BossSnapshot.make(raidID: raid.id, at: start, store: store))
        #expect(fighting.canComplete)
        #expect(fighting.refreshDates(after: start) == [500, 750, 900, 1001].map { start.addingTimeInterval($0) })
    }

    @Test("No raid, no snapshot")
    func empty() throws {
        let store = RaidStore(container: try SharedContainer.make(inMemory: true))
        LocalIdentity.currentRaidID = nil
        #expect(BossSnapshot.make(raidID: nil, at: .now, store: store) == nil)
    }
}
