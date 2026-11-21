import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDDesign

struct CreateRaidView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync
    @Environment(Entitlements.self) private var entitlements
    @State private var paywall: PaywallReason?
    @State private var removing: Raid?
    /// Observed, so the free-plan notice updates as soon as a boss is deleted.
    @Query private var allRaids: [RaidRecord]

    @State private var name = ""
    @State private var bossName = BossNames.random()
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    @State private var multiplayer = false
    @State private var role: Role?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var choosingBoss = false
    /// The Apple sign-in offer is shown once, after the first group raid.
    @State private var offeringAppleSync = false
    @AppStorage("settings.appleSyncOffered", store: AppGroup.defaults) private var appleSyncOffered = false
    private enum Field { case name, boss }
    @FocusState private var focus: Field?
    /// The boss name the sheet opened with, to tell whether the user changed anything.
    @State private var initialBossName = ""
    /// Bumped to rebuild the Mode picker, so it snaps back to Solo after a free player picks Raid.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The boss preview grows a little with the text size, up to 72pt.
    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 44

    var body: some View {
        NavigationStack {
            Form {
                if let block = currentBlock {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(noticeTitle(block))
                                .font(.headline)
                            Text(noticeDetail(block))
                                .readableFootnote()
                            Button { paywall = PaywallReason(block: block) } label: {
                                Text("See Premium").frame(maxWidth: .infinity)
                            }
                                .primaryActionStyle()
                                .accessibilityIdentifier("seePremiumButton")
                            if block == .soloLimitReached, let active = activeSoloRaid {
                                Button(role: .destructive) { removing = active } label: {
                                    Text("Delete \(active.bossName)…").frame(maxWidth: .infinity)
                                }
                                    .dangerActionStyle()
                                    .accessibilityIdentifier("deleteActiveBossButton")
                            }
                        }
                    }
                    .dungeonRow()
                }
                Section {
                    TextField("Project or deadline", text: $name, axis: .vertical)
                        .focused($focus, equals: .name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .onSubmit { focus = .boss }
                        .accessibilityIdentifier("raidNameField")
                }
                .dungeonRow()

                Section {
                    bossRow
                    if let locked = lockedBoss {
                        // The thumbnail's lock is hidden from VoiceOver, so this note says it.
                        Text("\(Image(systemName: "lock.fill")) \(Text(locked.title)) is a Premium boss. Free raids can fight the Clock, Dragon or Goblin.")
                            .readableFootnote()
                            .accessibilityIdentifier("premiumBossNote")
                    }
                }
                .dungeonRow()

                Section {
                    DatePicker("Deadline", selection: $deadline, in: Date.now.addingTimeInterval(3600)..., displayedComponents: [.date, .hourAndMinute])
                    Text("The boss gets angrier as the deadline gets closer.").readableFootnote()
                }
                .dungeonRow()

                Section {
                    Picker("Mode", selection: modeSelection) {
                        Text("Solo").tag(false)
                        raidModeLabel.tag(true)
                    }
                    .pickerStyle(.segmented)
                    // Free players can always tap Raid: it opens the paywall instead.
                    .disabled(entitlements.isPremium && !sync.isAvailable)
                    .accessibilityHint(entitlements.isPremium ? Text("") : Text("Group raids need Premium. Choosing Raid shows Premium."))
                    .accessibilityIdentifier("modePicker")
                    RolePickerRow(role: $role)
                    Group {
                        if !multiplayer {
                            // Said where a boss is made, so nobody is surprised by a new phone.
                            Text("Solo bosses are stored only on this device. Group raids sync through your account.")
                        }
                        if !entitlements.isPremium {
                            Text("Group raids for up to 5 come with Premium. Joining a friend's raid stays free.")
                        } else if sync.isAvailable {
                            Text("A raid gets an invite code to share with your group.")
                        } else {
                            Text("Multiplayer needs Firebase; this build is solo only.")
                        }
                    }
                    .readableFootnote()
                }
                .dungeonRow()

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                    .dungeonRow()
                }
            }
            .headerProminence(.increased)
            .scrollDismissesKeyboard(.interactively)
            .dungeonScreen()
            .onAppear {
                if initialBossName.isEmpty { initialBossName = bossName }
            }
            .sheet(item: $paywall) { PaywallView(reason: $0.block) }
            .sheet(isPresented: $choosingBoss) { BossPickerSheet(bossName: $bossName) }
            .sheet(isPresented: $offeringAppleSync, onDismiss: { dismiss() }) { AppleSyncOfferView() }
            .deleteBossConfirmation($removing)
            .navigationTitle("New raid")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCancelConfirm("Create", confirmIdentifier: "createRaidButton",
                                isEnabled: !trimmedName.isEmpty && !isSaving, hasChanges: !trimmedName.isEmpty || (!initialBossName.isEmpty && bossName != initialBossName), onConfirm: create)
        }
    }

    // MARK: Boss row

    /// Preview, name and buttons in one row; the full boss grid opens as a sheet.
    /// At accessibility sizes the field gets its own line so it isn't squeezed.
    @ViewBuilder private var bossRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    bossThumbnailButton
                    Spacer()
                    bossButtons
                }
                bossNameField
            }
            .padding(.vertical, 4)
        } else {
            HStack(spacing: 12) {
                bossThumbnailButton
                bossNameField
                bossButtons
            }
        }
    }

    /// Dice and grid side by side; each keeps a 44pt hit area.
    private var bossButtons: some View {
        HStack(spacing: 0) {
            randomBossButton
            chooseBossButton
        }
    }

    /// Same action as the grid button, so VoiceOver skips it.
    private var bossThumbnailButton: some View {
        Button { choosingBoss = true } label: {
            BossThumbnail(kind: BossNames.kind(forName: bossName), isLocked: lockedBoss != nil, size: min(thumbnailSize, 72))
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private var bossNameField: some View {
        TextField("Boss name", text: $bossName, axis: .vertical)
            .focused($focus, equals: .boss)
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .onSubmit { focus = nil }
            .accessibilityIdentifier("bossNameField")
    }

    private var randomBossButton: some View {
        Button {
            bossName = BossNames.random(isPremium: entitlements.isPremium)
        } label: {
            Image(systemName: "dice")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Random boss name")
    }

    private var chooseBossButton: some View {
        Button { choosingBoss = true } label: {
            Image(systemName: "square.grid.2x2")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Choose boss")
        .accessibilityIdentifier("chooseBossButton")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Segmented pickers show text only, so the Premium mark is in the label.
    /// At accessibility sizes it's dropped to fit; the hint and footnote still say it.
    private var raidModeLabel: Text {
        if entitlements.isPremium { return Text("Raid (up to 5)") }
        return dynamicTypeSize.isAccessibilitySize ? Text("Raid") : Text("Raid · Premium")
    }

    /// Choosing Raid on the free plan stays on Solo and offers Premium right away. The binding
    /// keeps `multiplayer` false, so the control redraws on Solo (checked by the UI test). Don't
    /// force it with `.id()`: rebuilding the picker made the accessibility audit flag the rows below it.
    private var modeSelection: Binding<Bool> {
        Binding {
            multiplayer
        } set: { wantsRaid in
            if wantsRaid && !entitlements.isPremium {
                paywall = PaywallReason(block: .multiplayerRequiresPremium)
            } else {
                multiplayer = wantsRaid
            }
        }
    }

    /// The Premium boss the current name turns into, if the player is on the free plan.
    /// Only creating is gated; joined and existing raids keep any look.
    private var lockedBoss: BossKind? {
        guard let kind = BossNames.kind(forName: bossName), entitlements.block(bossIsFree: kind.isFree) != nil else { return nil }
        return kind
    }

    private func noticeTitle(_ block: PlanLimits.Block) -> LocalizedStringKey {
        switch block {
        case .multiplayerRequiresPremium: "Group raids are Premium"
        case .soloLimitReached: "Free plan: 1 active solo boss"
        case .premiumBoss: "Premium bosses"
        }
    }

    private func noticeDetail(_ block: PlanLimits.Block) -> LocalizedStringKey {
        switch block {
        case .multiplayerRequiresPremium: "Joining a friend's raid stays free."
        case .soloLimitReached: "Finish or delete your current boss, or go Premium for unlimited bosses."
        case .premiumBoss: "Free raids can fight the Clock, Dragon or Goblin. Premium unlocks all \(BossKind.allCases.count)."
        }
    }

    /// The unfinished solo boss that uses up the free slot.
    private var activeSoloRaid: Raid? {
        let me = LocalIdentity.current.memberID
        return allRaids.map(\.model).first { !$0.isMultiplayer && $0.ownerID == me && ($0.status == .planning || $0.status == .active) }
    }

    /// Free-plan limit that applies to the current choice, if any.
    private var currentBlock: PlanLimits.Block? {
        entitlements.block(createMultiplayer: multiplayer, raids: allRaids.map(\.model), playerID: LocalIdentity.current.memberID)
    }

    private func create() {
        if let block = currentBlock {
            paywall = PaywallReason(block: block)
            return
        }
        if lockedBoss != nil {
            paywall = PaywallReason(block: .premiumBoss)
            return
        }
        isSaving = true
        errorMessage = nil
        let boss = bossName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSaving = false }
            do {
                let raid = try DDStore.shared.createRaid(
                    name: trimmedName, bossName: boss.isEmpty ? BossNames.random(isPremium: entitlements.isPremium) : boss,
                    deadline: deadline, multiplayer: multiplayer, owner: LocalIdentity.current, role: role
                )
                if multiplayer { try await sync.publish(raid) }
                // First group raid: offer to tie the account to Apple so it follows the player.
                if multiplayer, !sync.isAppleLinked, !appleSyncOffered {
                    appleSyncOffered = true
                    offeringAppleSync = true
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum BossNames {
    /// A name with a random look: any of the 12 on Premium, only the free looks otherwise.
    /// UI tests always get the longest free name, the worst case for layout.
    static func random(isPremium: Bool = false) -> String {
        if LaunchOptions.isUITesting { return "Unfinished Citation Goblin" }
        let kinds = isPremium ? BossKind.allCases : BossKind.freeKinds
        return random(for: kinds.randomElement() ?? .dragon)
    }

    /// A name that shows this boss's look.
    static func random(for kind: BossKind) -> String {
        kind.suggestedNames.randomElement() ?? kind.rawValue
    }

    /// The boss a name turns into: the same trimmed name that create() saves.
    /// An empty name is no boss yet.
    static func kind(forName bossName: String) -> BossKind? {
        let name = bossName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : BossKind.forName(name)
    }
}

#Preview { CreateRaidView().environment(SyncEngine()) }

/// Identifiable wrapper so the paywall can be shown with `.sheet(item:)`.
struct PaywallReason: Identifiable {
    let block: PlanLimits.Block?
    var id: String { block?.rawValue ?? "upgrade" }
}
