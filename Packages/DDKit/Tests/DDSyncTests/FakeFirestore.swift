import Foundation
@testable import DDSync

/// In-memory Firestore for tests. Applies commits atomically and enforces the parts of
/// firestore.rules the sync relies on: create-only preconditions, server timestamps,
/// at most 5 members, and no hits unless the fight is active.
actor FakeFirestore: FirestoreTransport {
    private(set) var docs: [String: FirestoreFields] = [:]
    private var clock = Date(timeIntervalSince1970: 2_000_000_000)
    private(set) var commits = 0
    /// While true, every commit fails like a dropped connection.
    var offline = false

    func setOffline(_ value: Bool) { offline = value }

    func get(_ path: String) async throws -> FirestoreDocument? {
        docs[path].map { FirestoreDocument(path: path, fields: $0) }
    }

    func commit(_ writes: [FirestoreWrite]) async throws {
        if offline { throw URLError(.notConnectedToInternet) }
        commits += 1
        var next = docs
        for w in writes {
            if w.mustNotExist, next[w.path] != nil {
                throw FirebaseError.http(400, "FAILED_PRECONDITION", "document exists")
            }
            clock = clock.addingTimeInterval(1)
            switch w.kind {
            case .set(var fields, let mask):
                for f in w.serverTimeFields { fields[f] = .date(clock) }
                if w.path.contains("/attacks/") { try checkAttack(w.path, fields, in: next) }
                if let mask {
                    var merged = next[w.path] ?? [:]
                    for key in mask { merged[key] = fields[key] }
                    next[w.path] = merged
                } else {
                    next[w.path] = fields
                }
            case .appendToArray(let field, let values):
                guard var doc = next[w.path] else { throw FirebaseError.http(404, "NOT_FOUND", "") }
                var array = doc[field]?.strings ?? []
                for v in values where !array.contains(v) { array.append(v) }
                let status = doc["status"]?.string
                if array.count > 5 || (status != "planning" && status != "active") {
                    throw FirebaseError.http(403, "PERMISSION_DENIED", "raid full or closed")
                }
                doc[field] = .strings(array)
                next[w.path] = doc
            case .delete:
                next[w.path] = nil
            }
        }
        docs = next
    }

    func query(parent: String, collection: String, field: String, after cursor: Date?) async throws -> [FirestoreDocument] {
        let prefix = "\(parent)/\(collection)/"
        return docs
            .filter { $0.key.hasPrefix(prefix) && !$0.key.dropFirst(prefix.count).contains("/") }
            .compactMap { path, fields -> FirestoreDocument? in
                guard let date = fields[field]?.date else { return nil }
                if let cursor, date <= cursor { return nil }
                return FirestoreDocument(path: path, fields: fields)
            }
            .sorted { ($0[field]?.date ?? .distantPast) < ($1[field]?.date ?? .distantPast) }
    }

    private func checkAttack(_ path: String, _ fields: FirestoreFields, in docs: [String: FirestoreFields]) throws {
        let raidPath = path.components(separatedBy: "/attacks/")[0]
        guard docs[raidPath]?["status"]?.string == "active" else {
            throw FirebaseError.http(403, "PERMISSION_DENIED", "fight not active")
        }
    }

    func setStatus(_ raidPath: String, _ status: String) {
        docs[raidPath]?["status"] = .string(status)
    }
}

/// One player's view of the fake cloud: raids are readable only by their members,
/// like `allow read: if request.auth.uid in resource.data.memberIDs`.
struct FakeClient: FirestoreTransport {
    let cloud: FakeFirestore
    let uid: String

    func get(_ path: String) async throws -> FirestoreDocument? {
        let doc = try await cloud.get(path)
        if path.hasPrefix("raids/"), path.split(separator: "/").count == 2, let doc,
           !(doc["memberIDs"]?.strings ?? []).contains(uid) {
            throw FirebaseError.http(403, "PERMISSION_DENIED", "not a member")
        }
        return doc
    }

    func commit(_ writes: [FirestoreWrite]) async throws { try await cloud.commit(writes) }

    func query(parent: String, collection: String, field: String, after cursor: Date?) async throws -> [FirestoreDocument] {
        try await cloud.query(parent: parent, collection: collection, field: field, after: cursor)
    }
}
