import Foundation
import SwiftData
import GameCore

/// Upload state for the local-first store. `pending` rows are the outbox.
public enum SyncState: String, Codable, Sendable {
    case pending, synced
}

@Model
public final class RaidRecord {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var bossName: String
    public var ownerID: String
    public var createdAt: Date
    public var deadline: Date
    public var startedAt: Date?
    public var lockedMaxHP: Int?
    public var statusRaw: String
    public var inviteCode: String?
    public var isMultiplayer: Bool
    public var syncStateRaw: String
    public var updatedAt: Date

    public init(_ raid: Raid, syncState: SyncState) {
        id = raid.id
        name = raid.name
        bossName = raid.bossName
        ownerID = raid.ownerID
        createdAt = raid.createdAt
        deadline = raid.deadline
        startedAt = raid.startedAt
        lockedMaxHP = raid.lockedMaxHP
        statusRaw = raid.status.rawValue
        inviteCode = raid.inviteCode
        isMultiplayer = raid.isMultiplayer
        syncStateRaw = syncState.rawValue
        updatedAt = .now
    }

    public var status: RaidStatus { RaidStatus(rawValue: statusRaw) ?? .planning }
    public var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .pending }

    public var model: Raid {
        Raid(
            id: id, name: name, bossName: bossName, ownerID: ownerID, createdAt: createdAt,
            deadline: deadline, startedAt: startedAt, lockedMaxHP: lockedMaxHP, status: status,
            inviteCode: inviteCode, isMultiplayer: isMultiplayer
        )
    }

    public func update(from raid: Raid, syncState: SyncState) {
        name = raid.name
        bossName = raid.bossName
        ownerID = raid.ownerID
        deadline = raid.deadline
        startedAt = raid.startedAt
        lockedMaxHP = raid.lockedMaxHP
        statusRaw = raid.status.rawValue
        inviteCode = raid.inviteCode
        isMultiplayer = raid.isMultiplayer
        syncStateRaw = syncState.rawValue
        updatedAt = .now
    }
}

@Model
public final class MemberRecord {
    /// `raidID|memberID`, since one person can be in several raids.
    @Attribute(.unique) public var key: String
    public var memberID: String
    public var raidID: UUID
    public var nickname: String
    public var roleRaw: String?
    public var joinedAt: Date
    public var activeFocusSince: Date?
    public var syncStateRaw: String

    public static func key(raidID: UUID, memberID: String) -> String { "\(raidID.uuidString)|\(memberID)" }

    public init(_ member: Member, syncState: SyncState) {
        key = Self.key(raidID: member.raidID, memberID: member.id)
        memberID = member.id
        raidID = member.raidID
        nickname = member.nickname
        roleRaw = member.role?.rawValue
        joinedAt = member.joinedAt
        activeFocusSince = member.activeFocusSince
        syncStateRaw = syncState.rawValue
    }

    public var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .pending }

    public var model: Member {
        Member(
            id: memberID, raidID: raidID, nickname: nickname, role: roleRaw.flatMap(Role.init(rawValue:)),
            joinedAt: joinedAt, activeFocusSince: activeFocusSince
        )
    }

    public func update(from member: Member, syncState: SyncState) {
        nickname = member.nickname
        roleRaw = member.role?.rawValue
        activeFocusSince = member.activeFocusSince
        syncStateRaw = syncState.rawValue
    }
}

@Model
public final class TaskRecord {
    @Attribute(.unique) public var id: UUID
    public var raidID: UUID
    public var title: String
    public var sizeRaw: String
    public var assigneeID: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var completedBy: String?
    public var sortIndex: Int
    /// Tombstone so deletions sync to teammates.
    public var deletedAt: Date?
    public var syncStateRaw: String
    public var updatedAt: Date

    public init(_ task: RaidTask, syncState: SyncState) {
        id = task.id
        raidID = task.raidID
        title = task.title
        sizeRaw = task.size.rawValue
        assigneeID = task.assigneeID
        createdAt = task.createdAt
        completedAt = task.completedAt
        completedBy = task.completedBy
        sortIndex = task.sortIndex
        deletedAt = nil
        syncStateRaw = syncState.rawValue
        updatedAt = .now
    }

    public var size: TaskSize { TaskSize(rawValue: sizeRaw) ?? .m }
    public var isDone: Bool { completedAt != nil }
    public var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .pending }

    public var model: RaidTask {
        RaidTask(
            id: id, raidID: raidID, title: title, size: size, assigneeID: assigneeID,
            createdAt: createdAt, completedAt: completedAt, completedBy: completedBy, sortIndex: sortIndex
        )
    }

    public func update(from task: RaidTask, syncState: SyncState) {
        title = task.title
        sizeRaw = task.size.rawValue
        assigneeID = task.assigneeID
        completedAt = task.completedAt
        completedBy = task.completedBy
        sortIndex = task.sortIndex
        syncStateRaw = syncState.rawValue
        updatedAt = .now
    }
}

@Model
public final class AttackRecord {
    @Attribute(.unique) public var id: UUID
    public var raidID: UUID
    public var memberID: String
    public var kindRaw: String
    public var taskID: UUID?
    public var durationSeconds: Int?
    public var damage: Int
    public var createdAt: Date
    public var localDay: String
    public var syncStateRaw: String

    public init(_ attack: Attack, syncState: SyncState) {
        id = attack.id
        raidID = attack.raidID
        memberID = attack.memberID
        switch attack.kind {
        case .task(let taskID):
            kindRaw = "task"
            self.taskID = taskID
            durationSeconds = nil
        case .focus(let seconds):
            kindRaw = "focus"
            taskID = nil
            durationSeconds = seconds
        }
        damage = attack.damage
        createdAt = attack.createdAt
        localDay = attack.localDay
        syncStateRaw = syncState.rawValue
    }

    public var syncState: SyncState { SyncState(rawValue: syncStateRaw) ?? .pending }

    public var kind: AttackKind {
        if kindRaw == "task", let taskID { return .task(taskID) }
        return .focus(seconds: durationSeconds ?? 0)
    }

    public var model: Attack {
        Attack(id: id, raidID: raidID, memberID: memberID, kind: kind, damage: damage, createdAt: createdAt, localDay: localDay)
    }
}

@Model
public final class FocusSessionRecord {
    /// `raidID|memberID`: one timer per member per raid.
    @Attribute(.unique) public var key: String
    public var id: UUID
    public var raidID: UUID
    public var memberID: String
    public var stateRaw: String
    public var startedAt: Date?
    public var accumulatedSeconds: Double
    public var backgroundedAt: Date?

    public init(_ session: FocusSession) {
        key = MemberRecord.key(raidID: session.raidID, memberID: session.memberID)
        id = session.id
        raidID = session.raidID
        memberID = session.memberID
        stateRaw = session.state.rawValue
        startedAt = session.startedAt
        accumulatedSeconds = session.accumulatedSeconds
        backgroundedAt = session.backgroundedAt
    }

    public var model: FocusSession {
        FocusSession(
            id: id, raidID: raidID, memberID: memberID, state: FocusTimerState(rawValue: stateRaw) ?? .idle,
            startedAt: startedAt, accumulatedSeconds: accumulatedSeconds, backgroundedAt: backgroundedAt
        )
    }

    public func update(from session: FocusSession) {
        stateRaw = session.state.rawValue
        startedAt = session.startedAt
        accumulatedSeconds = session.accumulatedSeconds
        backgroundedAt = session.backgroundedAt
    }
}
