import Foundation
import SwiftUI
import GameCore
import DDPersistence
import DDIntents
#if canImport(FirebaseCore)
@preconcurrency import FirebaseCore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
#endif

/// Pushes the local outbox to Firestore and merges teammates' changes back into the
/// local store. Lives only in the app target; widgets never talk to Firebase.
///
/// Multiplayer is available only when a `GoogleService-Info.plist` is bundled
/// (or the app runs against the emulator). Without it the app is solo-only.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case unavailable
        case signingIn
        case ready
        case failed(String)
    }

    enum SyncError: LocalizedError {
        case unavailable
        case codeNotFound
        case raidFullOrClosed
        case network(String)

        var errorDescription: String? {
            switch self {
            case .unavailable: String(localized: "Multiplayer isn't set up in this build. Add GoogleService-Info.plist (see the README).")
            case .codeNotFound: String(localized: "No raid uses this code. Check it with the raid leader.")
            case .raidFullOrClosed: String(localized: "This raid is full (5 members) or has already ended.")
            case .network(let message): message
            }
        }
    }

    private(set) var status: Status = .unavailable
    private(set) var lastError: String?
    var isAvailable: Bool { status == .ready }
    var store: RaidStore { DDStore.shared }

    private var flushTask: Task<Void, Never>?
    #if canImport(FirebaseCore)
    private var listeners: [UUID: [any ListenerRegistration]] = [:]
    private var db: Firestore { Firestore.firestore() }
    #endif

    // MARK: Setup

    func configure() {
        #if canImport(FirebaseCore)
        guard !LaunchOptions.isUITesting else { return }
        let hasConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil
        guard hasConfig else { return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        if LaunchOptions.useFirebaseEmulator {
            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "127.0.0.1:8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
        } else {
            // The local SwiftData store is the offline cache; keep Firestore's small.
            let settings = Firestore.firestore().settings
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
        }
        status = .signingIn
        Task { await signIn() }
        #endif
    }

    #if canImport(FirebaseCore)
    private func signIn() async {
        do {
            let uid: String
            if let user = Auth.auth().currentUser {
                uid = user.uid
            } else {
                uid = try await Auth.auth().signInAnonymously().user.uid
            }
            let old = LocalIdentity.current.memberID
            if old != uid {
                try store.migrateMemberID(from: old, to: uid)
                LocalIdentity.setMemberID(uid)
            }
            status = .ready
            refreshListeners()
            scheduleFlush(raidID: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
    #endif

    func appDidBecomeActive() {
        guard isAvailable else { return }
        refreshListeners()
        scheduleFlush(raidID: nil)
    }

    // MARK: Create and join

    /// Publishes a newly created multiplayer raid and gives it an invite code.
    func publish(_ raid: Raid) async throws {
        #if canImport(FirebaseCore)
        guard isAvailable else { throw SyncError.unavailable }
        let uid = LocalIdentity.current.memberID
        for _ in 0..<5 {
            let code = InviteCode.generate()
            var published = raid
            published.inviteCode = code
            let raidRef = db.collection("raids").document(raid.id.uuidString)
            let codeRef = db.collection("inviteCodes").document(code)
            var data = Self.data(for: published)
            data["memberIDs"] = [uid]
            do {
                if try await codeRef.getDocument().exists { continue }
                let batch = db.batch()
                batch.setData(data, forDocument: raidRef)
                batch.setData(["raidId": raid.id.uuidString], forDocument: codeRef)
                try await batch.commit()
                try store.updateRaid(published)
                store.markRaidSynced(raid.id)
                refreshListeners()
                scheduleFlush(raidID: raid.id)
                return
            } catch {
                throw SyncError.network(error.localizedDescription)
            }
        }
        throw SyncError.network(String(localized: "Couldn't create an invite code. Try again."))
        #else
        throw SyncError.unavailable
        #endif
    }

    /// Joins a raid by invite code and pulls it into the local store.
    @discardableResult
    func join(code rawCode: String, role: Role?) async throws -> UUID {
        #if canImport(FirebaseCore)
        guard isAvailable else { throw SyncError.unavailable }
        let code = InviteCode.normalize(rawCode)
        let me = LocalIdentity.current
        let codeSnapshot: DocumentSnapshot
        do {
            codeSnapshot = try await db.collection("inviteCodes").document(code).getDocument()
        } catch {
            throw SyncError.network(error.localizedDescription)
        }
        guard let raidIDString = codeSnapshot.data()?["raidId"] as? String, let raidID = UUID(uuidString: raidIDString) else {
            throw SyncError.codeNotFound
        }
        let raidRef = db.collection("raids").document(raidIDString)
        do {
            try await raidRef.updateData(["memberIDs": FieldValue.arrayUnion([me.memberID])])
        } catch {
            // Already a member? Then reading works and we just continue.
            if (try? await raidRef.getDocument())?.exists != true { throw SyncError.raidFullOrClosed }
        }
        let snapshot: DocumentSnapshot
        do {
            snapshot = try await raidRef.getDocument()
        } catch {
            throw SyncError.raidFullOrClosed
        }
        guard let raid = Self.raid(from: snapshot) else { throw SyncError.codeNotFound }
        store.mergeRemote(raid: raid)
        try store.addMember(Member(id: me.memberID, raidID: raidID, nickname: me.nickname, role: role, joinedAt: .now))
        LocalIdentity.currentRaidID = raidID
        refreshListeners()
        scheduleFlush(raidID: raidID)
        return raidID
        #else
        throw SyncError.unavailable
        #endif
    }

    /// Removes me from a raid on the server, then deletes it locally.
    func leave(_ raidID: UUID) async {
        #if canImport(FirebaseCore)
        if isAvailable, store.raid(raidID)?.isMultiplayer == true {
            let uid = LocalIdentity.current.memberID
            stopListening(raidID)
            try? await db.collection("raids").document(raidID.uuidString).collection("members").document(uid).delete()
        }
        #endif
        try? store.deleteRaidLocally(raidID)
    }

    // MARK: Upload

    /// Coalesces bursts of changes into one upload.
    func scheduleFlush(raidID: UUID?) {
        guard isAvailable else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    func flush() async {
        #if canImport(FirebaseCore)
        guard isAvailable else { return }
        let uid = LocalIdentity.current.memberID
        lastError = nil

        for raid in store.pendingRaids() {
            let ref = db.collection("raids").document(raid.id.uuidString)
            do {
                if raid.ownerID == uid {
                    var data = Self.data(for: raid)
                    data.removeValue(forKey: "ownerId")
                    try await ref.updateData(data)
                } else if raid.status == .won || raid.status == .lost {
                    try await ref.updateData(["status": raid.status.rawValue])
                }
                store.markRaidSynced(raid.id)
            } catch {
                handle(error) { store.markRaidSynced(raid.id) }
            }
        }

        for member in store.pendingMembers() {
            guard member.id == uid else {
                store.markMemberSynced(raidID: member.raidID, memberID: member.id)
                continue
            }
            let ref = db.collection("raids").document(member.raidID.uuidString).collection("members").document(member.id)
            do {
                try await ref.setData(Self.data(for: member), merge: true)
                store.markMemberSynced(raidID: member.raidID, memberID: member.id)
            } catch {
                handle(error) { store.markMemberSynced(raidID: member.raidID, memberID: member.id) }
            }
        }

        for (task, deleted) in store.pendingTasks() {
            let ref = db.collection("raids").document(task.raidID.uuidString).collection("tasks").document(task.id.uuidString)
            do {
                var data = Self.data(for: task)
                data["deleted"] = deleted
                try await ref.setData(data, merge: true)
                store.markTaskSynced(task.id)
            } catch {
                handle(error) { store.markTaskSynced(task.id) }
            }
        }

        for attack in store.pendingAttacks() {
            let ref = db.collection("raids").document(attack.raidID.uuidString).collection("attacks").document(attack.id.uuidString)
            do {
                try await ref.setData(Self.data(for: attack))
                store.markAttackSynced(attack.id)
            } catch {
                // A retry of an attack that already landed is an "update", which the rules deny.
                if (try? await ref.getDocument())?.exists == true {
                    store.markAttackSynced(attack.id)
                } else {
                    handle(error) { store.markAttackSynced(attack.id) }
                }
            }
        }
        #endif
    }

    #if canImport(FirebaseCore)
    /// Permission errors will never succeed on retry, so drop them; keep everything else pending.
    private func handle(_ error: Error, dropping drop: () -> Void) {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            drop()
        }
        lastError = error.localizedDescription
    }
    #endif

    // MARK: Download

    /// Listens to every multiplayer raid I'm in.
    func refreshListeners() {
        #if canImport(FirebaseCore)
        guard isAvailable else { return }
        let wanted = Set(store.raids().filter { $0.isMultiplayer && $0.inviteCode != nil }.map(\.id))
        for id in listeners.keys where !wanted.contains(id) { stopListening(id) }
        for id in wanted where listeners[id] == nil { startListening(id) }
        #endif
    }

    #if canImport(FirebaseCore)
    private func startListening(_ raidID: UUID) {
        let raidRef = db.collection("raids").document(raidID.uuidString)
        var registrations: [any ListenerRegistration] = []

        registrations.append(raidRef.addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot, let raid = Self.raid(from: snapshot) else { return }
                self.store.mergeRemote(raid: raid)
                self.didMergeRemote(raidID)
            }
        })

        registrations.append(raidRef.collection("members").addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                for change in snapshot.documentChanges {
                    if change.type == .removed {
                        self.store.removeRemoteMember(raidID: raidID, memberID: change.document.documentID)
                    } else if let member = Self.member(from: change.document, raidID: raidID) {
                        self.store.mergeRemote(member: member)
                    }
                }
                self.didMergeRemote(raidID)
            }
        })

        registrations.append(raidRef.collection("tasks").addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                for change in snapshot.documentChanges where change.type != .removed {
                    if let task = Self.task(from: change.document, raidID: raidID) {
                        self.store.mergeRemote(task: task, deleted: change.document.data()["deleted"] as? Bool ?? false)
                    }
                }
                self.didMergeRemote(raidID)
            }
        })

        registrations.append(raidRef.collection("attacks").addSnapshotListener { [weak self] snapshot, _ in
            MainActor.assumeIsolated {
                guard let self, let snapshot else { return }
                for change in snapshot.documentChanges where change.type == .added {
                    if let attack = Self.attack(from: change.document, raidID: raidID) {
                        self.store.mergeRemote(attack: attack)
                    }
                }
                try? self.store.settleOutcome(raidID)
                self.didMergeRemote(raidID)
            }
        })

        listeners[raidID] = registrations
    }

    private func stopListening(_ raidID: UUID) {
        listeners[raidID]?.forEach { $0.remove() }
        listeners[raidID] = nil
    }
    #endif

    private var refreshTask: Task<Void, Never>?

    /// Widgets and the Live Activity update at most once per second during bursts.
    private func didMergeRemote(_ raidID: UUID) {
        refreshTask?.cancel()
        refreshTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            GameActions.reloadSystemSurfaces()
            #if os(iOS)
            LiveActivityController.sync(raidID: raidID)
            #endif
            scheduleFlush(raidID: raidID)
        }
    }
}

