import Foundation
import Security

/// Firebase without the SDK: the app talks to Firebase Auth and Firestore over REST.
/// The SDK added ~1.4 s to every launch (gRPC, abseil, OpenSSL); URLSession adds nothing.

// MARK: - Configuration

struct FirebaseConfig: Sendable {
    let apiKey: String
    let projectID: String
    let useEmulator: Bool

    /// Reads `GoogleService-Info.plist` (git-ignored; see firebase/README.md).
    static func load(useEmulator: Bool) -> FirebaseConfig? {
        guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
              let plist = NSDictionary(contentsOf: url),
              let key = plist["API_KEY"] as? String,
              let project = plist["PROJECT_ID"] as? String else {
            // The emulator works without a real project.
            return useEmulator ? FirebaseConfig(apiKey: "emulator", projectID: "demo-dungeons", useEmulator: true) : nil
        }
        return FirebaseConfig(apiKey: key, projectID: project, useEmulator: useEmulator)
    }

    var authBase: String { useEmulator ? "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1" : "https://identitytoolkit.googleapis.com/v1" }
    var tokenBase: String { useEmulator ? "http://127.0.0.1:9099/securetoken.googleapis.com/v1" : "https://securetoken.googleapis.com/v1" }
    var firestoreHost: String { useEmulator ? "http://127.0.0.1:8080/v1" : "https://firestore.googleapis.com/v1" }
    var databaseName: String { "projects/\(projectID)/databases/(default)" }
    var documentsRoot: String { "\(databaseName)/documents" }
}

enum FirebaseError: LocalizedError {
    case http(Int, String, String)
    case badResponse

    /// Firestore/Auth status such as "PERMISSION_DENIED", "FAILED_PRECONDITION", "NOT_FOUND".
    var status: String {
        if case .http(_, let status, _) = self { return status }
        return ""
    }

    var errorDescription: String? {
        switch self {
        case .http(let code, let status, let message): "Server error \(code) \(status): \(message)"
        case .badResponse: "Unexpected server response."
        }
    }
}

// MARK: - Auth (anonymous accounts)

