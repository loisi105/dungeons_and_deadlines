import GameKit
import SwiftUI
import GameCore
import DDPersistence
import DDDesign

/// Game Center: sign-in, achievements, leaderboards and the Access Point.
/// Raids themselves sync through Firebase; Game Center is the Apple-native layer
/// for identity, bragging rights and the Games app.
///
/// Achievement and leaderboard IDs must exist in App Store Connect (docs/GAME_CENTER.md).
/// Until they do, reports fail quietly and the app works normally.
@MainActor
@Observable
final class GameCenterService {
    private(set) var isAuthenticated = false
    private(set) var displayName: String?
    private(set) var lastError: String?

    /// Achievement percentages already sent, so we only report changes.
    private var reported: [String: Double] {
        get { (AppGroup.defaults.dictionary(forKey: "gamecenter.reported") as? [String: Double]) ?? [:] }
        set { AppGroup.defaults.set(newValue, forKey: "gamecenter.reported") }
    }

    var isEnabled: Bool { !LaunchOptions.isUITesting }

    /// Starts Game Center sign-in. iOS shows its own sign-in sheet if needed.
    func authenticate() {
        guard isEnabled else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let viewController {
                    Self.present(viewController)
                    return
                }
                if let error {
                    self.lastError = error.localizedDescription
                }
                let player = GKLocalPlayer.local
                self.isAuthenticated = player.isAuthenticated
                self.displayName = player.isAuthenticated ? player.displayName : nil
                if player.isAuthenticated {
                    // Offer the Game Center name as the nickname if none is set yet.
                    if !LocalIdentity.hasNickname { LocalIdentity.setNickname(player.displayName) }
                    self.syncProgress()
                }
            }
        }
    }

    /// Shows or hides the floating Game Center button (top leading).
    func showAccessPoint(_ visible: Bool) {
        guard isEnabled else { return }
        GKAccessPoint.shared.location = .topLeading
        GKAccessPoint.shared.isActive = visible && isAuthenticated
    }

    func openDashboard(_ state: GKGameCenterViewControllerState) {
        guard isAuthenticated else { authenticate(); return }
        GKAccessPoint.shared.trigger(state: state) {}
    }

    private var pendingSync: Task<Void, Never>?

    /// Debounced `syncProgress`, for bursts of hits.
    func scheduleSync() {
        guard isEnabled, isAuthenticated else { return }
        pendingSync?.cancel()
        pendingSync = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.syncProgress()
        }
    }

    /// Recomputes progress from the local store and reports anything new.
    func syncProgress() {
        guard isEnabled, isAuthenticated else { return }
        let store = DDStore.shared
        let me = LocalIdentity.current.memberID
        let reports = store.raids().compactMap { store.report($0.id) }
        let progress = PlayerProgress.compute(memberID: me, reports: reports, config: store.config,
            lookOf: { BossKind.forName($0).rawValue }, lookCount: BossKind.allCases.count
        )

        var sent = reported
        let achievements: [GKAchievement] = progress.achievements.compactMap { achievement, percent in
            guard percent > (sent[achievement.rawValue] ?? 0) else { return nil }
            let a = GKAchievement(identifier: achievement.rawValue)
            a.percentComplete = percent
            a.showsCompletionBanner = true
            sent[achievement.rawValue] = percent
            return a
        }
        let scores = progress.scores
        Task {
            do {
                if !achievements.isEmpty {
                    try await GKAchievement.report(achievements)
                    reported = sent
                }
                for (board, score) in scores where score > 0 {
                    try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: [board.rawValue])
                }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private static func present(_ viewController: UIViewController) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(viewController, animated: true)
    }
}
