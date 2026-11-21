import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// Raid details, members, invite code, switching raids and settings.
struct RaidView: View {
    let raidID: UUID

    @Environment(SyncEngine.self) private var sync

    @Query private var raids: [RaidRecord]
    @Query private var members: [MemberRecord]
    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var allRaids: [RaidRecord]

    @Environment(AppEnvironment.self) private var environment
    @State private var showJoin = false
    @State private var removing: Raid?
    @State private var showReport = false

    init(raidID: UUID) {
        self.raidID = raidID
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID }, sort: \MemberRecord.joinedAt)
    }

    private var me: String { LocalIdentity.current.memberID }

    var body: some View {
        NavigationStack {
            List {
                if let raid = raids.first?.model {
                    raidSection(raid)
                    if raid.isMultiplayer { inviteSection(raid) }
                    membersSection(raid)
                }
                otherRaidsSection
                dangerSection
            }
            .headerProminence(.increased)
            .scrollDismissesKeyboard(.interactively)
            .dungeonScreen()
            .readableContentWidth()
            .navigationTitle("Raid")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { SettingsView(raidID: raidID) } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu("New", systemImage: "plus") {
                        Button("New raid", systemImage: "plus") { environment.showCreateRaid = true }
                        Button("Join with code", systemImage: "person.badge.plus") { showJoin = true }
                            .disabled(!sync.isAvailable)
                    }
                }
            }
            .sheet(isPresented: $showJoin) { JoinRaidView() }
            .sheet(isPresented: $showReport) { ReportView(raidID: raidID) }
            .deleteBossConfirmation($removing)
        }
    }

    // MARK: Sections

    private func raidSection(_ raid: Raid) -> some View {
        Section {
            InfoRow("Project", value: raid.name)
            InfoRow("Boss", value: raid.bossName)
            InfoRow("Deadline") { Text(raid.deadline, format: .dateTime.day().month().hour().minute()) }
            InfoRow("Status") { Text(statusTitle(raid.status)) }
            if raid.status == .won || raid.status == .lost {
                Button("See report", systemImage: "doc.text.magnifyingglass") { showReport = true }
            }
        }
        .dungeonRow()
    }

    private func inviteSection(_ raid: Raid) -> some View {
        Section {
            if let code = raid.inviteCode {
                InfoRow("Invite code") {
                    Text(code)
                        .font(.title3.monospaced().bold())
                        .textSelection(.enabled)
                        .accessibilityLabel(code.map(String.init).joined(separator: " "))
                }
                ShareLink(item: String(localized: "Join my raid against \(raid.bossName) in Dungeons & Deadlines! Code: \(code)")) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                }
            } else {
                Label("Waiting for an invite code. Check your connection.", systemImage: "wifi.exclamationmark")
                    .foregroundStyle(.readableSecondary)
            }
            Text("Up to 5 people per raid.").readableFootnote()
        } header: {
            Text("Invite").font(.headline)
        }
        .dungeonRow()
    }

    private func membersSection(_ raid: Raid) -> some View {
        Section {
            ForEach(members) { record in
                let member = record.model
                HStack {
                    Image(systemName: member.role?.symbol ?? "person.fill")
                        .frame(width: 28)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(member.id == me ? String(localized: "\(member.nickname) (you)") : member.nickname)
                        if let role = member.role {
                            Text(role.title).font(.subheadline).foregroundStyle(.readableSecondary)
                        }
                    }
                    Spacer()
                    if member.id == raid.ownerID {
                        Label("Leader", systemImage: "crown.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Raid leader")
                    }
                    if member.activeFocusSince != nil {
                        Label("Attacking", systemImage: "flame.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Members (\(members.count)/5)").font(.headline)
        }
        .dungeonRow()
    }

    @ViewBuilder
    private var otherRaidsSection: some View {
        let others = allRaids.filter { $0.id != raidID }
        if !others.isEmpty {
            Section {
                ForEach(others) { raid in
                    Button {
                        LocalIdentity.currentRaidID = raid.id
                    } label: {
                        RaidRow(raid: raid)
                    }
                    .foregroundStyle(.primary)
                    .swipeActions(edge: .trailing) {
                        Button(raid.isMultiplayer ? "Leave" : "Delete", systemImage: "trash", role: .destructive) {
                            removing = raid.model
                        }
                    }
                    .contextMenu {
                        Button(raid.isMultiplayer ? "Leave raid" : "Delete boss", systemImage: "trash", role: .destructive) {
                            removing = raid.model
                        }
                    }
                    .accessibilityActions {
                        Button(raid.isMultiplayer ? "Leave raid" : "Delete boss") { removing = raid.model }
                    }
                }
            } header: {
                Text("Other raids").font(.headline)
            }
            .dungeonRow()
        }
    }

    private var dangerSection: some View {
        Section {
            if let raid = raids.first?.model {
                VStack(alignment: .leading, spacing: 10) {
                    // Solid red pixel button, so it never reads like an ordinary row.
                    Button(role: .destructive) {
                        removing = raid
                    } label: {
                        // Icon and text as plain views: a `Label` here was reported by the audit as
                        // possibly clipped at large text sizes (it wraps fine; the audit can't tell).
                        HStack(spacing: 8) {
                            Image(systemName: raid.isMultiplayer ? "rectangle.portrait.and.arrow.right" : "trash")
                                .accessibilityHidden(true)
                            Text(raid.isMultiplayer ? "Leave raid" : "Delete boss")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .dangerActionStyle()
                    .accessibilityIdentifier("deleteCurrentBoss")
                    Text(raid.isMultiplayer
                         ? "Removes this raid from your phone. Your teammates keep fighting."
                         : "Deletes this boss with all its tasks and hits. This can't be undone.")
                        .readableFootnote()
                }
                .padding(.vertical, 4)
            }
        }
        .dungeonRow()
    }

    private func statusTitle(_ status: RaidStatus) -> LocalizedStringKey {
        switch status {
        case .planning: "Planning"
        case .active: "Fighting"
        case .won: "Victory"
        case .lost: "Defeat"
        }
    }
}