/// Anonymous Firebase Auth over REST. The refresh token lives in the Keychain.
actor FirebaseAuthREST {
    struct Session: Sendable {
        var uid: String
        var idToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    private let config: FirebaseConfig
    private var session: Session?

    init(config: FirebaseConfig) { self.config = config }

    var uid: String? { session?.uid }

    /// Restores the saved account or creates a new anonymous one.
    func signIn() async throws -> String {
        if let saved = Keychain.read("firebase.refreshToken"), let uid = Keychain.read("firebase.uid") {
            session = Session(uid: uid, idToken: "", refreshToken: saved, expiresAt: .distantPast)
            _ = try await validToken()
            return uid
        }
        let json = try await post("\(config.authBase)/accounts:signUp?key=\(config.apiKey)", json: ["returnSecureToken": true])
        guard let idToken = json["idToken"] as? String, let refresh = json["refreshToken"] as? String,
              let uid = json["localId"] as? String else { throw FirebaseError.badResponse }
        let expires = Double(json["expiresIn"] as? String ?? "3600") ?? 3600
        session = Session(uid: uid, idToken: idToken, refreshToken: refresh, expiresAt: Date().addingTimeInterval(expires - 60))
        Keychain.write("firebase.refreshToken", refresh)
        Keychain.write("firebase.uid", uid)
        return uid
    }

    /// An ID token valid for at least a minute, refreshing if needed.
    func validToken() async throws -> String {
        guard var s = session else { throw FirebaseError.badResponse }
        if s.expiresAt > Date(), !s.idToken.isEmpty { return s.idToken }
        var request = URLRequest(url: URL(string: "\(config.tokenBase)/token?key=\(config.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(s.refreshToken)".data(using: .utf8)
        let json = try await FirestoreREST.send(request)
        guard let idToken = json["id_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw FirebaseError.badResponse
        }
        s.idToken = idToken
        s.refreshToken = refresh
        s.expiresAt = Date().addingTimeInterval((Double(json["expires_in"] as? String ?? "3600") ?? 3600) - 60)
        session = s
        Keychain.write("firebase.refreshToken", refresh)
        return idToken
    }

    private func post(_ url: String, json: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await FirestoreREST.send(request)
    }
}

// MARK: - Firestore

/// Minimal Firestore REST client: get, commit (atomic writes with preconditions), query.
struct FirestoreREST: Sendable {
    let config: FirebaseConfig
    let auth: FirebaseAuthREST

    /// A field value in Firestore's typed JSON.
    enum Value {
        case string(String), int(Int), bool(Bool), date(Date), null, strings([String])

        var json: [String: Any] {
            switch self {
            case .string(let s): ["stringValue": s]
            case .int(let i): ["integerValue": String(i)]
            case .bool(let b): ["booleanValue": b]
            case .date(let d): ["timestampValue": FirestoreREST.timestamp(d)]
            case .null: ["nullValue": NSNull()]
            case .strings(let a): ["arrayValue": ["values": a.map { ["stringValue": $0] }]]
            }
        }
    }

    /// A document's fields decoded to plain Swift values (String, Int, Bool, Date, [String], nil).
    struct Document {
        let path: String
        let fields: [String: Any]
        var id: String { String(path.split(separator: "/").last ?? "") }
        func string(_ k: String) -> String? { fields[k] as? String }
        func int(_ k: String) -> Int? { fields[k] as? Int }
        func bool(_ k: String) -> Bool? { fields[k] as? Bool }
        func date(_ k: String) -> Date? { fields[k] as? Date }
        func strings(_ k: String) -> [String] { fields[k] as? [String] ?? [] }
    }

    struct Write {
        var path: String
        var fields: [String: Value]
        /// Only these fields are written (merge). Nil writes `fields` as given.
        var mask: [String]?
        var mustNotExist = false
        var serverTimeFields: [String] = []
        var appendToArray: (field: String, values: [String])?
    }

    func get(_ path: String) async throws -> Document? {
        var request = try await authorized("\(config.firestoreHost)/\(config.documentsRoot)/\(path)")
        request.httpMethod = "GET"
        do {
            return Self.document(try await Self.send(request))
        } catch let error as FirebaseError where error.status == "NOT_FOUND" {
            return nil
        }
    }

    func commit(_ writes: [Write]) async throws {
        let body: [String: Any] = ["writes": writes.map(encode)]
        var request = try await authorized("\(config.firestoreHost)/\(config.documentsRoot):commit")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await Self.send(request)
    }

    /// Documents in `collection` under `parent` whose `field` is after `cursor`, oldest first.
    func query(parent: String, collection: String, after cursor: Date?, field: String) async throws -> [Document] {
        var query: [String: Any] = [
            "from": [["collectionId": collection]],
            "orderBy": [["field": ["fieldPath": field], "direction": "ASCENDING"]],
        ]
        if let cursor {
            query["where"] = ["fieldFilter": [
                "field": ["fieldPath": field], "op": "GREATER_THAN", "value": Value.date(cursor).json,
            ]]
        }
        var request = try await authorized("\(config.firestoreHost)/\(config.documentsRoot)/\(parent):runQuery")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": query])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(data, response)
        let rows = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        return rows.compactMap { ($0["document"] as? [String: Any]).flatMap(Self.document) }
    }

    // MARK: Encoding

    private func encode(_ w: Write) -> [String: Any] {
        let name = "\(config.documentsRoot)/\(w.path)"
        if let append = w.appendToArray, w.fields.isEmpty {
            return ["transform": ["document": name, "fieldTransforms": [[
                "fieldPath": append.field,
                "appendMissingElements": ["values": append.values.map { ["stringValue": $0] }],
            ]]]]
        }
        var out: [String: Any] = ["update": ["name": name, "fields": w.fields.mapValues(\.json)]]
        if let mask = w.mask { out["updateMask"] = ["fieldPaths": mask] }
        if w.mustNotExist { out["currentDocument"] = ["exists": false] }
        if !w.serverTimeFields.isEmpty {
            out["updateTransforms"] = w.serverTimeFields.map { ["fieldPath": $0, "setToServerValue": "REQUEST_TIME"] }
        }
        return out
    }

    static func document(_ json: [String: Any]) -> Document? {
        guard let name = json["name"] as? String else { return nil }
        let raw = json["fields"] as? [String: [String: Any]] ?? [:]
        return Document(path: name, fields: raw.compactMapValues(decode))
    }

    static func decode(_ v: [String: Any]) -> Any? {
        if let s = v["stringValue"] as? String { return s }
        if let s = v["integerValue"] as? String { return Int(s) }
        if let i = v["integerValue"] as? Int { return i }
        if let b = v["booleanValue"] as? Bool { return b }
        if let t = v["timestampValue"] as? String { return parse(t) }
        if let a = v["arrayValue"] as? [String: Any] { return (a["values"] as? [[String: Any]] ?? []).compactMap { $0["stringValue"] as? String } }
        return nil
    }

    static func timestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    static func parse(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        // Firestore may send nanoseconds; trim to milliseconds.
        if let dot = s.firstIndex(of: "."), let z = s.lastIndex(of: "Z") {
            let frac = s[s.index(after: dot)..<z].prefix(3)
            return f.date(from: String(s[..<dot]) + "." + frac + "Z")
        }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: HTTP

    private func authorized(_ url: String) async throws -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await auth.validToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        return request
    }

    static func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(data, response)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw FirebaseError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            throw FirebaseError.http(http.statusCode, json?["status"] as? String ?? "", json?["message"] as? String ?? "")
        }
    }
}

// MARK: - Keychain

enum Keychain {
    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
