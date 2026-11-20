import Foundation
import GameCore
import DDPersistence

/// Invite codes: 6 characters without 0/O or 1/I, so they're easy to read aloud.
public enum InviteCode {
    public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    public static func generate(length: Int = 6) -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    public static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { alphabet.contains($0) }
    }
}

/// Moves raids between the local store and Firestore.
///
/// - Upload: the store's outbox (`syncState == .pending`), one atomic write per item.
///   Attacks are create-only, so a retry of an attack that already landed counts as done.
/// - Download: polling. Each poll reads the raid document plus only the members, tasks
///   and attacks changed since the last poll (server timestamps `updatedAt` / `serverCreatedAt`).
@MainActor
public final class RaidSync {
    public enum SyncError: LocalizedError, Equatable {
        case codeNotFound
        case raidFullOrClosed
        case couldNotCreateCode

        public var errorDescription: String? {
            switch self {
            case .codeNotFound: String(localized: "No raid uses this code. Check it with the raid leader.")
            case .raidFullOrClosed: String(localized: "This raid is full (5 members) or has already ended.")
            case .couldNotCreateCode: String(localized: "Couldn't create an invite code. Try again.")
            }
        }
    }

    struct Cursors {
        var members: Date?
        var tasks: Date?
        var attacks: Date?
    }

    public let store: RaidStore
    public let uid: String
    let transport: any FirestoreTransport
    private var cursors: [UUID: Cursors] = [:]

    public init(store: RaidStore, transport: any FirestoreTransport, uid: String) {
        self.store = store
        self.transport = transport
        self.uid = uid
    }

    // MARK: Create and join

    /// Publishes a new multiplayer raid (still in planning) and gives it an invite code.
    @discardableResult
    public func publish(_ raid: Raid, code makeCode: () -> String = { InviteCode.generate() }) async throws -> Raid {
        for _ in 0..<5 {
            var published = raid
            published.inviteCode = makeCode()
            var fields = Mapping.fields(published)
            fields["memberIDs"] = .strings([uid])
            fields["status"] = .string(RaidStatus.planning.rawValue)
            do {
                try await transport.commit([
                    FirestoreWrite(path: Mapping.raidPath(raid.id), kind: .set(fields, mask: nil), mustNotExist: true),
                    FirestoreWrite(path: "inviteCodes/\(published.inviteCode!)", kind: .set(["raidId": .string(raid.id.uuidString)], mask: nil), mustNotExist: true),
                ])
            } catch let error as FirebaseError where error.isAlreadyExists {
                continue // code taken; try another
            }
            try store.updateRaid(published)
            store.markRaidSynced(raid.id)
            await flush()
            return published
        }
        throw SyncError.couldNotCreateCode
    }

    /// Joins a raid by invite code and pulls it into the local store. Returns the raid ID.
    @discardableResult
    public func join(code raw: String, nickname: String, role: Role?) async throws -> UUID {
        let code = InviteCode.normalize(raw)
        guard code.count == 6, let codeDoc = try await transport.get("inviteCodes/\(code)"),
              let raidID = codeDoc["raidId"]?.string.flatMap(UUID.init(uuidString:)) else {
            throw SyncError.codeNotFound
        }
        let path = Mapping.raidPath(raidID)
        do {
            try await transport.commit([FirestoreWrite(path: path, kind: .appendToArray(field: "memberIDs", values: [uid]))])
        } catch let error as FirebaseError where error.isPermanent {
            // Already a member? Then reading works and we carry on.
            guard (try? await transport.get(path)) != nil else { throw SyncError.raidFullOrClosed }
        }
        guard let doc = try await transport.get(path), let raid = Mapping.raid(doc) else { throw SyncError.raidFullOrClosed }
        store.mergeRemote(raid: raid)
        try store.addMember(Member(id: uid, raidID: raidID, nickname: nickname, role: role, joinedAt: .now))
        LocalIdentity.currentRaidID = raidID
        _ = try await poll(raidID)
        await flush()
        return raidID
    }

    /// Removes my member document, then the raid from this device.
    public func leave(_ raidID: UUID) async {
        if store.raid(raidID)?.isMultiplayer == true {
            try? await transport.commit([FirestoreWrite(path: "\(Mapping.raidPath(raidID))/members/\(uid)", kind: .delete)])
        }
        cursors[raidID] = nil
        try? store.deleteRaidLocally(raidID)
    }

    // MARK: Upload

