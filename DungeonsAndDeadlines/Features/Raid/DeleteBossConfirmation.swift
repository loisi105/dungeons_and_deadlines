import SwiftUI
import GameCore
import DDPersistence
import DDDesign

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

extension Raid {
    /// Leaving a group raid shows an exit; deleting a solo boss shows a trash can.
    var removalSymbol: String { isMultiplayer ? "rectangle.portrait.and.arrow.right" : "trash" }
}

/// Swipe, long press and VoiceOver actions that remove a raid from a list row.
private struct RaidRowActions: ViewModifier {
    let raid: Raid
    @State private var removing: Raid?

    private var title: LocalizedStringKey { raid.isMultiplayer ? "Leave raid" : "Delete boss" }

    func body(content: Content) -> some View {
        content
            // The Quest Log's row insets: iOS puts a swipe button's name below it, not
            // inside, once the row gets tall.
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 16))
            // Styled like the Quest Log's swipe buttons. No destructive role: it would
            // animate the row away before the player confirms.
            .swipeActions(edge: .trailing) {
                Button { removing = raid } label: {
                    Label(raid.isMultiplayer ? "Leave" : "Delete", systemImage: "\(raid.removalSymbol).fill")
                        .labelStyle(.titleAndIcon)
                }
                .tint(Theme.dangerTop)
            }
            .contextMenu {
                Button(title, systemImage: raid.removalSymbol, role: .destructive) { removing = raid }
            }
            .accessibilityActions {
                Button(title) { removing = raid }
            }
            // On the row, so the dialog opens next to it.
            .deleteBossConfirmation($removing)
    }
}

extension View {
    func raidRowActions(_ raid: Raid) -> some View {
        modifier(RaidRowActions(raid: raid))
    }

    func deleteBossConfirmation(_ raid: Binding<Raid?>) -> some View {
        modifier(DeleteBossConfirmation(raid: raid))
    }
}
