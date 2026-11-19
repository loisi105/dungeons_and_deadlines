import Foundation
import Security

/// Firebase without the SDK: Auth and Firestore over REST with URLSession.
/// The SDK added ~1.4 s to every launch (gRPC, abseil, OpenSSL); this adds nothing.

public struct FirebaseConfig: Sendable, Equatable {
    public let apiKey: String
    public let projectID: String
    public let useEmulator: Bool

    public init(apiKey: String, projectID: String, useEmulator: Bool = false) {
        self.apiKey = apiKey
        self.projectID = projectID
        self.useEmulator = useEmulator
    }

    /// Reads `API_KEY` and `PROJECT_ID` from `GoogleService-Info.plist` (git-ignored).
    /// With the emulator, a demo project works without the file.
    public static func load(bundle: Bundle = .main, useEmulator: Bool) -> FirebaseConfig? {
        if let url = bundle.url(forResource: "GoogleService-Info", withExtension: "plist"),
           let plist = NSDictionary(contentsOf: url),
           let key = plist["API_KEY"] as? String, let project = plist["PROJECT_ID"] as? String {
            return FirebaseConfig(apiKey: key, projectID: project, useEmulator: useEmulator)
        }
        return useEmulator ? FirebaseConfig(apiKey: "emulator", projectID: "demo-dungeons", useEmulator: true) : nil
    }

    var authBase: String { useEmulator ? "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1" : "https://identitytoolkit.googleapis.com/v1" }
    var tokenBase: String { useEmulator ? "http://127.0.0.1:9099/securetoken.googleapis.com/v1" : "https://securetoken.googleapis.com/v1" }
    var firestoreHost: String { useEmulator ? "http://127.0.0.1:8080/v1" : "https://firestore.googleapis.com/v1" }
    var documentsRoot: String { "projects/\(projectID)/databases/(default)/documents" }
}

// MARK: - Auth

/// Anonymous Firebase Auth. The refresh token and user ID live in the Keychain,
/// so the player keeps the same account across launches.
public actor FirebaseAuthREST {
    private let config: FirebaseConfig
    private let session: URLSession
    private var uid: String?
    private var idToken: String?
    private var refreshToken: String?
    private var expiresAt = Date.distantPast

    public init(config: FirebaseConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Restores the saved account or creates a new anonymous one. Returns the user ID.
    public func signIn() async throws -> String {
        if let uid = Keychain.read("firebase.uid"), let refresh = Keychain.read("firebase.refreshToken") {
            self.uid = uid
            refreshToken = refresh
            _ = try await validToken()
            return uid
        }
        var request = URLRequest(url: URL(string: "\(config.authBase)/accounts:signUp?key=\(config.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["returnSecureToken": true])
        let json = try await HTTP.send(request, session: session)
        guard let token = json["idToken"] as? String, let refresh = json["refreshToken"] as? String,
              let uid = json["localId"] as? String else { throw FirebaseError.badResponse }
        self.uid = uid
        idToken = token
        refreshToken = refresh
        expiresAt = Date().addingTimeInterval((Double(json["expiresIn"] as? String ?? "3600") ?? 3600) - 60)
        Keychain.write("firebase.uid", uid)
        Keychain.write("firebase.refreshToken", refresh)
        return uid
    }

    /// An ID token valid for at least another minute.
    public func validToken() async throws -> String {
        if let idToken, expiresAt > Date() { return idToken }
        guard let refreshToken else { throw FirebaseError.notConfigured }
        var request = URLRequest(url: URL(string: "\(config.tokenBase)/token?key=\(config.apiKey)")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(refreshToken)".data(using: .utf8)
        let json = try await HTTP.send(request, session: session)
        guard let token = json["id_token"] as? String, let refresh = json["refresh_token"] as? String else {
            throw FirebaseError.badResponse
        }
        idToken = token
        self.refreshToken = refresh
        expiresAt = Date().addingTimeInterval((Double(json["expires_in"] as? String ?? "3600") ?? 3600) - 60)
        Keychain.write("firebase.refreshToken", refresh)
        return token
    }
}

// MARK: - Firestore

/// Firestore over REST: `GET` a document, atomic `commit`, and `runQuery`.
public struct FirestoreREST: FirestoreTransport {
    let config: FirebaseConfig
    let auth: FirebaseAuthREST
    let session: URLSession

    public init(config: FirebaseConfig, auth: FirebaseAuthREST, session: URLSession = .shared) {
        self.config = config
        self.auth = auth
        self.session = session
    }

    public func get(_ path: String) async throws -> FirestoreDocument? {
        var request = try await authorized("\(config.firestoreHost)/\(config.documentsRoot)/\(path)")
        request.httpMethod = "GET"
        do {
            return FirestoreJSON.document(try await HTTP.send(request, session: session), root: config.documentsRoot)
        } catch let error as FirebaseError where error.status == "NOT_FOUND" {
            return nil
        }
    }

    public func commit(_ writes: [FirestoreWrite]) async throws {
        var request = try await authorized("\(config.firestoreHost)/\(config.documentsRoot):commit")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "writes": writes.map { FirestoreJSON.write($0, root: config.documentsRoot) },
        ])
        _ = try await HTTP.send(request, session: session)
    }

    public func query(parent: String, collection: String, field: String, after cursor: Date?) async throws -> [FirestoreDocument] {
        var structured: [String: Any] = [
            "from": [["collectionId": collection]],
            "orderBy": [["field": ["fieldPath": field], "direction": "ASCENDING"]],
        ]
        if let cursor {
            structured["where"] = ["fieldFilter": [
                "field": ["fieldPath": field], "op": "GREATER_THAN",
                "value": FirestoreJSON.encode(.date(cursor)),
            ]]
        }
        var request = try await authorized("\(config.firestoreHost)/\(config.documentsRoot)/\(parent):runQuery")
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["structuredQuery": structured])
        let rows = try await HTTP.sendArray(request, session: session)
        return rows.compactMap { ($0["document"] as? [String: Any]).flatMap { FirestoreJSON.document($0, root: config.documentsRoot) } }
    }

    private func authorized(_ url: String) async throws -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(try await auth.validToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        return request
    }
}

// MARK: - HTTP

enum HTTP {
    static func send(_ request: URLRequest, session: URLSession) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        try check(data, response)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    static func sendArray(_ request: URLRequest, session: URLSession) async throws -> [[String: Any]] {
        let (data, response) = try await session.data(for: request)
        try check(data, response)
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    static func check(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw FirebaseError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            var json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? [String: Any]
            // runQuery and commit can return the error inside an array.
            if json == nil, let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                json = array.first?["error"] as? [String: Any]
            }
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
