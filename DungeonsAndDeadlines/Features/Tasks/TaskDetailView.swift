import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

struct TaskDetailView: View {
    let taskID: UUID
    let raidID: UUID

    @Environment(Announcer.self) private var announcer
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskRecord]
    @Query private var raids: [RaidRecord]
    @Query private var members: [MemberRecord]
    @State private var editing = false
    @State private var errorMessage: String?
    @State private var needsFightStart: RaidTask?

    init(taskID: UUID, raidID: UUID) {
        self.taskID = taskID
        self.raidID = raidID
        _tasks = Query(filter: #Predicate<TaskRecord> { $0.id == taskID })
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID })
    }

    var body: some View {
        if let record = tasks.first, record.deletedAt == nil {
            let task = record.model
            let raid = raids.first?.model
            List {
                Section {
                    Text(task.title)
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    LabeledContent("Size") { Text(task.size.title) }
                    LabeledContent("Damage", value: "\(DDStore.shared.config.baseDamage(for: task.size))")
                    LabeledContent("Assigned to", value: name(task.assigneeID) ?? String(localized: "Nobody"))
                    LabeledContent("Added") { Text(task.createdAt, style: .date) }
                    if task.isLate(startedAt: raid?.startedAt) {
                        Label("Added after the fight started", systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                    }
                }
                .dungeonRow()
                if let completedAt = task.completedAt {
                    Section {
                        LabeledContent("By", value: name(task.completedBy) ?? "?")
                        LabeledContent("When") { Text(completedAt, format: .dateTime) }
                    } header: {
                        Text("Completed").font(.headline)
                    }
                    .dungeonRow()
                }
            }
            .headerProminence(.increased)
            .dungeonScreen()
            .readableContentWidth()
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !task.isDone && (raid?.status == .active || raid?.status == .planning) {
                    Button {
                        if raid?.status == .planning {
                            needsFightStart = task
                        } else {
                            complete(task)
                        }
                    } label: {
                        Label("Complete task", systemImage: "checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionStyle()
                    .controlSize(.large)
                    .padding()
                }
            }
            .toolbar {
                if raid?.status == .planning || raid?.status == .active {
                    Button("Edit", systemImage: "pencil") { editing = true }
                }
            }
            .sheet(isPresented: $editing) { TaskEditorView(raidID: raidID, mode: .edit(task)) }
            .startFightPrompt(task: $needsFightStart, raid: raid) { complete($0) }
            .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("Task deleted", systemImage: "trash")
        }
    }

    private func complete(_ task: RaidTask) {
        do {
            let attack = try GameActions.completeTask(task.id)
            dismiss() // back to the list, then over to the boss for the attack
            environment.castTaskAttack(attack, task: task)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func name(_ id: String?) -> String? {
        guard let id else { return nil }
        if id == LocalIdentity.current.memberID { return String(localized: "You") }
        return members.first { $0.memberID == id }?.nickname
    }
}
