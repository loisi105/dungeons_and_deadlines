import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// The boss, its health, the phase and the latest hits.
struct BossView: View {
    let raidID: UUID
    var showTasks: () -> Void = {}

    @Environment(Announcer.self) private var announcer
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true

    @Query private var raids: [RaidRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var attacks: [AttackRecord]
    @Query private var members: [MemberRecord]

    @State private var lastHit: Attack?
    /// The class attack currently playing over the boss.
    @State private var activeCast: AttackCast?
    @State private var hitCount = 0
    @State private var shake: CGFloat = 0
    @State private var errorMessage: String?
    @State private var showReport = false
    @State private var showResume = false
    @State private var addFollowUp = false
    @State private var showPhaseDetails = false

    init(raidID: UUID, showTasks: @escaping () -> Void = {}) {
        self.raidID = raidID
        self.showTasks = showTasks
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
        _tasks = Query(filter: #Predicate<TaskRecord> { $0.raidID == raidID && $0.deletedAt == nil }, sort: \TaskRecord.sortIndex)
        _attacks = Query(filter: #Predicate<AttackRecord> { $0.raidID == raidID }, sort: \AttackRecord.createdAt)
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID }, sort: \MemberRecord.joinedAt)
    }

    private var me: String { LocalIdentity.current.memberID }

    var body: some View {
        NavigationStack {
            if let raid = raids.first?.model {
                TimelineView(.everyMinute) { context in
                    let state = BossEngine.state(raid: raid, tasks: tasks.map(\.model), attacks: attacks.map(\.model), now: context.date)
                    content(raid: raid, state: state)
                        // Only when the boss gets angrier, like the announcement; calming down is quiet.
                        .sensoryFeedback(.warning, trigger: state.phase) { old, new in hapticsOn && state.outcome == .ongoing && new > old }
                        .sensoryFeedback(.success, trigger: state.outcome) { _, new in hapticsOn && new == .won }
                        .onChange(of: state.phase) { old, new in
                            guard state.outcome == .ongoing, new > old else { return }
                            // The hint describes the time rule, which doesn't hold once the leader shifted it.
                            let why = raid.phaseShift == 0
                                ? String(localized: new.hint)
                                : String(localized: "The raid leader set the boss's mood.")
                            announcer.announce(String(localized: "The boss is now \(String(localized: new.title)). \(why)"), important: true)
                        }
                        // Mood changes are for a running fight only.
                        .onChange(of: state.outcome) { _, new in
                            if new != .ongoing { showPhaseDetails = false }
                        }
                }
                .navigationTitle(raid.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { BossSwitcher(currentRaidID: raidID) }
                }
                .sheet(isPresented: $showReport) { ReportView(raidID: raidID) }
                .sheet(isPresented: $showResume) { ResumeFightView(raidID: raidID) }
                .sheet(isPresented: $addFollowUp) { TaskEditorView(raidID: raidID, mode: .add) }
                // At accessibility text sizes the phase details are a sheet; a popover would clip.
                .sheet(isPresented: phaseDetailsBinding(asSheet: true)) {
                    if let raid = raids.first?.model {
                        // Re-evaluated when the raid, its tasks or hits change; the details also
                        // check the deadline themselves. A finished fight shows no mood buttons.
                        PhaseDetailsSheet(raid: raid, isOngoing: isOngoing(raid))
                    }
                }
            } else {
                ContentUnavailableView("Raid not found", systemImage: "questionmark.circle")
            }
        }
        .onChange(of: attacks.count) { old, new in
            guard new > old else { return }
            let fresh = attacks.suffix(new - old).map(\.model)
            for attack in fresh where attack.memberID != me {
                announcer.queueTeammateHit(attack)
            }
            // A task attack from this phone gets its class animation instead (see below).
            if let latest = fresh.last, latest.id != environment.pendingAttack?.id, latest.id != activeCast?.id {
                playHit(latest)
            }
        }
        .onChange(of: environment.pendingAttack?.id) { startPendingCast() }
        .onAppear { startPendingCast() }
        .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(raid: Raid, state: BossState) -> some View {
        ScrollView {
            // iPad (regular width): the boss on the left, the battle info on the right.
            // iPhone: one column.
            let wide = horizontalSizeClass == .regular
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
                : AnyLayout(VStackLayout(spacing: 20))
            layout {
                header(raid: raid, state: state)
                    .frame(maxWidth: wide ? 560 : 640)
                VStack(spacing: 20) {
                    switch state.outcome {
                    case .planning: planningCard(raid: raid, state: state)
                    case .won, .lost: outcomeCard(raid: raid, state: state)
                    case .ongoing: EmptyView()
                    }
                    recentHits
                }
                .frame(maxWidth: wide ? 440 : 640)
            }
            .padding(wide ? 28 : 16)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .dungeonScreen()
    }

    // MARK: Header

    private func header(raid: Raid, state: BossState) -> some View {
        VStack(spacing: 16) {
            ZStack {
                BossAvatar(bossName: raid.bossName, phase: state.phase, defeated: state.outcome == .won)
                    .modifier(ShakeEffect(amount: reduceMotion ? 0 : 10, shakes: shake))
                    .opacity(reduceMotion && shake.truncatingRemainder(dividingBy: 2) == 1 ? 0.6 : 1)
                SwordSlash(trigger: hitCount)
                    .frame(width: 150, height: 150)
                    .offset(x: 30, y: 10)
                if let activeCast {
                    AttackEffect(cast: activeCast) { land(activeCast) }
                        .id(activeCast.id)
                }
                if let lastHit {
                    DamageNumber(damage: lastHit.damage, id: hitCount, reduceMotion: reduceMotion)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                // The icon's night sky behind the boss, framed like a window into the dungeon.
                PixelArtView(.nightSky, fill: true)
                    .overlay(state.phase.tint.opacity(state.phase >= .enraged ? 0.25 : 0))
                    .clipShape(PixelCornerShape(step: 6))
                    .overlay(PixelCornerShape(step: 6).stroke(Theme.outline, lineWidth: 3))
            }

            VStack(spacing: 8) {
                Text(raid.bossName)
                    .font(.title.weight(.black))
                    .multilineTextAlignment(.center)
                    // A single long word ("Procrastination") can't wrap; let it shrink instead of clipping.
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                if state.outcome == .ongoing { phaseBadgeButton(raid: raid, state: state) }
            }

            VStack(spacing: 6) {
                HPBar(current: state.currentHP, max: state.maxHP, phase: state.phase, bossName: raid.bossName)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout())
                layout {
                    Text("\(state.currentHP) / \(state.maxHP) HP")
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    deadlineText(raid: raid)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
                .accessibilityElement(children: .combine)
            }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: hitCount) { _, _ in hapticsOn }
        .animation(reduceMotion ? nil : .smooth, value: state.currentHP)
    }

    /// The phase badge opens how long the phase lasts, what's next, and (for the leader)
    /// buttons to make the boss angrier or calmer than the deadline says.
    private func phaseBadgeButton(raid: Raid, state: BossState) -> some View {
        Button {
            showPhaseDetails = true
        } label: {
            PhaseBadge(state.phase, isShifted: raid.phaseShift != 0)
        }
        .buttonStyle(.plain)
        // The badge's hint describes the time rule, which doesn't hold once the leader shifted it.
        .accessibilityLabel(raid.phaseShift == 0
            ? Text("Phase \(state.phase.rawValue): \(Text(state.phase.title)). \(Text(state.phase.hint))")
            : Text("Phase \(state.phase.rawValue): \(Text(state.phase.title)). Set by the raid leader."))
        .accessibilityHint(Text("Shows when the boss gets angrier"))
        .accessibilityIdentifier("phaseBadgeButton")
        .popover(isPresented: phaseDetailsBinding(asSheet: false), arrowEdge: .top) {
            PhaseDetailsView(raid: raid, isOngoing: state.outcome == .ongoing)
                .padding(20)
                .frame(width: 320)
                .presentationCompactAdaptation(.popover)
                .presentationBackground(Theme.card)
        }
    }

    /// Whether the fight is running right now (not planning, won or lost).
    private func isOngoing(_ raid: Raid) -> Bool {
        BossEngine.state(raid: raid, tasks: tasks.map(\.model), attacks: attacks.map(\.model), now: .now).outcome == .ongoing
    }

    /// One flag drives both presentations; the text size picks popover or sheet.
    private func phaseDetailsBinding(asSheet: Bool) -> Binding<Bool> {
        Binding(
            get: { showPhaseDetails && dynamicTypeSize.isAccessibilitySize == asSheet },
            set: { showPhaseDetails = $0 }
        )
    }

    @ViewBuilder
    private func deadlineText(raid: Raid) -> some View {
        if raid.deadline > .now {
            Text("Deadline \(Text(raid.deadline, style: .relative))")
        } else {
            Text("Deadline passed")
        }
    }

    // MARK: Cards

    private func planningCard(raid: Raid, state: BossState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prepare for battle", systemImage: "map.fill")
                .font(.headline)
            Text("Add the tasks for this deadline. When the fight starts, the boss's health is locked at \(state.maxHP) HP from the planned tasks.")
                .foregroundStyle(.readableSecondary)
            if raid.ownerID == me {
                HStack {
                    Button("Add tasks", systemImage: "plus", action: showTasks)
                        .secondaryActionStyle()
                    Spacer()
                    Button {
                        startFight()
                    } label: {
                        Label("Start the fight", systemImage: "flame.fill")
                    }
                    .primaryActionStyle()
                    .disabled(tasks.isEmpty)
                    .accessibilityIdentifier("startFightButton")
                    .accessibilityHint(tasks.isEmpty ? Text("Add at least one task first.") : Text("Locks the boss's health and starts the fight."))
                }
                .controlSize(.large)
            } else {
                Label("Waiting for the raid leader to start the fight.", systemImage: "hourglass")
                    .foregroundStyle(.readableSecondary)
            }
        }
        .dungeonPanel()
    }

    private func outcomeCard(raid: Raid, state: BossState) -> some View {
        VStack(spacing: 12) {
            Image(systemName: state.outcome == .won ? "trophy.fill" : "flag.slash.fill")
                .font(.largeTitle)
                .foregroundStyle(state.outcome == .won ? .yellow : .secondary)
                .accessibilityHidden(true)
            Text(state.outcome.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text(state.outcome == .won
                 ? "You beat \(raid.bossName) before the deadline."
                 : "\(raid.bossName) survived with \(state.currentHP) HP.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.readableSecondary)
            Button("See report", systemImage: "doc.text.magnifyingglass") { showReport = true }
                .primaryActionStyle()
                .controlSize(.large)
                .accessibilityIdentifier("seeReportButton")
            // Follow-up work after the deadline: add tasks and bring the boss back.
            if raid.ownerID == me {
                Button("Add follow-up task", systemImage: "plus") { addFollowUp = true }
                    .secondaryActionStyle()
                    .accessibilityIdentifier("addFollowUpButton")
                Button("Resume the fight", systemImage: "flame") { showResume = true }
                    .secondaryActionStyle()
                    .accessibilityIdentifier("resumeFightButton")
            } else {
                Text("Found more work? The raid leader can add follow-up tasks and resume the fight.")
                    .readableFootnote()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .dungeonPanel()
        .accessibilityElement(children: .contain)
    }

    // MARK: Hits

    @ViewBuilder
    private var recentHits: some View {
        let recent = attacks.suffix(6).reversed().map(\.model)
        if !recent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Latest hits")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(recent) { attack in
                    HStack {
                        Image(systemName: attack.kind.isTask ? "bolt.fill" : "timer")
                            .foregroundStyle(.orange)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(nickname(attack.memberID))
                        Spacer()
                        Text("−\(attack.damage)")
                            .monospacedDigit()
                            .fontWeight(.semibold)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(A11yText.attack(attack, by: attack.memberID == me ? nil : nickname(attack.memberID)))
                }
            }
            .dungeonPanel()
        }
    }

    private func nickname(_ id: String) -> String {
        if id == me { return String(localized: "You") }
        return members.first { $0.memberID == id }?.nickname ?? String(localized: "Someone")
    }

    // MARK: Actions

    private func startFight() {
        do {
            try GameActions.startFight(raidID)
            announcer.announce(String(localized: "The fight has started!"), important: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Picks up a task attack waiting for this boss (after the tab switch has happened).
    private func startPendingCast() {
        // Match by boss, not by this view's attack list: that list updates a moment later.
        guard let cast = environment.pendingAttack, cast.raidID == raidID else { return }
        environment.pendingAttack = nil
        Task {
            // A short beat after the tab switch so the attack is seen from the start.
            try? await Task.sleep(for: .milliseconds(Int(250 * AttackEffect.timeScale)))
            activeCast = cast
        }
    }

    /// The class attack reached the boss: shake, damage number, haptic, announcement.
    private func land(_ cast: AttackCast) {
        if let attack = attacks.first(where: { $0.id == cast.id })?.model ?? DDStore.shared.attacks(raidID).first(where: { $0.id == cast.id }) {
            playHit(attack)
        }
        announcer.announce(cast.announcement)
        Task {
            try? await Task.sleep(for: .seconds(1 * AttackEffect.timeScale))
            if activeCast?.id == cast.id { activeCast = nil }
        }
    }

    private func playHit(_ attack: Attack) {
        lastHit = attack
        hitCount += 1
        if reduceMotion {
            shake += 1
        } else {
            withAnimation(.linear(duration: 0.45)) { shake += 1 }
        }
    }
}

/// Horizontal knockback on a hit.
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(shakes * .pi * 4), y: 0))
    }
}

/// "−150" floating up from the boss. Fades in place with Reduce Motion.
struct DamageNumber: View {
    let damage: Int
    let id: Int
    let reduceMotion: Bool
    @State private var visible = false

    var body: some View {
        Text("−\(damage)")
            .font(.system(.largeTitle, design: .monospaced).weight(.black))
            .foregroundStyle(Color(hex: 0xEF4444))
            .shadow(radius: 4)
            .offset(y: visible && !reduceMotion ? -70 : 0)
            .opacity(visible ? 0 : 1)
            .accessibilityHidden(true)
            .id(id)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) { visible = true }
            }
    }
}
