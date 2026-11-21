import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// Task list (native `List`): tap the checkbox or swipe right to complete, swipe left to
/// delete, long-press for more, drag to reorder in Edit mode. Before the fight starts,
/// completing asks to start the fight first.
struct TasksView: View {
    let raidID: UUID

    @Environment(Announcer.self) private var announcer
    @Environment(AppEnvironment.self) private var environment
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true

    @Query private var raids: [RaidRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var members: [MemberRecord]

    @State private var editing: TaskEditorView.Mode?
    @State private var errorMessage: String?
    @State private var completedCount = 0
    /// A task the player tried to complete while the raid is still planning.
    @State private var needsFightStart: RaidTask?
    /// Selection mode, like Mail: tapping an empty circle starts it; the bottom bar acts on the selection.
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var path: [UUID] = []
    /// Tasks waiting for the fight to start before a batch completes.
    @State private var pendingBatch: [UUID] = []
    @State private var confirmBatchDelete = false
    @State private var showResume = false
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
    /// Completing is offered while planning too; it asks to start the fight first.
    private var canComplete: Bool { raid?.status == .active || raid?.status == .planning }
    /// Tasks can always be added and edited; finished bosses collect follow-ups.
    private var canEdit: Bool { raid != nil }
    private var isFinished: Bool { raid?.status == .won || raid?.status == .lost }

    var body: some View {
        NavigationStack(path: $path) {
            taskList
                .confirmationDialog(
                    "Delete \(selection.count) tasks?", isPresented: $confirmBatchDelete, titleVisibility: .visible
                ) {
                    Button("Delete \(selection.count) Tasks", role: .destructive) { deleteSelected() }
                    Button("Cancel", role: .cancel) {}
                }
                .environment(\.editMode, $editMode)
                .navigationTitle(editMode.isEditing && !selection.isEmpty ? Text("\(selection.count) Selected") : Text("Quest Log"))
                .navigationSubtitle(raid.map { "\($0.bossName) · \($0.name)" } ?? "")
                .navigationDestination(for: UUID.self) { id in
                    TaskDetailView(taskID: id, raidID: raidID)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
                .toolbar { toolbar }
                .toolbarVisibility(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
                .onChange(of: editMode.isEditing) { _, isEditing in
                    if !isEditing { selection = [] }
                    environment.isSelectingTasks = isEditing
                }
                .onDisappear { environment.isSelectingTasks = false }
                .sheet(item: $editing) { mode in
                    TaskEditorView(raidID: raidID, mode: mode)
                }
                .sensoryFeedback(.success, trigger: completedCount) { _, _ in hapticsOn }
                .startFightPrompt(task: $needsFightStart, raid: raid) { task in
                    if pendingBatch.isEmpty {
                        complete(task)
                    } else {
                        let ids = pendingBatch
                        pendingBatch = []
                        completeBatch(ids)
                    }
                }
                .onChange(of: needsFightStart == nil) { _, none in if none { pendingBatch = [] } }
                .sheet(isPresented: $showResume) { ResumeFightView(raidID: raidID) }
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
        List(selection: $selection) {
            followUpSection
            planningSection
            openSections
            doneSection
        }
        // Like Notes: each group is one rounded container, rows split by separators.
        .listStyle(.insetGrouped)
        .headerProminence(.increased)
        .animation(.default, value: tasks.map { "\($0.id)\($0.isDone)" })
        .overlay {
            // The system's empty state, like Reminders and Notes.
            if tasks.isEmpty && !isFinished {
                ContentUnavailableView {
                    Label("No tasks yet", systemImage: "scroll")
                } description: {
                    Text("Add the steps for this deadline.")
                } actions: {
                    if canEdit {
                        // A real button, like the one on the Boss tab; plain text read as a caption.
                        Button("Add task", systemImage: "plus") { editing = .add }
                            .primaryActionStyle()
                            .accessibilityIdentifier("emptyAddTaskButton")
                    }
                }
            }
        }
        .dungeonScreen()
        .readableContentWidth(minMargin: 16)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { BossSwitcher(currentRaidID: raidID) }
        if editMode.isEditing {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Complete", systemImage: "checkmark.circle") { completeSelected() }
                    .disabled(selection.isEmpty || !canComplete)
                    .accessibilityIdentifier("completeSelectedButton")
                Spacer()
                Button("Delete", systemImage: "trash", role: .destructive) { confirmBatchDelete = true }
                    .disabled(selection.isEmpty || !canEdit)
                    .accessibilityIdentifier("deleteSelectedButton")
            }
        }
        if canEdit {
            // Not `EditButton()`: toolbar content doesn't see the edit mode bound on the list,
            // so that button toggled a different state and did nothing.
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "Done" : "Edit") {
                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                }
                .accessibilityIdentifier("editTasksButton")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Add task", systemImage: "plus") { editing = .add }
                    .accessibilityIdentifier("addTaskButton")
            }
        }
    }

    @ViewBuilder
    private var followUpSection: some View {
        if isFinished, let raid {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(raid.status == .won ? "Boss defeated" : "Deadline passed")
                        .font(.headline)
                    Text("Found more work after the deadline? Add follow-up tasks, then resume the fight. The boss comes back with health from the open tasks.")
                        .readableFootnote()
                    if raid.ownerID == LocalIdentity.current.memberID {
                        Button("Resume the fight", systemImage: "flame") { showResume = true }
                            .primaryActionStyle()
                            .disabled(open.isEmpty)
                            .accessibilityIdentifier("tasksResumeFightButton")
                    }
                }
            }
            .dungeonRow()
        }
    }

    @ViewBuilder
    private var planningSection: some View {
        if let raid, raid.status == .planning {
            let hp = BossEngine.lockHP(tasks: tasks.map(\.model), config: config)
            Section {
                Text("Boss health when the fight starts: \(hp) HP")
                    .font(.headline)
            }
            .dungeonRow()
        }
    }

    /// Open tasks, grouped by assignee like Notes groups by date: you first, then
    /// teammates in join order, then unassigned. While nobody is assigned anything
    /// (solo raids, mostly) it stays one "Open" group.
    private var openGroups: [TaskGroup] {
        let me = LocalIdentity.current.memberID
        guard open.contains(where: { $0.assigneeID != nil }) else {
            return [TaskGroup(id: "open", title: String(localized: "Open (\(open.count))"), tasks: open)]
        }
        let byAssignee = Dictionary(grouping: open) { $0.assigneeID }
        var order: [String] = [me] + members.map(\.memberID).filter { $0 != me }
        // Assignees who have since left the raid still get their own group.
        order += byAssignee.keys.compactMap { $0 }.filter { !order.contains($0) }.sorted()
        var groups = order.compactMap { id -> TaskGroup? in
            guard let tasks = byAssignee[id] else { return nil }
            let name = nickname(id) ?? String(localized: "Former member")
            return TaskGroup(id: id, title: String(localized: "\(name) (\(tasks.count))"), tasks: tasks)
        }
        // Unassigned tasks come first: they're the ones still waiting for someone.
        if let unassigned = byAssignee[nil] {
            groups.insert(TaskGroup(id: "unassigned", title: String(localized: "Unassigned (\(unassigned.count))"), tasks: unassigned), at: 0)
        }
        return groups
    }

    @ViewBuilder
    private var openSections: some View {
        if open.isEmpty && !tasks.isEmpty {
            Section {
                Text("All tasks done!")
                    .foregroundStyle(.readableSecondary)
            } header: {
                Text("Open (\(0))")
            }
            .dungeonRow()
        }
        let groups = openGroups
        let grouped = groups.count > 1 || groups.first?.id != "open"
        ForEach(groups) { group in
            Section {
                ForEach(group.tasks) { task in
                    // The group header already names the assignee.
                    row(task, showsAssignee: !grouped).moveDisabled(!canEdit)
                }
                .onMove { move(in: group.id, from: $0, to: $1) }
            } header: {
                Text(group.title)
            }
            .dungeonRow()
        }
    }

    @ViewBuilder
    private var doneSection: some View {
        if !done.isEmpty {
            Section {
                ForEach(done) { task in row(task) }
            } header: {
                Text("Done (\(done.count))").font(.headline)
            }
            .dungeonRow()
        }
    }

    @ViewBuilder
    private func row(_ record: TaskRecord, showsAssignee: Bool = true) -> some View {
        let task = record.model
        HStack(spacing: 12) {
            if !editMode.isEditing {
                CompleteButton(task: task, enabled: canComplete) { beginSelecting(task) }
            }
            let content = TaskRow(task: task, damage: config.baseDamage(of: task), assignee: showsAssignee ? nickname(task.assigneeID) : nil, isLate: task.isLate(startedAt: raid?.startedAt))
            if editMode.isEditing {
                // Taps select the row while choosing tasks.
                content
            } else {
                // A button, not a NavigationLink: next to the checkbox, a link's text didn't react to taps.
                Button { path.append(task.id) } label: {
                    HStack {
                        content
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .tag(task.id)
        .selectionDisabled(task.isDone)
        .matchedTransitionSource(id: task.id, in: zoom)
        // Fixed insets: with the system's default ones the accessibility audit
        // intermittently reports the row's text as not scaling with Dynamic Type.
        .listRowInsets(EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 14))
        // Full swipe right completes (green, like the checkbox), full swipe left deletes.
        // Apple's own symbols and names (Reminders/Mail): iOS 26 draws the icon in the capsule
        // with the name underneath.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !task.isDone && canComplete {
                Button { attemptComplete(task) } label: { Label("Complete", systemImage: "checkmark")
                    .labelStyle(.titleAndIcon) }
                    // Deeper than system green, so the white label reads (~5:1).
                    .tint(Color(hex: 0x1F7A3A))
            } else if task.isDone && canEdit {
                // Like Reminders: a finished item swipes back open.
                Button { reopen(task) } label: { Label("Reopen", systemImage: "arrow.uturn.backward")
                    .labelStyle(.titleAndIcon) }
                    .tint(Color(hex: 0x4A3F8F))
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !task.isDone && canEdit {
                // First listed = outermost = the full-swipe action.
                Button(role: .destructive) { delete(task) } label: { Label("Delete", systemImage: "trash.fill")
                    .labelStyle(.titleAndIcon) }
                    // Without a tint the destructive button takes the app's gold accent at night.
                    .tint(Theme.dangerTop)
                Button { editing = .edit(task) } label: { Label("Details", systemImage: "info.circle.fill")
                    .labelStyle(.titleAndIcon) }
                    .tint(Color(hex: 0x8A5A12))
            }
        }
        .contextMenu {
            if !task.isDone && canComplete {
                Button("Complete", systemImage: "checkmark.circle") { attemptComplete(task) }
            }
            if task.isDone {
                Button("Reopen", systemImage: "arrow.uturn.backward") { reopen(task) }
            }
            if canEdit {
                Button("Details", systemImage: "info.circle") { editing = .edit(task) }
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
                Button("Complete task") { attemptComplete(task) }
            }
            if canEdit {
                Button("Show details") { editing = .edit(task) }
            }
            if !task.isDone && canEdit {
                Button("Delete task", role: .destructive) { delete(task) }
            }
        }
        // A container, so the checkbox keeps its own identifier and label.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("task-\(task.title)")
    }

    private func nickname(_ id: String?) -> String? {
        guard let id else { return nil }
        if id == LocalIdentity.current.memberID { return String(localized: "You") }
        return members.first { $0.memberID == id }?.nickname
    }

    // MARK: Actions

    /// Tapping an empty circle starts selecting, with that task chosen, like Mail.
    private func beginSelecting(_ task: RaidTask) {
        withAnimation { editMode = .active }
        // After the list has entered edit mode: it clears the selection while it switches, so a
        // selection set together with edit mode never stuck (Complete stayed disabled).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            selection = [task.id]
        }
    }

    private func completeSelected() {
        let ids = open.map(\.id).filter { selection.contains($0) }
        guard let first = ids.first, let task = open.first(where: { $0.id == first })?.model else { return }
        if raid?.status == .planning {
            // Starting the fight first; the batch completes after the prompt is confirmed.
            pendingBatch = ids
            needsFightStart = task
        } else {
            completeBatch(ids)
        }
    }

    /// Completes several tasks; every one of them gets its attack animation, one after another.
    private func completeBatch(_ ids: [UUID]) {
        var attacks: [(Attack?, RaidTask)] = []
        for id in ids {
            guard let task = tasks.first(where: { $0.id == id })?.model, !task.isDone else { continue }
            do {
                attacks.append((try GameActions.completeTask(id), task))
            } catch {
                errorMessage = error.localizedDescription
                break
            }
        }
        withAnimation { editMode = .inactive }
        guard !attacks.isEmpty else { return }
        completedCount += 1
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            for (attack, task) in attacks {
                environment.castTaskAttack(attack, task: task, quick: attacks.count > 1)
            }
        }
    }

    private func deleteSelected() {
        for id in selection {
            guard let task = tasks.first(where: { $0.id == id }), !task.isDone else { continue }
            do { try DDStore.shared.deleteTask(id) } catch { errorMessage = error.localizedDescription; break }
        }
        GameActions.changed(raidID)
        withAnimation { editMode = .inactive }
    }

    /// Completes now while fighting; while planning, asks to start the fight first.
    private func attemptComplete(_ task: RaidTask) {
        if raid?.status == .planning {
            needsFightStart = task
        } else {
            complete(task)
        }
    }

    private func complete(_ task: RaidTask) {
        do {
            let attack = try GameActions.completeTask(task.id)
            completedCount += 1
            // Let the row finish its own swipe and check-off animation first, then jump to
            // the boss and play the class attack there (it announces the hit).
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                environment.castTaskAttack(attack, task: task)
            }
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

    /// Reorders within one group; the stored order follows the groups.
    private func move(in groupID: String, from source: IndexSet, to destination: Int) {
        let ids = openGroups.flatMap { group in
            var groupIDs = group.tasks.map(\.id)
            if group.id == groupID { groupIDs.move(fromOffsets: source, toOffset: destination) }
            return groupIDs
        }
        do { try DDStore.shared.moveTasks(raidID: raidID, orderedIDs: ids); GameActions.changed(raidID) } catch { errorMessage = error.localizedDescription }
    }
}

