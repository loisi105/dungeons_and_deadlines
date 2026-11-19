import Foundation
import SwiftData
import Testing
import GameCore
import DDPersistence
@testable import DDSync

@MainActor
func makePlayer(_ uid: String, _ firestore: FakeFirestore) throws -> RaidSync {
    let store = RaidStore(container: try SharedContainer.make(inMemory: true))
    return RaidSync(store: store, transport: FakeClient(cloud: firestore, uid: uid), uid: uid)
}

@Suite("Raid sync", .serialized) @MainActor
struct RaidSyncTests {
    @Test("Two players converge: publish, join, plan, fight, hit")
    func converge() async throws {
        let cloud = FakeFirestore()
        let alice = try makePlayer("alice", cloud)
        let bob = try makePlayer("bob", cloud)

        let raid = try alice.store.createRaid(
            name: "Thesis", bossName: "Dragon", deadline: .now.addingTimeInterval(86_400 * 7),
            multiplayer: true, owner: LocalIdentity(memberID: "alice", nickname: "Alice")
        )
        try alice.store.addTask(raidID: raid.id, title: "Outline", size: .m)
        let published = try await alice.publish(raid, code: { "ABCDEF" })
        #expect(published.inviteCode == "ABCDEF")
        #expect(alice.store.pendingRaids().isEmpty)

        // Bob joins before the fight and sees the planned task.
        let joined = try await bob.join(code: "abc-def", nickname: "Bob", role: .tank)
        #expect(joined == raid.id)
        #expect(bob.store.tasks(raid.id).map(\.title) == ["Outline"])
        #expect(await cloud.docs["raids/\(raid.id.uuidString)"]?["memberIDs"]?.strings == ["alice", "bob"])

        // Alice starts the fight; Bob sees locked HP and completes the task.
        try alice.store.startFight(raid.id, by: "alice")
        await alice.flush()
        try await alice.poll(raid.id)
        try await bob.poll(raid.id)
        #expect(bob.store.raid(raid.id)?.status == .active)
        #expect(bob.store.raid(raid.id)?.lockedMaxHP == 231)

        let task = try #require(bob.store.tasks(raid.id).first)
        let hit = try #require(try bob.store.completeTask(task.id, by: "bob"))
        let errors = await bob.flush()
        #expect(errors.isEmpty)

        // Alice pulls Bob's hit and the completed task; both see the same boss.
        #expect(try await alice.poll(raid.id))
        #expect(alice.store.attacks(raid.id).map(\.id) == [hit.id])
        #expect(alice.store.task(task.id)?.completedBy == "bob")
        #expect(alice.store.bossState(raid.id)?.currentHP == bob.store.bossState(raid.id)?.currentHP)
        #expect(alice.store.members(raid.id).map(\.nickname).sorted() == ["Alice", "Bob"])

        // Nothing new: the next poll reads only changes.
        #expect(try await alice.poll(raid.id) == false)
    }

    @Test("Wrong code, full raid")
    func joinErrors() async throws {
        let cloud = FakeFirestore()
        let owner = try makePlayer("p0", cloud)
        let raid = try owner.store.createRaid(name: "R", bossName: "B", deadline: .now.addingTimeInterval(3600), multiplayer: true, owner: LocalIdentity(memberID: "p0", nickname: "P0"))
        try await owner.publish(raid, code: { "QWERTY" })

        let stranger = try makePlayer("x", cloud)
        await #expect(throws: RaidSync.SyncError.codeNotFound) { try await stranger.join(code: "ZZZZZZ", nickname: "X", role: nil) }

        for i in 1...4 {
            let p = try makePlayer("p\(i)", cloud)
            try await p.join(code: "QWERTY", nickname: "P\(i)", role: nil)
        }
        let sixth = try makePlayer("p5", cloud)
        await #expect(throws: RaidSync.SyncError.raidFullOrClosed) { try await sixth.join(code: "QWERTY", nickname: "P5", role: nil) }
    }

    @Test("A taken invite code is retried with a new one")
    func codeCollision() async throws {
        let cloud = FakeFirestore()
        let a = try makePlayer("a", cloud)
        let first = try a.store.createRaid(name: "One", bossName: "B", deadline: .now.addingTimeInterval(3600), multiplayer: true, owner: LocalIdentity(memberID: "a", nickname: "A"))
        try await a.publish(first, code: { "AAAAAA" })
        let second = try a.store.createRaid(name: "Two", bossName: "B", deadline: .now.addingTimeInterval(3600), multiplayer: true, owner: LocalIdentity(memberID: "a", nickname: "A"))
        var codes = ["AAAAAA", "BBBBBB"]
        let published = try await a.publish(second, code: { codes.removeFirst() })
        #expect(published.inviteCode == "BBBBBB")
    }