// MARK: - Invite codes

enum InviteCode {
    /// No 0/O or 1/I, so codes are easy to read aloud.
    static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func generate(length: Int = 6) -> String {
        String((0..<length).map { _ in alphabet.randomElement()! })
    }

    static func normalize(_ raw: String) -> String {
        raw.uppercased().filter { alphabet.contains($0) }
    }
}

// MARK: - Firestore mapping

#if canImport(FirebaseCore)
extension SyncEngine {
    nonisolated static func data(for raid: Raid) -> [String: Any] {
        var data: [String: Any] = [
            "name": raid.name,
            "bossName": raid.bossName,
            "ownerId": raid.ownerID,
            "createdAt": Timestamp(date: raid.createdAt),
            "deadline": Timestamp(date: raid.deadline),
            "status": raid.status.rawValue,
        ]
        if let code = raid.inviteCode { data["inviteCode"] = code }
        if let started = raid.startedAt { data["startedAt"] = Timestamp(date: started) }
        if let hp = raid.lockedMaxHP { data["lockedMaxHP"] = hp }
        return data
    }

    nonisolated static func raid(from snapshot: DocumentSnapshot) -> Raid? {
        guard let d = snapshot.data(), let id = UUID(uuidString: snapshot.documentID),
              let deadline = (d["deadline"] as? Timestamp)?.dateValue() else { return nil }
        return Raid(
            id: id, name: d["name"] as? String ?? "", bossName: d["bossName"] as? String ?? "",
            ownerID: d["ownerId"] as? String ?? "",
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            deadline: deadline,
            startedAt: (d["startedAt"] as? Timestamp)?.dateValue(),
            lockedMaxHP: d["lockedMaxHP"] as? Int,
            status: RaidStatus(rawValue: d["status"] as? String ?? "") ?? .planning,
            inviteCode: d["inviteCode"] as? String,
            isMultiplayer: true
        )
    }