/// A section of the Quest Log: open tasks for one assignee.
private struct TaskGroup: Identifiable {
    let id: String
    let title: String
    let tasks: [TaskRecord]
}

struct TaskRow: View {
    let task: RaidTask
    let damage: Int
    let assignee: String?
    let isLate: Bool

    var body: some View {
        // Reminders-style: title, then one wrapping line of details. No layout switching,
        // so it scales cleanly with Dynamic Type.
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title)
                .foregroundStyle(task.isDone ? Theme.inkSoft : Theme.ink)
            Text(details)
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var details: String {
        var parts = ["\(String(localized: task.size.title)) · \(damage) dmg"]
        if let assignee { parts.append(assignee) }
        if isLate { parts.append(String(localized: "Late")) }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: Text {
        var parts = [task.title, String(localized: task.size.title), String(localized: "\(damage) damage")]
        if task.isDone { parts.append(String(localized: "done")) }
        if let assignee { parts.append(String(localized: "assigned to \(assignee)")) }
        if isLate { parts.append(String(localized: "added after the fight started")) }
        return Text(parts.joined(separator: ", "))
    }
}

/// The row's checkbox, like Reminders: one tap completes the task.
struct CompleteButton: View {
    let task: RaidTask
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(task.isDone ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.inkSoft))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: task.isDone)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Borderless, so tapping the checkbox doesn't open the task.
        .buttonStyle(.borderless)
        .disabled(task.isDone || !enabled)
        .accessibilityLabel(task.isDone ? Text("\(task.title), done") : Text("Select \(task.title)"))
        .accessibilityHint(task.isDone ? Text("") : Text("Starts selecting tasks to complete or delete"))
        .accessibilityIdentifier("complete-\(task.title)")
    }
}

