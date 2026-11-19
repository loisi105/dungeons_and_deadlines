import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// Task list: swipe right to complete, context menu for everything else, drag to reorder.
struct TasksView: View {
    let raidID: UUID

    @Environment(Announcer.self) private var announcer
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true

    @Query private var raids: [RaidRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var members: [MemberRecord]

    @State private var editing: TaskEditorView.Mode?
    @State private var errorMessage: String?
    @State private var completedCount = 0
    @Namespace private var zoom

    init(raidID: UUID) {
        self.raidID = raidID
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
        _tasks = Query(filter: #Predicate<TaskRecord> { $0.raidID == raidID && $0.deletedAt == nil }, sort: [SortDescriptor(\TaskRecord.sortIndex), SortDescriptor(\TaskRecord.createdAt)])
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID }, sort: \MemberRecord.joinedAt)
    }

    private var raid: Raid? { raids.first?.model }
    private var open: [TaskRecord] { tasks.filter { !$0.isDone } }
    private var done: [TaskRecord] { tasks.filter(\.isDone) }
    private var config: DamageConfig { DDStore.shared.config }
    private var canComplete: Bool { raid?.status == .active }
    private var canEdit: Bool { raid?.status == .planning || raid?.status == .active }

    var body: some View {
        NavigationStack {
            taskList
                .navigationTitle("Tasks")
                .navigationDestination(for: UUID.self) { id in
                    TaskDetailView(taskID: id, raidID: raidID)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
                .toolbar { toolbar }
                .sheet(item: $editing) { mode in
                    TaskEditorView(raidID: raidID, mode: mode)
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: completedCount) { _, _ in hapticsOn }
                .alert("Couldn't do that", isPresented: errorBinding) {
                    Button("OK") { errorMessage = nil }
                } message: {
                    Text(errorMessage ?? "")
                }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var taskList: some View {
        List {
            planningSection
            openSection
            doneSection
        }
        .headerProminence(.increased)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if canEdit {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .primaryAction) {
                Button("Add task", systemImage: "plus") { editing = .add }
                    .accessibilityIdentifier("addTaskButton")
            }
        }
    }

    @ViewBuilder
    private var planningSection: some View {
        if let raid, raid.status == .planning {
            let hp = BossEngine.lockHP(tasks: tasks.map(\.model), config: config)
            Section {
                LabeledContent("Boss health when the fight starts") {
                    Text("\(hp) HP").monospacedDigit()
                }
            } footer: {
                Text("Small tasks deal \(config.smallTaskDamage), medium \(config.mediumTaskDamage), large \(config.largeTaskDamage) damage. Focus time covers the rest.").readableFootnote()
            }
        }
    }

    private var openSection: some View {
        Section {
            if open.isEmpty {
                Text(tasks.isEmpty ? "No tasks yet. Add the steps for this deadline." : "All tasks done!")
                    .foregroundStyle(.readableSecondary)
            }
            ForEach(open) { task in
                row(task).moveDisabled(!canEdit)
            }
            .onMove(perform: move)
        } header: {
            Text("Open (\(open.count))")
        }
    }

    @ViewBuilder
    private var doneSection: some View {
        if !done.isEmpty {
            Section("Done (\(done.count))") {
                ForEach(done) { task in row(task) }
            }
        }
    }

    @ViewBuilder
    private func row(_ record: TaskRecord) -> some View {
        let task = record.model
        NavigationLink(value: task.id) {
            TaskRow(task: task, damage: config.baseDamage(for: task.size), assignee: nickname(task.assigneeID), isLate: task.isLate(startedAt: raid?.startedAt))
        }
        .matchedTransitionSource(id: task.id, in: zoom)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !task.isDone && canComplete {
                Button("Complete", systemImage: "checkmark") { complete(task) }
                    .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            if !task.isDone && canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(task) }
            }
        }
        .contextMenu {
            if !task.isDone && canComplete {
                Button("Complete", systemImage: "checkmark.circle") { complete(task) }
            }
            if task.isDone {
                Button("Reopen", systemImage: "arrow.uturn.backward") { reopen(task) }
            }
            if canEdit {
                Button("Edit", systemImage: "pencil") { editing = .edit(task) }
                Menu("Assign to", systemImage: "person.crop.circle") {
                    Button("Nobody") { assign(task, to: nil) }
                    ForEach(members) { m in
                        Button(m.nickname) { assign(task, to: m.memberID) }
                    }
                }
            }
            if !task.isDone && canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(task) }
            }
        }
        .accessibilityActions {
            if !task.isDone && canComplete {
                Button("Complete task") { complete(task) }
            }
            if canEdit {
                Button("Edit task") { editing = .edit(task) }
            }
            if !task.isDone && canEdit {
                Button("Delete task", role: .destructive) { delete(task) }
            }
        }
        .accessibilityIdentifier("task-\(task.title)")
    }

    private func nickname(_ id: String?) -> String? {
        guard let id else { return nil }
        if id == LocalIdentity.current.memberID { return String(localized: "You") }
        return members.first { $0.memberID == id }?.nickname
    }

    // MARK: Actions

    private func complete(_ task: RaidTask) {
        do {
            let attack = try GameActions.completeTask(task.id)
            completedCount += 1
            announcer.announceOwnHit(attack)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reopen(_ task: RaidTask) {
        do { try DDStore.shared.reopenTask(task.id); GameActions.changed(raidID) } catch { errorMessage = error.localizedDescription }
    }

    private func delete(_ task: RaidTask) {
        do { try DDStore.shared.deleteTask(task.id); GameActions.changed(raidID) } catch { errorMessage = error.localizedDescription }
    }

    private func assign(_ task: RaidTask, to memberID: String?) {
        var updated = task
        updated.assigneeID = memberID
        do { try DDStore.shared.updateTask(updated); GameActions.changed(raidID) } catch { errorMessage = error.localizedDescription }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ids = open.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        do { try DDStore.shared.moveTasks(raidID: raidID, orderedIDs: ids); GameActions.changed(raidID) } catch { errorMessage = error.localizedDescription }
    }
}

struct TaskRow: View {
    let task: RaidTask
    let damage: Int
    let assignee: String?
    let isLate: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(task.isDone ? .green : .secondary)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                HStack(spacing: 6) {
                    if let assignee { Label(assignee, systemImage: "person.fill") }
                    if isLate { Label("Late", systemImage: "clock.badge.exclamationmark") }
                }
                .font(.caption)
                .foregroundStyle(.readableSecondary)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            SizeChip(task.size, damage: damage)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        var parts = [task.title, String(localized: task.size.title), String(localized: "\(damage) damage")]
        if task.isDone { parts.append(String(localized: "done")) }
        if let assignee { parts.append(String(localized: "assigned to \(assignee)")) }
        if isLate { parts.append(String(localized: "added after the fight started")) }
        return Text(parts.joined(separator: ", "))
    }
}
