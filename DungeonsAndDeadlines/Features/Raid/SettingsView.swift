import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// Everything about the player and the app, as opposed to the raid itself (that stays on the
/// Party tab): profile, account, Premium, Game Center, alerts and focus blocking.
struct SettingsView: View {
    let raidID: UUID

    @Environment(SyncEngine.self) private var sync
    @Environment(GameCenterService.self) private var gameCenter
    @Environment(Entitlements.self) private var entitlements
    @State private var paywall: PaywallReason?
    @State private var manageSubscription = false
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true
    @AppStorage("identity.nickname", store: AppGroup.defaults) private var nickname = ""
    @FocusState private var nicknameFocused: Bool
    /// The class shown in the row. Plain state that is copied to and from the store: a binding that
    /// read the database record directly made the pushed Class list spin at 100% CPU.
    @State private var role: Role?
    @State private var roleLoaded = false
    @Query private var members: [MemberRecord]

    init(raidID: UUID) {
        self.raidID = raidID
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID }, sort: \MemberRecord.joinedAt)
    }

    private var me: String { LocalIdentity.current.memberID }
    private var storedRole: Role? { members.first { $0.memberID == me }?.model.role }

    var body: some View {
        List {
            profileSection
            if sync.isAvailable { accountSection }
            premiumSection
            gameCenterSection
            preferencesSection
            extraSections
        }
        .headerProminence(.increased)
        .scrollDismissesKeyboard(.interactively)
        .dungeonScreen()
        .readableContentWidth()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            role = storedRole
            roleLoaded = true
        }
        .onChange(of: role) { _, new in
            guard roleLoaded, new != storedRole else { return }
            try? DDStore.shared.updateMember(raidID: raidID, memberID: me) { $0.role = new }
            GameActions.changed(raidID)
        }
        // Screen level, not on the Premium row: sheets attached to list rows get
        // dismissed when the list refreshes, which closed the paywall right away.
        .sheet(item: $paywall) { PaywallView(reason: $0.block) }
        .manageSubscriptionsSheet(isPresented: $manageSubscription, subscriptionGroupID: Entitlements.subscriptionGroupID)
    }

    // MARK: Sections

    private var profileSection: some View {
        Section {
            TextField("Nickname", text: $nickname)
                .focused($nicknameFocused)
                .textContentType(.nickname)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(commitNickname)
                // Settings-style: the name is kept when you tap away or leave the screen, not only on Return.
                .onChange(of: nicknameFocused) { _, focused in if !focused { commitNickname() } }
                .onDisappear(perform: commitNickname)
            if members.contains(where: { $0.memberID == me }) {
                RolePickerRow(role: $role)
            }
        } header: {
            Text("Profile").font(.headline)
        }
        .dungeonRow()
    }

    private func commitNickname() {
        let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, members.first(where: { $0.memberID == me })?.nickname != name else { return }
        nickname = name
        try? DDStore.shared.renameMember(me, to: name)
        GameActions.changed(raidID)
    }

    /// Multiplayer account (only when multiplayer is available).
    private var accountSection: some View {
        Section {
            AppleSignInRow()
        } header: {
            Text("Account").font(.headline)
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
                Button { paywall = PaywallReason(block: nil) } label: {
                    Label("See Premium", systemImage: "crown").fixedSize(horizontal: false, vertical: true)
                }
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
                Button("Game Center", systemImage: "person.crop.circle") { gameCenter.openDashboard(.dashboard) }
                    .accessibilityHint(Text("Shows your Game Center profile and friends"))
                    .accessibilityIdentifier("gameCenterDashboardButton")
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

    private var preferencesSection: some View {
        Section {
            Toggle("Haptics", isOn: $hapticsOn)
                .sensoryFeedback(.selection, trigger: hapticsOn)
            PhaseAlertsSetting()
            FocusBlockingSetting()
        } header: {
            Text("Alerts & focus").font(.headline)
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
}
