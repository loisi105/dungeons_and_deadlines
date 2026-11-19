import SwiftUI
import GameCore
import DDPersistence

/// Asks before removing a boss. Solo bosses are deleted for good; multiplayer raids are
/// left (removed from this phone, teammates keep theirs).
struct DeleteBossConfirmation: ViewModifier {
    @Binding var raid: Raid?
    @Environment(SyncEngine.self) private var sync

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title,
            isPresented: Binding(get: { raid != nil }, set: { if !$0 { raid = nil } }),
            titleVisibility: .visible,
            presenting: raid
        ) { raid in
            Button(raid.isMultiplayer ? "Leave and remove from this phone" : "Delete boss", role: .destructive) {
                Task { await sync.leave(raid.id) }
            }
            .accessibilityIdentifier("confirmDeleteBoss")
            Button("Cancel", role: .cancel) {}
        } message: { raid in
            if raid.isMultiplayer {
                Text("Its tasks and hits are removed from this phone. Teammates keep their copy.")
            } else {
                Text("\(raid.bossName) (\(raid.name)), its tasks and hits are deleted. This can't be undone.")
            }
        }
    }

    private var title: String {
        guard let raid else { return "" }
        return raid.isMultiplayer ? String(localized: "Leave this raid?") : String(localized: "Delete \(raid.bossName)?")
    }
}

extension View {
    func deleteBossConfirmation(_ raid: Binding<Raid?>) -> some View {
        modifier(DeleteBossConfirmation(raid: raid))
    }
}