    nonisolated static func data(for member: Member) -> [String: Any] {
        var data: [String: Any] = [
            "nickname": member.nickname,
            "joinedAt": Timestamp(date: member.joinedAt),
            "role": member.role?.rawValue ?? NSNull(),
            "activeFocusSince": member.activeFocusSince.map { Timestamp(date: $0) } ?? NSNull(),
        ]
        data["updatedAt"] = FieldValue.serverTimestamp()
        return data
    }

    nonisolated static func member(from doc: DocumentSnapshot, raidID: UUID) -> Member? {
        guard let d = doc.data() else { return nil }
        return Member(
            id: doc.documentID, raidID: raidID, nickname: d["nickname"] as? String ?? "?",
            role: (d["role"] as? String).flatMap(Role.init(rawValue:)),
            joinedAt: (d["joinedAt"] as? Timestamp)?.dateValue() ?? .now,
            activeFocusSince: (d["activeFocusSince"] as? Timestamp)?.dateValue()
        )
    }

    nonisolated static func data(for task: RaidTask) -> [String: Any] {
        [
            "title": task.title,
            "size": task.size.rawValue,
            "assigneeId": task.assigneeID ?? NSNull(),
            "createdAt": Timestamp(date: task.createdAt),
            "completedAt": task.completedAt.map { Timestamp(date: $0) } ?? NSNull(),
            "completedBy": task.completedBy ?? NSNull(),
            "sortIndex": task.sortIndex,
        ]
    }