extension View {
    /// Asks to start the fight when a task is completed during planning.
    /// The raid leader can start it right away; others are told to wait.
    func startFightPrompt(task: Binding<RaidTask?>, raid: Raid?, complete: @escaping (RaidTask) -> Void) -> some View {
        modifier(StartFightPrompt(task: task, raid: raid, complete: complete))
    }
}

private struct StartFightPrompt: ViewModifier {
    @Binding var task: RaidTask?
    let raid: Raid?
    let complete: (RaidTask) -> Void
    @Environment(Announcer.self) private var announcer
    @State private var errorMessage: String?

    private var isLeader: Bool { raid?.ownerID == LocalIdentity.current.memberID }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "The fight hasn't started",
                isPresented: Binding(get: { task != nil }, set: { if !$0 { task = nil } }),
                titleVisibility: .visible,
                presenting: task
            ) { pending in
                if isLeader {
                    Button("Start the fight and complete") {
                        do {
                            try GameActions.startFight(raid?.id)
                            announcer.announce(String(localized: "The fight has started!"), important: true)
                            complete(pending)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                Button("Not yet", role: .cancel) {}
            } message: { _ in
                if isLeader {
                    Text("Tasks only hit the boss once the fight is on. Starting locks the boss's health from the planned tasks.")
                } else {
                    Text("Tasks only hit the boss once the fight is on. The raid leader starts it.")
                }
            }
            .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
