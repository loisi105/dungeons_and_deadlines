import Foundation
import SwiftData
import GameCore

/// Outbox and remote-merge API used by the Firebase sync engine (app target only).
extension RaidStore {
    // MARK: Outbox

    public func pendingRaids() -> [Raid] {
        let p = SyncState.pending.rawValue
        return ((try? context.fetch(FetchDescriptor<RaidRecord>(predicate: #Predicate { $0.syncStateRaw == p && $0.isMultiplayer }))) ?? []).map(\.model)
    }

    public func pendingMembers() -> [Member] {
        let p = SyncState.pending.rawValue
        let records = (try? context.fetch(FetchDescriptor<MemberRecord>(predicate: #Predicate { $0.syncStateRaw == p }))) ?? []
        return records.map(\.model).filter { raid($0.raidID)?.isMultiplayer == true }
    }

    /// Pending tasks, including deletions (`deleted == true`).
    public func pendingTasks() -> [(task: RaidTask, deleted: Bool)] {
        let p = SyncState.pending.rawValue
        let records = (try? context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.syncStateRaw == p }))) ?? []
        return records.filter { raid($0.raidID)?.isMultiplayer == true }.map { ($0.model, $0.deletedAt != nil) }
    }

    public func pendingAttacks() -> [Attack] {
        let p = SyncState.pending.rawValue
        let records = (try? context.fetch(FetchDescriptor<AttackRecord>(predicate: #Predicate { $0.syncStateRaw == p }, sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        return records.map(\.model).filter { raid($0.raidID)?.isMultiplayer == true }
    }

    public func markRaidSynced(_ id: UUID) {
        raidRecord(id)?.syncStateRaw = SyncState.synced.rawValue
        try? context.save()
    }

    public func markMemberSynced(raidID: UUID, memberID: String) {
        memberRecord(raidID: raidID, memberID: memberID)?.syncStateRaw = SyncState.synced.rawValue
        try? context.save()
    }

    public func markTaskSynced(_ id: UUID) {
        taskRecord(id)?.syncStateRaw = SyncState.synced.rawValue
        try? context.save()
    }

    public func markAttackSynced(_ id: UUID) {
        let record = try? context.fetch(FetchDescriptor<AttackRecord>(predicate: #Predicate { $0.id == id })).first
        record?.syncStateRaw = SyncState.synced.rawValue
        try? context.save()
    }

    // MARK: Remote merge

    /// Applies a raid from the server unless there's an unsent local change.
    public func mergeRemote(raid: Raid) {
        if let record = raidRecord(raid.id) {
            guard record.syncState == .synced else { return }
            record.update(from: raid, syncState: .synced)
        } else {
            context.insert(RaidRecord(raid, syncState: .synced))
        }
        try? context.save()
    }

    public func mergeRemote(member: Member) {
        if let record = memberRecord(raidID: member.raidID, memberID: member.id) {
            guard record.syncState == .synced else { return }
            record.update(from: member, syncState: .synced)
        } else {
            context.insert(MemberRecord(member, syncState: .synced))
        }
        try? context.save()
    }

    public func removeRemoteMember(raidID: UUID, memberID: String) {
        if let record = memberRecord(raidID: raidID, memberID: memberID) {
            context.delete(record)
            try? context.save()
        }
    }

    public func mergeRemote(task: RaidTask, deleted: Bool) {
        if let record = taskRecord(task.id) {
            guard record.syncState == .synced else { return }
            record.update(from: task, syncState: .synced)
            record.deletedAt = deleted ? (record.deletedAt ?? clock()) : nil
        } else {
            let record = TaskRecord(task, syncState: .synced)
            record.deletedAt = deleted ? clock() : nil
            context.insert(record)
        }
        try? context.save()
    }

    /// Attacks are immutable, so merging is just "insert if new".
    public func mergeRemote(attack: Attack) {
        let id = attack.id
        let exists = ((try? context.fetchCount(FetchDescriptor<AttackRecord>(predicate: #Predicate { $0.id == id }))) ?? 0) > 0
        guard !exists else { return }
        context.insert(AttackRecord(attack, syncState: .synced))
        try? context.save()
    }
}
