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
    @Environment(\.dismiss) private var dismiss
    @Query private var tasks: [TaskRecord]
    @Query private var raids: [RaidRecord]
    @Query private var members: [MemberRecord]
    @State private var editing = false
    @State private var errorMessage: String?

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
                    Section("Completed") {
                        LabeledContent("By", value: name(task.completedBy) ?? "?")
                        LabeledContent("When") { Text(completedAt, format: .dateTime) }
                    }
                    .dungeonRow()
                }
            }
            .headerProminence(.increased)
            .dungeonScreen()
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if !task.isDone && raid?.status == .active {
                    Button {
                        do {
                            announcer.announceOwnHit(try GameActions.completeTask(task.id))
                        } catch {
                            errorMessage = error.localizedDescription
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
            .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        } else {
            ContentUnavailableView("Task deleted", systemImage: "trash")
        }
    }

    private func name(_ id: String?) -> String? {
        guard let id else { return nil }
        if id == LocalIdentity.current.memberID { return String(localized: "You") }
        return members.first { $0.memberID == id }?.nickname
    }
}
