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
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(Entitlements.self) private var entitlements
    @State private var paywall: PaywallReason?
    @State private var manageSubscription = false
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true
    @AppStorage("identity.nickname", store: AppGroup.defaults) private var nickname = ""

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
                youSection
                premiumSection
                gameCenterSection
                otherRaidsSection
                dangerSection
                extraSections
            }
            .headerProminence(.increased)
            .dungeonScreen()
            .readableContentWidth()
            .navigationTitle("Party")
            .toolbar {
                Menu("New", systemImage: "plus") {
                    Button("New raid", systemImage: "plus") { environment.showCreateRaid = true }
                    Button("Join with code", systemImage: "person.badge.plus") { showJoin = true }
                        .disabled(!sync.isAvailable)
                }
            }
            .onAppear { gameCenter.showAccessPoint(true) }
            .onDisappear { gameCenter.showAccessPoint(false) }
            .sheet(isPresented: $showJoin) { JoinRaidView() }
            .sheet(isPresented: $showReport) { ReportView(raidID: raidID) }
            // Screen level, not on the Premium row: sheets attached to list rows get
            // dismissed when the list refreshes, which closed the paywall right away.
            .sheet(item: $paywall) { PaywallView(reason: $0.block) }
            .manageSubscriptionsSheet(isPresented: $manageSubscription, subscriptionGroupID: Entitlements.subscriptionGroupID)
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
                            Text(role.title).font(.caption).foregroundStyle(.readableSecondary)
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
                            .font(.caption)
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

    private var youSection: some View {
        Section {
            TextField("Nickname", text: $nickname)
                .onSubmit { try? DDStore.shared.renameMember(me, to: nickname); GameActions.changed(raidID) }
            if let mine = members.first(where: { $0.memberID == me }) {
                RolePickerRow(role: Binding(
                    get: { mine.model.role },
                    set: { role in
                        try? DDStore.shared.updateMember(raidID: raidID, memberID: me) { $0.role = role }
                        GameActions.changed(raidID)
                    }
                ))
            }
            Toggle("Haptics", isOn: $hapticsOn)
            PhaseAlertsSetting()
        } header: {
            Text("You").font(.headline)
        }
        .dungeonRow()
    }

    private var premiumSection: some View {
        Section {
            if entitlements.isPremium {
                Label("Premium is active", systemImage: "crown.fill")
                Button("Manage subscription", systemImage: "creditcard") { manageSubscription = true }
            } else {
                Text("Free plan: 1 active solo boss, join any raid. Premium adds group raids and unlimited bosses.")
                    .readableFootnote()
                Button("See Premium", systemImage: "crown") { paywall = PaywallReason(block: nil) }
                    .accessibilityIdentifier("partySeePremium")
            }
        } header: {
            Text("Premium").font(.headline)
        }
        .dungeonRow()
    }

    private var gameCenterSection: some View {
        Section {
            if gameCenter.isAuthenticated {
                Label {
                    Text("Signed in as \(gameCenter.displayName ?? "")")
                } icon: {
                    Image(systemName: "gamecontroller.fill")
                }
                Button("Achievements", systemImage: "trophy.fill") { gameCenter.openDashboard(.achievements) }
                Button("Leaderboards", systemImage: "list.number") { gameCenter.openDashboard(.leaderboards) }
            } else {
                Text("Sign in to Game Center to earn achievements and compare your damage with friends.")
                    .readableFootnote()
                Button("Sign in to Game Center", systemImage: "gamecontroller") { gameCenter.authenticate() }
                    .disabled(!gameCenter.isEnabled)
            }
        } header: {
            Text("Game Center").font(.headline)
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
                        Label(raid.isMultiplayer ? "Leave raid" : "Delete boss",
                              systemImage: raid.isMultiplayer ? "rectangle.portrait.and.arrow.right" : "trash")
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

    /// Debug tools (debug builds only).
    @ViewBuilder
    private var extraSections: some View {
        #if DEBUG
        DebugSection(raidID: raidID)
        #endif
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
