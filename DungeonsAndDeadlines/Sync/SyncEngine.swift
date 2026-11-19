import Foundation
import GameCore
import DDPersistence

/// Multiplayer sync. Solo-only until M6 adds Firebase.
@MainActor
@Observable
final class SyncEngine {
    enum SyncError: LocalizedError {
        case unavailable
        var errorDescription: String? { String(localized: "Multiplayer isn't available yet.") }
    }

    var isAvailable: Bool { false }
    private(set) var lastError: String?

    func configure() {}
    func appDidBecomeActive() {}
    func scheduleFlush(raidID: UUID?) {}
    func publish(_ raid: Raid) async throws { throw SyncError.unavailable }
    func join(code: String, role: Role?) async throws -> UUID { throw SyncError.unavailable }
    func leave(_ raidID: UUID) async { try? DDStore.shared.deleteRaidLocally(raidID) }
}
