import Foundation

/// A Firestore field value (the subset this app uses).
public enum FirestoreValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case date(Date)
    case strings([String])
    case null

    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var int: Int? { if case .int(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var date: Date? { if case .date(let v) = self { v } else { nil } }
    public var strings: [String]? { if case .strings(let v) = self { v } else { nil } }
}

public typealias FirestoreFields = [String: FirestoreValue]

/// A document read from Firestore. `path` is relative to `…/documents`, e.g. `raids/ID`.
public struct FirestoreDocument: Sendable, Equatable {
    public var path: String
    public var fields: FirestoreFields

    public init(path: String, fields: FirestoreFields) {
        self.path = path
        self.fields = fields
    }

    public var id: String { String(path.split(separator: "/").last ?? "") }
    public subscript(_ key: String) -> FirestoreValue? { fields[key] }
}

/// One write in an atomic commit.
public struct FirestoreWrite: Sendable {
    public enum Kind: Sendable {
        /// Set fields. With `mask`, only those fields change (merge); otherwise the document is replaced.
        case set(FirestoreFields, mask: [String]?)
        /// Adds values to an array field if they're missing (Firestore `arrayUnion`).
        case appendToArray(field: String, values: [String])
        case delete
    }

    public var path: String
    public var kind: Kind
    /// Fail the whole commit if the document already exists.
    public var mustNotExist: Bool
    /// Fields set to the server's time when the write is applied.
    public var serverTimeFields: [String]

    public init(path: String, kind: Kind, mustNotExist: Bool = false, serverTimeFields: [String] = []) {
        self.path = path
        self.kind = kind
        self.mustNotExist = mustNotExist
        self.serverTimeFields = serverTimeFields
    }
}

/// What the sync engine needs from Firestore. `FirestoreREST` talks to the real service;
/// tests use an in-memory fake.
public protocol FirestoreTransport: Sendable {
    func get(_ path: String) async throws -> FirestoreDocument?
    func commit(_ writes: [FirestoreWrite]) async throws
    /// Documents of `collection` under `parent` whose timestamp `field` is after `cursor`, oldest first.
    func query(parent: String, collection: String, field: String, after cursor: Date?) async throws -> [FirestoreDocument]
}

public enum FirebaseError: LocalizedError, Equatable {
    /// HTTP status, Google status (e.g. `PERMISSION_DENIED`), message.
    case http(Int, String, String)
    case badResponse
    case notConfigured

    public var status: String {
        if case .http(_, let status, _) = self { return status }
        return ""
    }

    /// The write can never succeed (rules said no), so retrying is pointless.
    public var isPermanent: Bool { status == "PERMISSION_DENIED" || status == "INVALID_ARGUMENT" }

    /// A create-only write found the document already there.
    public var isAlreadyExists: Bool { status == "ALREADY_EXISTS" || status == "FAILED_PRECONDITION" }

    public var errorDescription: String? {
        switch self {
        case .http(let code, let status, let message): "Server error \(code) \(status): \(message)"
        case .badResponse: "Unexpected server response."
        case .notConfigured: "Multiplayer isn't set up in this build."
        }
    }
}

// MARK: - Firestore REST JSON

enum FirestoreJSON {
    static func encode(_ value: FirestoreValue) -> [String: Any] {
        switch value {
        case .string(let s): ["stringValue": s]
        case .int(let i): ["integerValue": String(i)]
        case .bool(let b): ["booleanValue": b]
        case .date(let d): ["timestampValue": timestamp(d)]
        case .strings(let a): ["arrayValue": ["values": a.map { ["stringValue": $0] }]]
        case .null: ["nullValue": NSNull()]
        }
    }

    static func decode(_ json: [String: Any]) -> FirestoreValue? {
        if let s = json["stringValue"] as? String { return .string(s) }
        if let s = json["integerValue"] as? String, let i = Int(s) { return .int(i) }
        if let i = json["integerValue"] as? Int { return .int(i) }
        if let b = json["booleanValue"] as? Bool { return .bool(b) }
        if let t = json["timestampValue"] as? String, let d = parse(t) { return .date(d) }
        if let a = json["arrayValue"] as? [String: Any] {
            return .strings((a["values"] as? [[String: Any]] ?? []).compactMap { $0["stringValue"] as? String })
        }
        if json["nullValue"] != nil { return .null }
        return nil
    }

    /// `{"name": "projects/…/documents/raids/ID", "fields": {…}}` → document with a relative path.
    static func document(_ json: [String: Any], root: String) -> FirestoreDocument? {
        guard let name = json["name"] as? String else { return nil }
        let path = name.hasPrefix(root + "/") ? String(name.dropFirst(root.count + 1)) : name
        let raw = json["fields"] as? [String: [String: Any]] ?? [:]
        return FirestoreDocument(path: path, fields: raw.compactMapValues(decode))
    }

    static func write(_ w: FirestoreWrite, root: String) -> [String: Any] {
        let name = "\(root)/\(w.path)"
        var out: [String: Any]
        switch w.kind {
        case .set(let fields, let mask):
            out = ["update": ["name": name, "fields": fields.mapValues(encode)]]
            if let mask { out["updateMask"] = ["fieldPaths": mask] }
        case .appendToArray(let field, let values):
            out = ["transform": ["document": name, "fieldTransforms": [[
                "fieldPath": field,
                "appendMissingElements": ["values": values.map { ["stringValue": $0] }],
            ]]]]
        case .delete:
            out = ["delete": name]
        }
        if w.mustNotExist { out["currentDocument"] = ["exists": false] }
        if !w.serverTimeFields.isEmpty, case .set = w.kind {
            out["updateTransforms"] = w.serverTimeFields.map { ["fieldPath": $0, "setToServerValue": "REQUEST_TIME"] }
        }
        return out
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    /// Parses RFC 3339 timestamps, including Firestore's nanosecond precision.
    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        if let dot = s.firstIndex(of: "."), let z = s.lastIndex(of: "Z"), dot < z {
            let fraction = s[s.index(after: dot)..<z].prefix(3)
            if let d = f.date(from: String(s[..<dot]) + "." + fraction + "Z") { return d }
        }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