    /// Sends every pending change. Returns the errors that will be retried later.
    @discardableResult
    public func flush() async -> [Error] {
        var retry: [Error] = []
        func attempt(_ writes: [FirestoreWrite], done: () -> Void) async {
            do {
                try await transport.commit(writes)
                done()
            } catch let error as FirebaseError where error.isPermanent {
                done() // the rules will never accept it
            } catch {
                retry.append(error)
            }
        }

        for raid in store.pendingRaids() {
            guard raid.inviteCode != nil else { continue } // not published yet
            if raid.ownerID == uid {
                var fields = Mapping.fields(raid)
                fields["ownerId"] = nil
                await attempt([FirestoreWrite(path: Mapping.raidPath(raid.id), kind: .set(fields, mask: Array(fields.keys).sorted()))]) {
                    store.markRaidSynced(raid.id)
                }
            } else if raid.status == .won || raid.status == .lost {
                await attempt([FirestoreWrite(path: Mapping.raidPath(raid.id), kind: .set(["status": .string(raid.status.rawValue)], mask: ["status"]))]) {
                    store.markRaidSynced(raid.id)
                }
            } else {
                store.markRaidSynced(raid.id)
            }
        }

        for member in store.pendingMembers() {
            guard member.id == uid else {
                store.markMemberSynced(raidID: member.raidID, memberID: member.id)
                continue
            }
            let fields = Mapping.fields(member)
            await attempt([FirestoreWrite(
                path: "\(Mapping.raidPath(member.raidID))/members/\(member.id)",
                kind: .set(fields, mask: Array(fields.keys).sorted() + ["updatedAt"]), serverTimeFields: ["updatedAt"]
            )]) {
                store.markMemberSynced(raidID: member.raidID, memberID: member.id)
            }
        }

        for (task, deleted) in store.pendingTasks() {
            let fields = Mapping.fields(task, deleted: deleted)
            await attempt([FirestoreWrite(
                path: "\(Mapping.raidPath(task.raidID))/tasks/\(task.id.uuidString)",
                kind: .set(fields, mask: Array(fields.keys).sorted() + ["updatedAt"]), serverTimeFields: ["updatedAt"]
            )]) {
                store.markTaskSynced(task.id)
            }
        }

        for attack in store.pendingAttacks() {
            do {
                try await transport.commit([FirestoreWrite(
                    path: "\(Mapping.raidPath(attack.raidID))/attacks/\(attack.id.uuidString)",
                    kind: .set(Mapping.fields(attack), mask: nil), mustNotExist: true, serverTimeFields: ["serverCreatedAt"]
                )])
                store.markAttackSynced(attack.id)
            } catch let error as FirebaseError where error.isAlreadyExists || error.isPermanent {
                store.markAttackSynced(attack.id) // already there, or never allowed
            } catch {
                retry.append(error)
            }
        }
        return retry
    }

    // MARK: Download

    /// Pulls changes for one raid. Returns true if anything new arrived.
    @discardableResult
    public func poll(_ raidID: UUID) async throws -> Bool {
        let path = Mapping.raidPath(raidID)
        var changed = false
        var c = cursors[raidID] ?? Cursors()

        if let doc = try await transport.get(path), let raid = Mapping.raid(doc) {
            if store.raid(raidID) != raid { changed = true }
            store.mergeRemote(raid: raid)
        }

        for doc in try await transport.query(parent: path, collection: "members", field: "updatedAt", after: c.members) {
            if let member = Mapping.member(doc, raidID: raidID) { store.mergeRemote(member: member); changed = true }
            c.members = max(c.members ?? .distantPast, doc["updatedAt"]?.date ?? .distantPast)
        }
        for doc in try await transport.query(parent: path, collection: "tasks", field: "updatedAt", after: c.tasks) {
            if let (task, deleted) = Mapping.task(doc, raidID: raidID) { store.mergeRemote(task: task, deleted: deleted); changed = true }
            c.tasks = max(c.tasks ?? .distantPast, doc["updatedAt"]?.date ?? .distantPast)
        }
        for doc in try await transport.query(parent: path, collection: "attacks", field: "serverCreatedAt", after: c.attacks) {
            if let attack = Mapping.attack(doc, raidID: raidID) { store.mergeRemote(attack: attack); changed = true }
            c.attacks = max(c.attacks ?? .distantPast, doc["serverCreatedAt"]?.date ?? .distantPast)
        }
        cursors[raidID] = c
        if changed { _ = try? store.settleOutcome(raidID) }
        return changed
    }
}
