import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

struct TaskEditorView: View {
    enum Mode: Identifiable {
        case add
        case edit(RaidTask)
        var id: String {
            switch self {
            case .add: "add"
            case .edit(let task): task.id.uuidString
            }
        }
    }

    let raidID: UUID
    let mode: Mode

    @Environment(\.dismiss) private var dismiss
    @Query private var members: [MemberRecord]
    @State private var title = ""
    @State private var size: TaskSize = .m
    /// Base damage as typed. Picking a size pre-fills the recommended number; the number is what counts.
    @State private var damageText = String(DDStore.shared.config.baseDamage(for: .m))
    @State private var assigneeID: String?
    @State private var errorMessage: String?
    @FocusState private var titleFocused: Bool

    init(raidID: UUID, mode: Mode) {
        self.raidID = raidID
        self.mode = mode
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID }, sort: \MemberRecord.joinedAt)
        if case .edit(let task) = mode {
            _title = State(initialValue: task.title)
            _size = State(initialValue: task.size)
            _damageText = State(initialValue: String(DDStore.shared.config.baseDamage(of: task)))
            _assigneeID = State(initialValue: task.assigneeID)
        }
    }

    private var config: DamageConfig { DDStore.shared.config }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .focused($titleFocused)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .accessibilityIdentifier("taskTitleField")
                }
                .dungeonRow()
                Section {
                    Picker("Size", selection: $size) {
                        ForEach(TaskSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .sensoryFeedback(.selection, trigger: size)
                    .onChange(of: size) { damageText = String(config.baseDamage(for: size)) }
                    LabeledContent("Damage") {
                        TextField("Damage", text: $damageText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("taskDamageField")
                            .onChange(of: damageText) { damageText = damageText.filter(\.isNumber) }
                    }
                    Text("Maximum damage: \(config.maxCustomTaskDamage).").readableFootnote()
                } header: {
                    Text("Size and damage").font(.headline)
                }
                .dungeonRow()
                if members.count > 1 {
                    Section {
                        Picker("Assigned to", selection: $assigneeID) {
                            Text("Nobody").tag(String?.none)
                            ForEach(members) { m in
                                Text(m.nickname).tag(String?.some(m.memberID))
                            }
                        }
                    }
                    .dungeonRow()
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                    .dungeonRow()
                }
            }
            .headerProminence(.increased)
            .scrollDismissesKeyboard(.interactively)
            .dungeonScreen()
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCancelConfirm("Save", confirmIdentifier: "saveTaskButton", isEnabled: !trimmed.isEmpty, hasChanges: hasChanges, onConfirm: save)
            .onAppear { titleFocused = !isEditing }
        }
        .modifier(TaskSheetSizing())
    }

    /// Anything differs from what the sheet opened with.
    private var hasChanges: Bool {
        switch mode {
        case .add: !trimmed.isEmpty || size != .m || assigneeID != nil || damage != config.baseDamage(for: .m)
        case .edit(let task): trimmed != task.title || size != task.size || assigneeID != task.assigneeID || damage != config.baseDamage(of: task)
        }
    }

    /// What was typed, kept within 1...max; empty or 0 falls back to the recommendation.
    private var damage: Int {
        guard let typed = Int(damageText), typed > 0 else { return config.baseDamage(for: size) }
        return min(typed, config.maxCustomTaskDamage)
    }
    /// Nil when it equals the recommendation, so it keeps following the size.
    private var storedDamage: Int? { damage == config.baseDamage(for: size) ? nil : damage }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }
    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        do {
            switch mode {
            case .add:
                try DDStore.shared.addTask(raidID: raidID, title: trimmed, size: size, damage: storedDamage, assigneeID: assigneeID)
            case .edit(var task):
                task.title = trimmed
                task.size = size
                task.damage = storedDamage
                task.assigneeID = assigneeID
                try DDStore.shared.updateTask(task)
            }
            GameActions.changed(raidID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// iPhone: a half sheet that scrolls its content instead of resizing when you drag inside it.
/// iPad: a fixed-size form sheet. Detents made it jump and shrink while scrolling. The device type
/// decides, not the size class: a sheet on iPad reports a compact width.
private struct TaskSheetSizing: ViewModifier {
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.presentationSizing(.form)
        } else {
            content
                .presentationDetents([.medium, .large])
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
        }
    }
}
