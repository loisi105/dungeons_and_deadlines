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
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true
    @AppStorage("identity.nickname", store: AppGroup.defaults) private var nickname = ""

    @Query private var raids: [RaidRecord]
    @Query private var members: [MemberRecord]
    @Query(sort: \RaidRecord.createdAt, order: .reverse) private var allRaids: [RaidRecord]

    @State private var showCreate = false
    @State private var showJoin = false
    @State private var confirmLeave = false
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
                otherRaidsSection
                dangerSection
                extraSections
            }
            .headerProminence(.increased)
            .dungeonScreen()
            .navigationTitle("Party")
            .toolbar {
                Menu("New", systemImage: "plus") {
                    Button("New raid", systemImage: "plus") { showCreate = true }
                    Button("Join with code", systemImage: "person.badge.plus") { showJoin = true }
                        .disabled(!sync.isAvailable)
                }
            }
            .sheet(isPresented: $showCreate) { CreateRaidView() }
            .sheet(isPresented: $showJoin) { JoinRaidView() }
            .sheet(isPresented: $showReport) { ReportView(raidID: raidID) }
            .confirmationDialog("Leave this raid?", isPresented: $confirmLeave, titleVisibility: .visible) {
                Button("Leave and remove from this phone", role: .destructive) {
                    Task { await sync.leave(raidID) }
                }
            } message: {
                Text("Its tasks and hits are removed from this phone. Teammates keep their copy.")
            }
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
        } header: {
            Text("Invite")
        } footer: {
            Text("Up to 5 people per raid.").readableFootnote()
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
        } header: {
            Text("You").font(.headline)
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
                }
            } header: {
                Text("Other raids").font(.headline)
            }
            .dungeonRow()
        }
    }

    private var dangerSection: some View {
        Section {
            Button("Leave raid", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                confirmLeave = true
            }
        }
        .dungeonRow()
    }

    /// Hook for later milestones (debug tools).
    @ViewBuilder
    private var extraSections: some View {
        EmptyView()
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
