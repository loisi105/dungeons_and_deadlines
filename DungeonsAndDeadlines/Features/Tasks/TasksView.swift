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
        NavigationStack {
            taskList
                .navigationTitle("Quest Log")
                .navigationSubtitle(raid.map { "\($0.bossName) · \($0.name)" } ?? "")
                .navigationDestination(for: UUID.self) { id in
                    TaskDetailView(taskID: id, raidID: raidID)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
                .toolbar { toolbar }
                .sheet(item: $editing) { mode in
                    TaskEditorView(raidID: raidID, mode: mode)
                }
                .sensoryFeedback(.impact(weight: .heavy), trigger: completedCount) { _, _ in hapticsOn }
                .startFightPrompt(task: $needsFightStart, raid: raid) { task in complete(task) }
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
        List {
            followUpSection
            planningSection
            openSection
            doneSection
        }
        .listStyle(.insetGrouped)
        // Each task is its own cell-sized card, so swipe buttons line up with it.
        .listRowSpacing(8)
        .headerProminence(.increased)
        .dungeonScreen()
        .readableContentWidth(minMargin: 16)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { BossSwitcher(currentRaidID: raidID) }
        if canEdit {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
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
            .questCard()
        }
    }

    @ViewBuilder
    private var planningSection: some View {
        if let raid, raid.status == .planning {
            let hp = BossEngine.lockHP(tasks: tasks.map(\.model), config: config)
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Boss health when the fight starts: \(hp) HP")
                        .font(.headline)
                    Text("Small tasks deal \(config.smallTaskDamage), medium \(config.mediumTaskDamage), large \(config.largeTaskDamage) damage. Focus time covers the rest.")
                        .readableFootnote()
                }
            }
            .questCard()
        }
    }

    private var openSection: some View {
        Section {
            if open.isEmpty {
                Text(tasks.isEmpty ? "No tasks yet. Add the steps for this deadline." : "All tasks done!")
                    .foregroundStyle(.readableSecondary)
                    .questCard()
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
            Section {
                ForEach(done) { task in row(task) }
            } header: {
                Text("Done (\(done.count))").font(.headline)
            }
        }
    }

    @ViewBuilder
    private func row(_ record: TaskRecord) -> some View {
        let task = record.model
        HStack(spacing: 12) {
            CompleteButton(task: task, enabled: canComplete) { attemptComplete(task) }
            NavigationLink(value: task.id) {
                TaskRow(task: task, damage: config.baseDamage(for: task.size), assignee: nickname(task.assigneeID), isLate: task.isLate(startedAt: raid?.startedAt))
            }
        }
        .matchedTransitionSource(id: task.id, in: zoom)
        .questCard(leading: 6)
        // Mail/Reminders style: full swipe right completes (green, like the checkbox),
        // full swipe left deletes.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !task.isDone && canComplete {
                Button("Complete", systemImage: "checkmark") { attemptComplete(task) }
                    .tint(.green)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !task.isDone && canEdit {
                Button("Delete", systemImage: "trash", role: .destructive) { delete(task) }
                    // Without a tint the destructive button takes the app's gold accent at night.
                    .tint(Theme.dangerTop)
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
                Button("Complete task") { attemptComplete(task) }
            }
            if canEdit {
                Button("Edit task") { editing = .edit(task) }
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
            // Jump to the boss and play the class attack there (it announces the hit).
            environment.castTaskAttack(attack, task: task)
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

extension View {
    /// Quest Log rows as separate cards (inset grouped cells with row spacing), the way
    /// iOS 26 draws a swiped cell: the card slides aside and the system's rounded swipe
    /// buttons sit beside it on the page, the same shape and height, instead of opening a
    /// rectangular hole in a strip of rows. `leading` is the content's inset in the card;
    /// task rows pass less, since the checkbox's 44 pt tap target already pads the circle.
    fileprivate func questCard(leading: CGFloat = 14) -> some View {
        modifier(QuestCard(leading: leading))
    }
}

private struct QuestCard: ViewModifier {
    let leading: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 8, leading: leading, bottom: 8, trailing: 14))
            .listRowSeparator(.hidden)
            .listRowBackground(
                // At least the system cell's corner radius, so its clip never shaves the
                // edge. No border by default: mid-swipe the clip stays put while the card
                // slides, and a border would show the cut.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.card)
                    .strokeBorder(contrast == .increased ? Theme.cardBorder : .clear, lineWidth: 2)
            )
    }
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
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? Theme.inkSoft : Theme.ink)
            Text(details)
                .font(.caption)
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
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Borderless, so tapping the checkbox doesn't open the task.
        .buttonStyle(.borderless)
        .disabled(task.isDone || !enabled)
        .accessibilityLabel(task.isDone ? Text("\(task.title), done") : Text("Complete \(task.title)"))
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