    nonisolated static func task(from doc: DocumentSnapshot, raidID: UUID) -> RaidTask? {
        guard let d = doc.data(), let id = UUID(uuidString: doc.documentID) else { return nil }
        return RaidTask(
            id: id, raidID: raidID, title: d["title"] as? String ?? "",
            size: TaskSize(rawValue: d["size"] as? String ?? "") ?? .m,
            assigneeID: d["assigneeId"] as? String,
            createdAt: (d["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            completedAt: (d["completedAt"] as? Timestamp)?.dateValue(),
            completedBy: d["completedBy"] as? String,
            sortIndex: d["sortIndex"] as? Int ?? 0
        )
    }

    nonisolated static func data(for attack: Attack) -> [String: Any] {
        var data: [String: Any] = [
            "memberId": attack.memberID,
            "damage": attack.damage,
            "createdAt": Timestamp(date: attack.createdAt),
            "serverCreatedAt": FieldValue.serverTimestamp(),
            "localDay": attack.localDay,
        ]
        switch attack.kind {
        case .task(let taskID):
            data["kind"] = "task"
            data["taskId"] = taskID.uuidString
        case .focus(let seconds):
            data["kind"] = "focus"
            data["durationSeconds"] = seconds
        }
        return data
    }

    nonisolated static func attack(from doc: DocumentSnapshot, raidID: UUID) -> Attack? {
        guard let d = doc.data(), let id = UUID(uuidString: doc.documentID),
              let memberID = d["memberId"] as? String, let damage = d["damage"] as? Int else { return nil }
        let kind: AttackKind
        if d["kind"] as? String == "task", let taskID = (d["taskId"] as? String).flatMap(UUID.init(uuidString:)) {
            kind = .task(taskID)
        } else {
            kind = .focus(seconds: d["durationSeconds"] as? Int ?? 0)
        }
        let created = (d["createdAt"] as? Timestamp)?.dateValue() ?? .now
        return Attack(
            id: id, raidID: raidID, memberID: memberID, kind: kind, damage: damage, createdAt: created,
            localDay: d["localDay"] as? String ?? LocalDay.key(for: created)
        )
    }
}
#endif
