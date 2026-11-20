import Foundation
import SwiftData
import GameCore

public enum StoreError: LocalizedError, Equatable {
    case raidNotFound
    case taskNotFound
    case notPlanning
    case notActive
    case noTasks
    case notOwner
    case raidFull
    case notFinished
    case noOpenTasks
    case deadlineInPast

    public var errorDescription: String? {
        switch self {
        case .raidNotFound: String(localized: "This raid no longer exists.")
        case .taskNotFound: String(localized: "This task no longer exists.")
        case .notPlanning: String(localized: "The fight has already started.")
        case .notActive: String(localized: "The fight isn't running.")
        case .noTasks: String(localized: "Add at least one task before starting the fight.")
        case .notOwner: String(localized: "Only the raid leader can do this.")
        case .raidFull: String(localized: "This raid already has 5 members.")
        case .notFinished: String(localized: "The fight is still on.")
        case .noOpenTasks: String(localized: "Add a follow-up task first.")
        case .deadlineInPast: String(localized: "Pick a deadline in the future.")
        }
    }
}

/// All reads and writes of game data. Runs on the main actor so SwiftUI `@Query`
/// views see every change immediately (the store and the views share `mainContext`).
@MainActor
public final class RaidStore {
    public let container: ModelContainer
    public var context: ModelContext { container.mainContext }
    public var calculator: DamageCalculator
    public var clock: @MainActor () -> Date

    public init(
        container: ModelContainer, config: DamageConfig = .standard,
        calendar: Calendar = .current, clock: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.container = container
        self.calculator = DamageCalculator(config: config, calendar: calendar)
        self.clock = clock
    }

    public var config: DamageConfig { calculator.config }

    // MARK: - Reads