    @Test("Network errors keep items pending; a re-sent attack counts as done; rule rejections are dropped")
    func retries() async throws {
        let cloud = FakeFirestore()
        let a = try makePlayer("a", cloud)
        let raid = try a.store.createRaid(name: "R", bossName: "B", deadline: .now.addingTimeInterval(86_400), multiplayer: true, owner: LocalIdentity(memberID: "a", nickname: "A"))
        let task = try a.store.addTask(raidID: raid.id, title: "T", size: .s)
        let task2 = try a.store.addTask(raidID: raid.id, title: "T2", size: .s)
        try await a.publish(raid, code: { "CCCCCC" })
        try a.store.startFight(raid.id, by: "a")
        await a.flush()
        let hit = try #require(try a.store.completeTask(task.id, by: "a"))

        await cloud.setOffline(true)
        let errors = await a.flush()
        #expect(!errors.isEmpty)
        #expect(a.store.pendingAttacks().map(\.id) == [hit.id])

        await cloud.setOffline(false)
        await a.flush()
        #expect(a.store.pendingAttacks().isEmpty)

        // The app died before marking the attack synced: re-sending it must not double count.
        let record = try #require(try a.store.context.fetch(FetchDescriptor<AttackRecord>()).first)
        record.syncStateRaw = SyncState.pending.rawValue
        await a.flush()
        #expect(a.store.pendingAttacks().isEmpty)
        #expect(await cloud.docs.keys.filter { $0.contains("/attacks/") }.count == 1)

        // The fight ended on the server: the rules reject new hits, so they're dropped, not retried forever.
        await cloud.setStatus("raids/\(raid.id.uuidString)", "won")
        try a.store.completeTask(task2.id, by: "a")
        let rejected = await a.flush()
        #expect(rejected.isEmpty)
        #expect(a.store.pendingAttacks().isEmpty)
        #expect(await cloud.docs.keys.filter { $0.contains("/attacks/") }.count == 1)
    }
}

@Suite("Firestore JSON")
struct FirestoreJSONTests {
    @Test("Values round-trip through Firestore's typed JSON")
    func values() {
        let date = Date(timeIntervalSince1970: 1_800_000_000.123)
        for value: FirestoreValue in [.string("Ada"), .int(42), .bool(true), .date(date), .strings(["a", "b"]), .null] {
            let decoded = FirestoreJSON.decode(FirestoreJSON.encode(value))
            if case .date(let d) = value {
                #expect(abs((decoded?.date ?? .distantPast).timeIntervalSince(d)) < 0.001)
            } else {
                #expect(decoded == value)
            }
        }
    }

    @Test("Nanosecond timestamps from Firestore parse")
    func nanos() {
        #expect(FirestoreJSON.parse("2026-11-19T12:00:00.123456789Z") != nil)
        #expect(FirestoreJSON.parse("2026-11-19T12:00:00Z") != nil)
    }

    @Test("Writes encode preconditions, masks, transforms and paths")
    func writes() throws {
        let root = "projects/p/databases/(default)/documents"
        let w = FirestoreJSON.write(FirestoreWrite(path: "raids/R/attacks/A", kind: .set(["damage": .int(5)], mask: nil), mustNotExist: true, serverTimeFields: ["serverCreatedAt"]), root: root)
        let update = try #require(w["update"] as? [String: Any])
        #expect(update["name"] as? String == "\(root)/raids/R/attacks/A")
        #expect((w["currentDocument"] as? [String: Any])?["exists"] as? Bool == false)
        #expect(((w["updateTransforms"] as? [[String: Any]])?.first?["setToServerValue"]) as? String == "REQUEST_TIME")

        let join = FirestoreJSON.write(FirestoreWrite(path: "raids/R", kind: .appendToArray(field: "memberIDs", values: ["u"])), root: root)
        #expect((join["transform"] as? [String: Any])?["document"] as? String == "\(root)/raids/R")

        let doc = try #require(FirestoreJSON.document(["name": "\(root)/raids/R", "fields": ["name": ["stringValue": "Thesis"]]], root: root))
        #expect(doc.path == "raids/R")
        #expect(doc["name"]?.string == "Thesis")
    }

    @Test("Error statuses decide retry vs drop")
    func errors() {
        #expect(FirebaseError.http(403, "PERMISSION_DENIED", "").isPermanent)
        #expect(FirebaseError.http(409, "ALREADY_EXISTS", "").isAlreadyExists)
        #expect(!FirebaseError.http(503, "UNAVAILABLE", "").isPermanent)
    }

    @Test("Invite codes avoid look-alike characters")
    func codes() {
        let code = InviteCode.generate()
        #expect(code.count == 6)
        #expect(!code.contains(where: { "0O1I".contains($0) }))
        #expect(InviteCode.normalize("abc-d e f") == "ABCDEF")
    }
}
