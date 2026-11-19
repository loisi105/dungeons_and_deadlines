import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDDesign

/// Toolbar menu to switch between bosses (each boss is a raid with its own tasks),
/// start a new one or join one. Native `Menu` + `Picker`, so it gets a checkmark for
/// the current boss, VoiceOver and the Large Content Viewer for free.
struct BossSwitcher: View {
    let currentRaidID: UUID

    @Environment(SyncEngine.self) private var sync
    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var raids: [RaidRecord]
    @Environment(AppEnvironment.self) private var environment
    @State private var showJoin = false

    var body: some View {
        Menu {
            Picker("Boss", selection: selection) {
                ForEach(raids) { raid in
                    Label {
                        Text(raid.bossName)
                        Text(subtitle(for: raid))
                    } icon: {
                        Image(systemName: symbol(for: raid.status))
                    }
                    .tag(raid.id)
                }
            }
            .pickerStyle(.inline)
            Section {
                Button("New boss…", systemImage: "plus") { environment.showCreateRaid = true }
                    .accessibilityIdentifier("newBossButton")
                if sync.isAvailable {
                    Button("Join with code…", systemImage: "person.badge.plus") { showJoin = true }
                }
            }
        } label: {
            Label("Switch boss", systemImage: "rectangle.stack.fill")
        }
        .accessibilityIdentifier("bossSwitcher")
        .sheet(isPresented: $showJoin) { JoinRaidView() }
    }

    private var selection: Binding<UUID> {
        Binding(get: { currentRaidID }, set: { LocalIdentity.currentRaidID = $0 })
    }

    private func subtitle(for raid: RaidRecord) -> String {
        let status: String = switch raid.status {
        case .planning: String(localized: "Planning")
        case .active: String(localized: "\(DDStore.shared.bossState(raid.id)?.percent ?? 100)% HP")
        case .won: String(localized: "Defeated")
        case .lost: String(localized: "Survived")
        }
        return "\(raid.name) · \(status)"
    }

    private func symbol(for status: RaidStatus) -> String {
        switch status {
        case .planning: "map"
        case .active: "flame.fill"
        case .won: "trophy.fill"
        case .lost: "flag.slash"
        }
    }
}
