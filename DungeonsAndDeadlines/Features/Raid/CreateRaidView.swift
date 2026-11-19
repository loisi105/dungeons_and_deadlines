import SwiftUI
import GameCore
import DDPersistence
import DDDesign

struct CreateRaidView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync

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
                Section {
                    TextField("Project or deadline", text: $name)
                        .accessibilityIdentifier("raidNameField")
                    HStack {
                        TextField("Boss name", text: $bossName)
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
                } footer: {
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
                    RolePickerRow(role: $role)
                } footer: {
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

    private func create() {
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
    static func random() -> String { all.randomElement() ?? "Exam Dragon" }
}

#Preview { CreateRaidView().environment(SyncEngine()) }
