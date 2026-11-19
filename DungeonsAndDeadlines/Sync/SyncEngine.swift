import Foundation
import GameCore
import DDPersistence
import DDIntents
import DDSync

/// Multiplayer for the app: wraps `RaidSync` (DDKit) with sign-in, debounced uploads
/// and foreground polling. Talks to Firebase over REST (no SDK, so no launch cost).
///
/// Multiplayer is available when `GoogleService-Info.plist` is bundled, or with
/// `-useFirebaseEmulator`. Otherwise the app is solo-only. See firebase/README.md.
@MainActor
@Observable
final class SyncEngine {
    enum Status: Equatable {
        case unavailable
        case signingIn
        case ready
        case failed(String)
    }

    private(set) var status: Status = .unavailable
    private(set) var lastError: String?
    var isAvailable: Bool { status == .ready }

    /// How often the current raid is polled while the app is in the foreground.
    let pollInterval: Duration = .seconds(5)

    private var sync: RaidSync?
    private var flushTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var store: RaidStore { DDStore.shared }

    // MARK: Lifecycle

    /// Starts sign-in in the background; never blocks launch.
    func configure() {
        guard !LaunchOptions.isUITesting,
              let config = FirebaseConfig.load(useEmulator: LaunchOptions.useFirebaseEmulator) else { return }
        status = .signingIn
        Task { await signIn(config) }
    }

    private func signIn(_ config: FirebaseConfig) async {
        do {
            let auth = FirebaseAuthREST(config: config)
            let uid = try await auth.signIn()
            let old = LocalIdentity.current.memberID
            if old != uid {
                try store.migrateMemberID(from: old, to: uid)
                LocalIdentity.setMemberID(uid)
            }
            sync = RaidSync(store: store, transport: FirestoreREST(config: config, auth: auth), uid: uid)
            status = .ready
            startPolling()
            scheduleFlush(raidID: nil)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func appDidBecomeActive() {
        guard isAvailable else { return }
        startPolling()
        scheduleFlush(raidID: nil)
    }

    func appDidEnterBackground() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: Create, join, leave

    func publish(_ raid: Raid) async throws {
        guard let sync else { throw FirebaseError.notConfigured }
        try await sync.publish(raid)
        GameActions.reloadSystemSurfaces()
    }

    @discardableResult
    func join(code: String, role: Role?) async throws -> UUID {
        guard let sync else { throw FirebaseError.notConfigured }
        let raidID = try await sync.join(code: code, nickname: LocalIdentity.current.nickname, role: role)
        GameActions.reloadSystemSurfaces()
        return raidID
    }

    /// Leaves a multiplayer raid, or deletes a solo boss, on this phone.
    func leave(_ raidID: UUID) async {
        #if os(iOS)
        LiveActivityController.end(raidID: raidID)
        #endif
        if let sync {
            await sync.leave(raidID)
        } else {
            try? store.deleteRaidLocally(raidID)
        }
        GameActions.reloadSystemSurfaces()
    }

    // MARK: Upload

    /// Coalesces bursts of local changes into one upload.
    func scheduleFlush(raidID: UUID?) {
        guard let sync else { return }
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let errors = await sync.flush()
            self?.lastError = errors.first?.localizedDescription
        }
    }

    // MARK: Download

    private func startPolling() {
        guard pollTask == nil, sync != nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollCurrentRaid()
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(5))
            }
        }
    }

    private func pollCurrentRaid() async {
        guard let sync, let raid = store.currentRaid(), raid.isMultiplayer, raid.inviteCode != nil else { return }
        do {
            if try await sync.poll(raid.id) {
                GameActions.reloadSystemSurfaces()
                #if os(iOS)
                LiveActivityController.sync(raidID: raid.id)
                #endif
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
