import Foundation
import GameCore
import DDPersistence

/// Everything a widget needs about one raid, read once from the shared store.
/// Lives here (not in the widget extension) so it can be unit tested.
public struct BossSnapshot: Sendable {
    public struct TaskInfo: Sendable, Identifiable {
        public let id: UUID
        public let title: String
        public let sizeLetter: String
        public let damage: Int

        public init(id: UUID, title: String, sizeLetter: String, damage: Int) {
            self.id = id
            self.title = title
            self.sizeLetter = sizeLetter
            self.damage = damage
        }
    }

    public let raidID: UUID
    public let raidName: String
    public let bossName: String
    public let startedAt: Date?
    public let deadline: Date
    public let state: BossState
    public let openTasks: [TaskInfo]
    public let canComplete: Bool

    public init(raidID: UUID, raidName: String, bossName: String, startedAt: Date? = nil, deadline: Date, state: BossState, openTasks: [TaskInfo], canComplete: Bool) {
        self.raidID = raidID
        self.raidName = raidName
        self.bossName = bossName
        self.startedAt = startedAt
        self.deadline = deadline
        self.state = state
        self.openTasks = openTasks
        self.canComplete = canComplete
    }

    public var raidEntity: RaidEntity { RaidEntity(id: raidID, name: raidName, bossName: bossName) }

    /// The given raid, or the current one. Nil if there's no raid.
    @MainActor
    public static func make(raidID: UUID?, at date: Date, store: RaidStore = DDStore.shared) -> BossSnapshot? {
        guard let raid = raidID.flatMap({ store.raid($0) }) ?? store.currentRaid(),
              let state = store.bossState(raid.id, at: date) else { return nil }
        // Up to 6 for the large (iPad) widget; the medium one shows the first 3.
        let open = store.tasks(raid.id).filter { !$0.isDone }.prefix(6).map {
            TaskInfo(id: $0.id, title: $0.title, sizeLetter: $0.size.rawValue.uppercased(), damage: store.config.baseDamage(for: $0.size))
        }
        return BossSnapshot(
            raidID: raid.id, raidName: raid.name, bossName: raid.bossName, startedAt: raid.startedAt,
            deadline: raid.deadline, state: state, openTasks: Array(open), canComplete: state.outcome == .ongoing
        )
    }

    /// When a widget should redraw on its own: each upcoming phase change and the deadline.
    public func refreshDates(after now: Date) -> [Date] {
        guard state.outcome == .ongoing else { return [] }
        var dates: [Date] = []
        var cursor = now
        let start = startedAt ?? now
        while let next = Phase.nextChange(start: start, deadline: deadline, after: cursor), dates.count < 4 {
            dates.append(next)
            cursor = next
        }
        if deadline > now { dates.append(deadline.addingTimeInterval(1)) }
        return dates.sorted()
    }
}
