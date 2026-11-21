import Foundation
import GameCore

/// Game models ⇄ Firestore fields. Field names match firestore.rules and IMPLEMENTATION_PLAN Appendix C.
enum Mapping {
    static func raidPath(_ id: UUID) -> String { "raids/\(id.uuidString)" }

    // MARK: Raid

    static func fields(_ raid: Raid) -> FirestoreFields {
        var f: FirestoreFields = [
            "name": .string(raid.name),
            "bossName": .string(raid.bossName),
            "ownerId": .string(raid.ownerID),
            "createdAt": .date(raid.createdAt),
            "deadline": .date(raid.deadline),
            "status": .string(raid.status.rawValue),
            "startedAt": raid.startedAt.map(FirestoreValue.date) ?? .null,
            "lockedMaxHP": raid.lockedMaxHP.map(FirestoreValue.int) ?? .null,
            "phaseShift": .int(raid.phaseShift),
        ]
        if let code = raid.inviteCode { f["inviteCode"] = .string(code) }
        return f
    }

    static func raid(_ d: FirestoreDocument) -> Raid? {
        guard let id = UUID(uuidString: d.id), let deadline = d["deadline"]?.date else { return nil }
        return Raid(
            id: id, name: d["name"]?.string ?? "", bossName: d["bossName"]?.string ?? "",
            ownerID: d["ownerId"]?.string ?? "", createdAt: d["createdAt"]?.date ?? deadline,
            deadline: deadline, startedAt: d["startedAt"]?.date, lockedMaxHP: d["lockedMaxHP"]?.int,
            status: RaidStatus(rawValue: d["status"]?.string ?? "") ?? .planning,
            inviteCode: d["inviteCode"]?.string, isMultiplayer: true,
            phaseShift: d["phaseShift"]?.int ?? 0 // missing on raids from older app versions
        )
    }

    // MARK: Member

    static func fields(_ m: Member) -> FirestoreFields {
        [
            "nickname": .string(m.nickname),
            "joinedAt": .date(m.joinedAt),
            "role": m.role.map { .string($0.rawValue) } ?? .null,
            "activeFocusSince": m.activeFocusSince.map(FirestoreValue.date) ?? .null,
        ]
    }

    static func member(_ d: FirestoreDocument, raidID: UUID) -> Member? {
        Member(
            id: d.id, raidID: raidID, nickname: d["nickname"]?.string ?? "?",
            role: d["role"]?.string.flatMap(Role.init(rawValue:)),
            joinedAt: d["joinedAt"]?.date ?? .now, activeFocusSince: d["activeFocusSince"]?.date
        )
    }

    // MARK: Task

    static func fields(_ t: RaidTask, deleted: Bool) -> FirestoreFields {
        [
            "title": .string(t.title),
            "size": .string(t.size.rawValue),
            "damage": t.damage.map(FirestoreValue.int) ?? .null,
            "assigneeId": t.assigneeID.map(FirestoreValue.string) ?? .null,
            "createdAt": .date(t.createdAt),
            "completedAt": t.completedAt.map(FirestoreValue.date) ?? .null,
            "completedBy": t.completedBy.map(FirestoreValue.string) ?? .null,
            "sortIndex": .int(t.sortIndex),
            "deleted": .bool(deleted),
        ]
    }

    static func task(_ d: FirestoreDocument, raidID: UUID) -> (task: RaidTask, deleted: Bool)? {
        guard let id = UUID(uuidString: d.id) else { return nil }
        let task = RaidTask(
            id: id, raidID: raidID, title: d["title"]?.string ?? "",
            size: TaskSize(rawValue: d["size"]?.string ?? "") ?? .m,
            damage: d["damage"]?.int.flatMap { $0 > 0 ? $0 : nil },
            assigneeID: d["assigneeId"]?.string, createdAt: d["createdAt"]?.date ?? .now,
            completedAt: d["completedAt"]?.date, completedBy: d["completedBy"]?.string,
            sortIndex: d["sortIndex"]?.int ?? 0
        )
        return (task, d["deleted"]?.bool ?? false)
    }

    // MARK: Attack

    static func fields(_ a: Attack) -> FirestoreFields {
        var f: FirestoreFields = [
            "memberId": .string(a.memberID),
            "damage": .int(a.damage),
            "createdAt": .date(a.createdAt),
            "localDay": .string(a.localDay),
        ]
        switch a.kind {
        case .task(let taskID):
            f["kind"] = .string("task")
            f["taskId"] = .string(taskID.uuidString)
        case .focus(let seconds):
            f["kind"] = .string("focus")
            f["durationSeconds"] = .int(seconds)
        }
        return f
    }

    static func attack(_ d: FirestoreDocument, raidID: UUID) -> Attack? {
        guard let id = UUID(uuidString: d.id), let memberID = d["memberId"]?.string, let damage = d["damage"]?.int else { return nil }
        let kind: AttackKind
        if d["kind"]?.string == "task", let taskID = d["taskId"]?.string.flatMap(UUID.init(uuidString:)) {
            kind = .task(taskID)
        } else {
            kind = .focus(seconds: d["durationSeconds"]?.int ?? 0)
        }
        let created = d["createdAt"]?.date ?? .now
        return Attack(
            id: id, raidID: raidID, memberID: memberID, kind: kind, damage: damage,
            createdAt: created, localDay: d["localDay"]?.string ?? LocalDay.key(for: created)
        )
    }
}
