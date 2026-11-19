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

    var body: some View {
        NavigationStack {
            Form {
                if let block = currentBlock {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(block == .multiplayerRequiresPremium ? "Group raids are Premium" : "Free plan: 1 active solo boss")
                                .font(.headline)
                            Text(block == .multiplayerRequiresPremium
                                 ? "Joining a friend's raid stays free."
                                 : "Finish or delete your current boss, or go Premium for unlimited bosses.")
                                .readableFootnote()
                            Button("See Premium") { paywall = PaywallReason(block: block) }
                                .primaryActionStyle()
                                .accessibilityIdentifier("seePremiumButton")
                            if block == .soloLimitReached, let active = activeSoloRaid {
                                Button("Delete \(active.bossName)…", role: .destructive) { removing = active }
                                    .dangerActionStyle()
                                    .accessibilityIdentifier("deleteActiveBossButton")
                            }
                        }
                    }
                    .dungeonRow()
                }
                Section {
                    TextField("Project or deadline", text: $name, axis: .vertical)
                        .accessibilityIdentifier("raidNameField")
                    HStack {
                        TextField("Boss name", text: $bossName, axis: .vertical)
                            .accessibilityIdentifier("bossNameField")
                        Button {
                            bossName = BossNames.random()
                        } label: {
                            Image(systemName: "dice")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Random boss name")
                    }
                } header: {
                    Text("Raid")
                }
                .dungeonRow()

                Section {
                    DatePicker("Deadline", selection: $deadline, in: Date.now.addingTimeInterval(3600)..., displayedComponents: [.date, .hourAndMinute])
                    Text("The boss gets angrier as the deadline gets closer.").readableFootnote()
                }
                .dungeonRow()

                Section {
                    Picker("Mode", selection: $multiplayer) {
                        Text("Solo").tag(false)
                        Text("Raid (up to 5)").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!sync.isAvailable)
                    .accessibilityHint(entitlements.isPremium ? Text("") : Text("Group raids need Premium."))
                    RolePickerRow(role: $role)
                    Group {
                        if sync.isAvailable {
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
            .dungeonScreen()
            .sheet(item: $paywall) { PaywallView(reason: $0.block) }
            .deleteBossConfirmation($removing)
            .navigationTitle("New raid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty || isSaving)
                        .accessibilityIdentifier("createRaidButton")
                }
            }
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

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
        isSaving = true
        errorMessage = nil
        let boss = bossName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSaving = false }
            do {
                let raid = try DDStore.shared.createRaid(
                    name: trimmedName, bossName: boss.isEmpty ? BossNames.random() : boss,
                    deadline: deadline, multiplayer: multiplayer, owner: LocalIdentity.current, role: role
                )
                if multiplayer { try await sync.publish(raid) }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum BossNames {
    static let all = [
        "Deadline Clock", "Exam Dragon", "Thesis Hydra", "Slide Deck Golem", "Essay Wyrm",
        "Lab Report Ogre", "Group Project Kraken", "Citation Goblin", "Procrastination Wraith",
        "Midterm Mimic", "Wifi Phantom", "Syntax Spider", "Burnout Shroom", "Proctor Cyclops", "Homework Slime",
    ]
    /// UI tests always get the longest name, the worst case for layout.
    static func random() -> String {
        LaunchOptions.isUITesting ? "Procrastination Wraith" : (all.randomElement() ?? "Exam Dragon")
    }
}

#Preview { CreateRaidView().environment(SyncEngine()) }

/// Identifiable wrapper so the paywall can be shown with `.sheet(item:)`.
struct PaywallReason: Identifiable {
    let block: PlanLimits.Block?
    var id: String { block?.rawValue ?? "upgrade" }
}
