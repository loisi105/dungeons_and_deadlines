import AppIntents
import Foundation
import GameCore
import DDPersistence

/// A raid as Siri, Shortcuts, Spotlight and widgets see it.
public struct RaidEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Raid"
    public static let defaultQuery = RaidQuery()

    public var id: UUID
    public var name: String
    public var bossName: String

    public init(id: UUID, name: String, bossName: String) {
        self.id = id
        self.name = name
        self.bossName = bossName
    }

    public init(_ raid: Raid) {
        self.init(id: raid.id, name: raid.name, bossName: raid.bossName)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Boss: \(bossName)", image: .init(systemName: "flame.fill"))
    }
}

public struct RaidQuery: EntityQuery, EnumerableEntityQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [RaidEntity] {
        await MainActor.run {
            identifiers.compactMap { DDStore.shared.raid($0) }.map(RaidEntity.init)
        }
    }

    public func allEntities() async throws -> [RaidEntity] {
        await MainActor.run { DDStore.shared.raids().map(RaidEntity.init) }
    }

    public func suggestedEntities() async throws -> [RaidEntity] {
        await MainActor.run {
            DDStore.shared.raids().filter { $0.status == .active || $0.status == .planning }.map(RaidEntity.init)
        }
    }

    public func defaultResult() async -> RaidEntity? {
        await MainActor.run { DDStore.shared.currentRaid().map(RaidEntity.init) }
    }
}

/// An open task, so "Complete task" can be run by voice or from a widget button.
public struct TaskEntity: AppEntity, Sendable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    public static let defaultQuery = TaskQuery()

    public var id: UUID
    public var title: String
    public var sizeLetter: String
    public var raidName: String

    public init(id: UUID, title: String, sizeLetter: String, raidName: String) {
        self.id = id
        self.title = title
        self.sizeLetter = sizeLetter
        self.raidName = raidName
    }

    @MainActor
    public init(_ task: RaidTask) {
        self.init(
            id: task.id, title: task.title, sizeLetter: task.size.rawValue.uppercased(),
            raidName: DDStore.shared.raid(task.raidID)?.name ?? ""
        )
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(sizeLetter) · \(raidName)")
    }
}

public struct TaskQuery: EntityQuery, EntityStringQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        await MainActor.run {
            identifiers.compactMap { DDStore.shared.task($0) }.map { TaskEntity($0) }
        }
    }

    public func entities(matching string: String) async throws -> [TaskEntity] {
        await MainActor.run {
            openTasks().filter { $0.title.localizedCaseInsensitiveContains(string) }.map { TaskEntity($0) }
        }
    }

    public func suggestedEntities() async throws -> [TaskEntity] {
        await MainActor.run { openTasks().map { TaskEntity($0) } }
    }

    @MainActor
    func openTasks() -> [RaidTask] {
        guard let raid = DDStore.shared.currentRaid() else { return [] }
        return DDStore.shared.tasks(raid.id).filter { !$0.isDone }
    }
}
