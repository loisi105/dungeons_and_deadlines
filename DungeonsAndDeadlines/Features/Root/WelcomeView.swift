import SwiftUI
import SwiftData
import DDPersistence
import DDDesign

/// Shown when there's no current raid: create one, join one, or reopen a finished one.
struct WelcomeView: View {
    @Environment(SyncEngine.self) private var sync
    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var raids: [RaidRecord]
    @State private var showCreate = false
    @State private var showJoin = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        BossAvatar(phase: .calm)
                            .frame(maxWidth: .infinity)
                        Text("No boss yet")
                            .font(.title2.bold())
                        Text("Create a raid for a deadline. Plan its tasks, then start the fight.")
                            .foregroundStyle(.readableSecondary)
                    }
                    .padding(.vertical)
                }
                if !raids.isEmpty {
                    Section("Past raids") {
                        ForEach(raids) { raid in
                            Button {
                                LocalIdentity.currentRaidID = raid.id
                            } label: {
                                RaidRow(raid: raid)
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .headerProminence(.increased)
            .navigationTitle("Dungeons & Deadlines")
            .safeAreaInset(edge: .bottom) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        if sync.isAvailable {
                            Button {
                                showJoin = true
                            } label: {
                                Label("Join", systemImage: "person.badge.plus")
                                    .frame(maxWidth: .infinity)
                            }
                            .secondaryActionStyle()
                            .accessibilityHint("Join a friend's raid with an invite code.")
                        }
                        Button {
                            showCreate = true
                        } label: {
                            Label("New raid", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryActionStyle()
                        .accessibilityIdentifier("newRaidButton")
                    }
                    .controlSize(.large)
                    .padding()
                }
            }
            .sheet(isPresented: $showCreate) { CreateRaidView() }
            .sheet(isPresented: $showJoin) { JoinRaidView() }
        }
    }
}

struct RaidRow: View {
    let raid: RaidRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(raid.name).font(.headline)
            HStack {
                Label(raid.bossName, systemImage: "lizard.fill")
                Spacer()
                Text(statusText)
            }
            .font(.subheadline)
            .foregroundStyle(.readableSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var statusText: LocalizedStringKey {
        switch raid.status {
        case .planning: "Planning"
        case .active: "Fighting"
        case .won: "Victory"
        case .lost: "Defeat"
        }
    }
}