    public func raidRecord(_ id: UUID) -> RaidRecord? {
        try? context.fetch(FetchDescriptor<RaidRecord>(predicate: #Predicate { $0.id == id })).first
    }

    public func raid(_ id: UUID) -> Raid? { raidRecord(id)?.model }

    public func raids() -> [Raid] {
        let descriptor = FetchDescriptor<RaidRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).map(\.model)
    }

    /// The selected raid, or the newest unfinished one.
    public func currentRaid() -> Raid? {
        if let id = LocalIdentity.currentRaidID, let raid = raid(id) { return raid }
        let all = raids()
        return all.first { $0.status == .active || $0.status == .planning } ?? all.first
    }

    public func members(_ raidID: UUID) -> [Member] {
        let d = FetchDescriptor<MemberRecord>(predicate: #Predicate { $0.raidID == raidID }, sortBy: [SortDescriptor(\.joinedAt)])
        return ((try? context.fetch(d)) ?? []).map(\.model)
    }

    func memberRecord(raidID: UUID, memberID: String) -> MemberRecord? {
        let key = MemberRecord.key(raidID: raidID, memberID: memberID)
        return try? context.fetch(FetchDescriptor<MemberRecord>(predicate: #Predicate { $0.key == key })).first
    }

    public func tasks(_ raidID: UUID) -> [RaidTask] {
        let d = FetchDescriptor<TaskRecord>(
            predicate: #Predicate { $0.raidID == raidID && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.createdAt)]
        )
        return ((try? context.fetch(d)) ?? []).map(\.model)
    }

    func taskRecord(_ id: UUID) -> TaskRecord? {
        try? context.fetch(FetchDescriptor<TaskRecord>(predicate: #Predicate { $0.id == id })).first
    }

    public func task(_ id: UUID) -> RaidTask? {
        guard let r = taskRecord(id), r.deletedAt == nil else { return nil }
        return r.model
    }

    public func attacks(_ raidID: UUID) -> [Attack] {
        let d = FetchDescriptor<AttackRecord>(predicate: #Predicate { $0.raidID == raidID }, sortBy: [SortDescriptor(\.createdAt)])
        return ((try? context.fetch(d)) ?? []).map(\.model)
    }

    public func bossState(_ raidID: UUID, at now: Date? = nil) -> BossState? {
        guard let raid = raid(raidID) else { return nil }
        return BossEngine.state(raid: raid, tasks: tasks(raidID), attacks: attacks(raidID), now: now ?? clock(), config: config)
    }

    public func report(_ raidID: UUID) -> RaidReport? {
        guard let raid = raid(raidID) else { return nil }
        return Titles.report(
            raid: raid, members: members(raidID), tasks: tasks(raidID), attacks: attacks(raidID),
            now: clock(), config: config, calendar: calculator.calendar
        )
    }

    func context(for memberID: String, raid: Raid) -> DamageCalculator.Context {
        DamageCalculator.Context(
            memberID: memberID, attacks: attacks(raid.id), memberCount: max(1, members(raid.id).count),
            lockedMaxHP: raid.lockedMaxHP, now: clock()
        )
    }

    // MARK: - Raid lifecycle

    @discardableResult
    public func createRaid(
        name: String, bossName: String, deadline: Date, multiplayer: Bool,
        owner: LocalIdentity, role: Role? = nil
    ) throws -> Raid {
        let now = clock()
        let raid = Raid(
            name: name, bossName: bossName, ownerID: owner.memberID, createdAt: now,
            deadline: deadline, isMultiplayer: multiplayer
        )
        context.insert(RaidRecord(raid, syncState: .pending))
        context.insert(MemberRecord(Member(id: owner.memberID, raidID: raid.id, nickname: owner.nickname, role: role, joinedAt: now), syncState: .pending))
        try context.save()
        LocalIdentity.currentRaidID = raid.id
        return raid
    }

    public func updateRaid(_ raid: Raid) throws {
        guard let record = raidRecord(raid.id) else { throw StoreError.raidNotFound }
        record.update(from: raid, syncState: .pending)
        try context.save()
    }

    /// Sets the leader's phase shift (clamped to `Phase.shiftRange`): whole steps added to the
    /// time-based phase. Only the leader, only while the fight is on. Marked pending so a
    /// multiplayer raid uploads it on the next flush.
    public func setPhaseShift(_ shift: Int, raidID: UUID, by memberID: String) throws {
        guard let record = raidRecord(raidID) else { throw StoreError.raidNotFound }
        var raid = record.model
        guard raid.ownerID == memberID else { throw StoreError.notOwner }
        guard raid.status == .active, bossState(raidID)?.outcome == .ongoing else { throw StoreError.notActive }
        raid.phaseShift = Phase.clampShift(shift)
        record.update(from: raid, syncState: .pending)
        try context.save()
    }

    /// Locks max HP from the planned tasks and starts the fight.
    @discardableResult
    public func startFight(_ raidID: UUID, by memberID: String) throws -> Raid {
        guard let record = raidRecord(raidID) else { throw StoreError.raidNotFound }
        var raid = record.model
        guard raid.ownerID == memberID else { throw StoreError.notOwner }
        guard raid.status == .planning else { throw StoreError.notPlanning }
        let planned = tasks(raidID)
        let hp = BossEngine.lockHP(tasks: planned, config: config)
        guard hp > 0 else { throw StoreError.noTasks }
        raid.status = .active
        raid.startedAt = clock()
        raid.lockedMaxHP = hp
        record.update(from: raid, syncState: .pending)
        try context.save()
        return raid
    }

    /// Brings a finished boss back for follow-up tasks: it returns with health from the
    /// open (follow-up) tasks, on top of whatever it had left, and a new deadline.
    /// Earlier hits stay in the log; phases restart from now.
    @discardableResult
    public func resumeFight(_ raidID: UUID, by memberID: String, deadline: Date) throws -> Raid {
        guard let record = raidRecord(raidID) else { throw StoreError.raidNotFound }
        var raid = record.model
        guard raid.ownerID == memberID else { throw StoreError.notOwner }
        guard raid.status == .won || raid.status == .lost else { throw StoreError.notFinished }
        let now = clock()
        guard deadline > now else { throw StoreError.deadlineInPast }
        let followUps = tasks(raidID).filter { !$0.isDone }
        let extra = BossEngine.lockHP(tasks: followUps, config: config)
        guard extra > 0 else { throw StoreError.noOpenTasks }
        let dealt = attacks(raidID).reduce(0) { $0 + $1.damage }
        raid.lockedMaxHP = max(raid.lockedMaxHP ?? 0, dealt) + extra
        raid.status = .active
        raid.startedAt = now
        raid.deadline = deadline
        // Phases restart from now, following the new deadline.
        raid.phaseShift = 0
        record.update(from: raid, syncState: .pending)
        try context.save()
        return raid
    }

    /// Moves an active raid to won/lost when its state says so. Returns the new status if it changed.
    @discardableResult
    public func settleOutcome(_ raidID: UUID) throws -> RaidStatus? {
        guard let record = raidRecord(raidID), record.status == .active, let state = bossState(raidID) else { return nil }
        let newStatus: RaidStatus
        switch state.outcome {
        case .won: newStatus = .won
        case .lost: newStatus = .lost
        default: return nil
        }
        var raid = record.model
        raid.status = newStatus
        record.update(from: raid, syncState: .pending)
        try context.save()
        return newStatus
    }

    public func deleteRaidLocally(_ raidID: UUID) throws {
        try context.delete(model: RaidRecord.self, where: #Predicate { $0.id == raidID })
        try context.delete(model: MemberRecord.self, where: #Predicate { $0.raidID == raidID })
        try context.delete(model: TaskRecord.self, where: #Predicate { $0.raidID == raidID })
        try context.delete(model: AttackRecord.self, where: #Predicate { $0.raidID == raidID })
        try context.delete(model: FocusSessionRecord.self, where: #Predicate { $0.raidID == raidID })
        try context.save()
        if LocalIdentity.currentRaidID == raidID { LocalIdentity.currentRaidID = nil }
    }

    // MARK: - Members

    public func addMember(_ member: Member) throws {
        if let existing = memberRecord(raidID: member.raidID, memberID: member.id) {
            existing.update(from: member, syncState: .pending)
        } else {
            guard members(member.raidID).count < config.maxMembers else { throw StoreError.raidFull }
            context.insert(MemberRecord(member, syncState: .pending))
        }
        try context.save()
    }

    public func updateMember(raidID: UUID, memberID: String, _ change: (inout Member) -> Void) throws {
        guard let record = memberRecord(raidID: raidID, memberID: memberID) else { return }
        var member = record.model
        change(&member)
        record.update(from: member, syncState: .pending)
        try context.save()
    }

    /// Renames this member in every raid (e.g. after changing the nickname).
    public func renameMember(_ memberID: String, to nickname: String) throws {
        let d = FetchDescriptor<MemberRecord>(predicate: #Predicate { $0.memberID == memberID })
        for record in (try? context.fetch(d)) ?? [] {
            var m = record.model
            m.nickname = nickname
            record.update(from: m, syncState: .pending)
        }
        try context.save()
    }

    /// Re-keys all local data from one member ID to another (local ID → Firebase user ID).
    public func migrateMemberID(from old: String, to new: String) throws {
        guard old != new else { return }
        for record in (try? context.fetch(FetchDescriptor<MemberRecord>(predicate: #Predicate { $0.memberID == old }))) ?? [] {
            record.memberID = new
            record.key = MemberRecord.key(raidID: record.raidID, memberID: new)
            record.syncStateRaw = SyncState.pending.rawValue
        }
        for record in (try? context.fetch(FetchDescriptor<RaidRecord>(predicate: #Predicate { $0.ownerID == old }))) ?? [] {
            record.ownerID = new
            record.syncStateRaw = SyncState.pending.rawValue
        }
        for record in (try? context.fetch(FetchDescriptor<AttackRecord>(predicate: #Predicate { $0.memberID == old }))) ?? [] {
            record.memberID = new
        }
        for record in (try? context.fetch(FetchDescriptor<TaskRecord>())) ?? [] {
            if record.completedBy == old { record.completedBy = new }
            if record.assigneeID == old { record.assigneeID = new }
        }
        for record in (try? context.fetch(FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.memberID == old }))) ?? [] {
            record.memberID = new
            record.key = MemberRecord.key(raidID: record.raidID, memberID: new)
        }
        try context.save()
    }

    // MARK: - Tasks

    @discardableResult
    public func addTask(raidID: UUID, title: String, size: TaskSize, assigneeID: String? = nil) throws -> RaidTask {
        guard raid(raidID) != nil else { throw StoreError.raidNotFound }
        // Any status: finished raids collect follow-up tasks before a resumed fight.
        let next = (tasks(raidID).map(\.sortIndex).max() ?? -1) + 1
        let task = RaidTask(raidID: raidID, title: title, size: size, assigneeID: assigneeID, createdAt: clock(), sortIndex: next)
        context.insert(TaskRecord(task, syncState: .pending))
        try context.save()
        return task
    }

    public func updateTask(_ task: RaidTask) throws {
        guard let record = taskRecord(task.id) else { throw StoreError.taskNotFound }
        record.update(from: task, syncState: .pending)
        try context.save()
    }

    public func deleteTask(_ id: UUID) throws {
        guard let record = taskRecord(id) else { throw StoreError.taskNotFound }
        guard !record.isDone else { return }
        record.deletedAt = clock()
        record.syncStateRaw = SyncState.pending.rawValue
        record.updatedAt = .now
        try context.save()
    }

    public func moveTasks(raidID: UUID, orderedIDs: [UUID]) throws {
        for (index, id) in orderedIDs.enumerated() {
            guard let record = taskRecord(id), record.sortIndex != index else { continue }
            record.sortIndex = index
            record.syncStateRaw = SyncState.pending.rawValue
            record.updatedAt = .now
        }
        try context.save()
    }

    /// Completes a task and records its attack. Completing an already-done task does nothing.
    @discardableResult
    public func completeTask(_ taskID: UUID, by memberID: String) throws -> Attack? {
        guard let record = taskRecord(taskID), record.deletedAt == nil else { throw StoreError.taskNotFound }
        guard !record.isDone else { return nil }
        guard let raid = raid(record.raidID) else { throw StoreError.raidNotFound }
        guard raid.status == .active, bossState(raid.id)?.outcome == .ongoing else { throw StoreError.notActive }

        // A task hits the boss once. Reopening and completing it again doesn't hit twice.
        let alreadyHit = attacks(raid.id).contains { $0.kind == .task(taskID) }
        let attack = alreadyHit ? nil : calculator.taskAttack(raidID: raid.id, taskID: taskID, size: record.size, context: context(for: memberID, raid: raid))
        var task = record.model
        task.completedAt = clock()
        task.completedBy = memberID
        record.update(from: task, syncState: .pending)
        if let attack { context.insert(AttackRecord(attack, syncState: .pending)) }
        try context.save()
        try settleOutcome(raid.id)
        return attack
    }

    /// Re-opens a task completed by mistake. Its attack stays in the log (attacks are add-only).
    public func reopenTask(_ taskID: UUID) throws {
        guard let record = taskRecord(taskID) else { throw StoreError.taskNotFound }
        var task = record.model
        task.completedAt = nil
        task.completedBy = nil
        record.update(from: task, syncState: .pending)
        try context.save()
    }

    // MARK: - Focus

    func focusRecord(raidID: UUID, memberID: String) -> FocusSessionRecord? {
        let key = MemberRecord.key(raidID: raidID, memberID: memberID)
        return try? context.fetch(FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.key == key })).first
    }

    public func focusSession(raidID: UUID, memberID: String) -> FocusSession {
        focusRecord(raidID: raidID, memberID: memberID)?.model ?? FocusSession(raidID: raidID, memberID: memberID)
    }

    /// Any running or paused session of this member, in any raid.
    public func activeFocusSession(memberID: String) -> FocusSession? {
        let idle = FocusTimerState.idle.rawValue
        let d = FetchDescriptor<FocusSessionRecord>(predicate: #Predicate { $0.memberID == memberID && $0.stateRaw != idle })
        return (try? context.fetch(d))?.first?.model
    }

    func save(_ session: FocusSession) throws {
        if let record = focusRecord(raidID: session.raidID, memberID: session.memberID) {
            record.update(from: session)
        } else {
            context.insert(FocusSessionRecord(session))
        }
        try context.save()
    }

    @discardableResult
    public func startFocus(raidID: UUID, memberID: String) throws -> FocusSession {
        guard let raid = raid(raidID) else { throw StoreError.raidNotFound }
        guard raid.status == .active else { throw StoreError.notActive }
        var session = focusSession(raidID: raidID, memberID: memberID)
        session.start(at: clock())
        try save(session)
        try updateMember(raidID: raidID, memberID: memberID) { $0.activeFocusSince = session.startedAt }
        return session
    }

    @discardableResult
    public func pauseFocus(raidID: UUID, memberID: String) throws -> FocusSession {
        var session = focusSession(raidID: raidID, memberID: memberID)
        session.pause(at: clock())
        try save(session)
        try updateMember(raidID: raidID, memberID: memberID) { $0.activeFocusSince = nil }
        return session
    }

    /// Stops the timer and records the focus attack (after the daily cap). Returns nil if nothing counted.
    @discardableResult
    public func stopFocus(raidID: UUID, memberID: String) throws -> Attack? {
        var session = focusSession(raidID: raidID, memberID: memberID)
        let seconds = session.stop(at: clock())
        try save(session)
        try updateMember(raidID: raidID, memberID: memberID) { $0.activeFocusSince = nil }
        guard let raid = raid(raidID), raid.status == .active, bossState(raidID)?.outcome == .ongoing else { return nil }
        guard let attack = calculator.focusAttack(raidID: raidID, seconds: seconds, context: context(for: memberID, raid: raid)) else { return nil }
        context.insert(AttackRecord(attack, syncState: .pending))
        try context.save()
        try settleOutcome(raidID)
        return attack
    }

    // MARK: - Recording attacks directly (debug teammates)

    public func insertAttack(_ attack: Attack, syncState: SyncState = .pending) throws {
        context.insert(AttackRecord(attack, syncState: syncState))
        try context.save()
        try settleOutcome(attack.raidID)
    }
}
