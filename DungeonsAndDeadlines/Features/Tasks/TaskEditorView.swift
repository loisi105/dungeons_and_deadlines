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
                    LabeledContent("Damage", value: "\(config.baseDamage(for: size))")
                } header: {
                    Text("Size")
                } footer: {
                    Text("Be honest: bigger tasks hit harder, and teammates see the size.").readableFootnote()
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
            .dungeonScreen()
            .navigationTitle(isEditing ? "Edit task" : "New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmed.isEmpty)
                        .accessibilityIdentifier("saveTaskButton")
                }
            }
            .onAppear { titleFocused = !isEditing }
        }
        .presentationDetents([.medium, .large])
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }
    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        do {
            switch mode {
            case .add:
                try DDStore.shared.addTask(raidID: raidID, title: trimmed, size: size, assigneeID: assigneeID)
            case .edit(var task):
                task.title = trimmed
                task.size = size
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
