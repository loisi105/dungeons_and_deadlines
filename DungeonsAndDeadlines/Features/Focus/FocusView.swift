import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// The focus timer. Controls float in a GlassEffectContainer and morph between
/// "Start" and "Pause | Stop" with `glassEffectID`.
struct FocusView: View {
    let raidID: UUID

    @Environment(Announcer.self) private var announcer
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true

    @Query private var sessions: [FocusSessionRecord]
    @Query private var raids: [RaidRecord]
    @Query private var attacks: [AttackRecord]
    @Namespace private var glass
    @State private var errorMessage: String?
    @State private var feedbackTrigger = 0
    @ScaledMetric(relativeTo: .largeTitle) private var timerSize: CGFloat = 72

    init(raidID: UUID) {
        self.raidID = raidID
        let key = MemberRecord.key(raidID: raidID, memberID: LocalIdentity.current.memberID)
        _sessions = Query(filter: #Predicate<FocusSessionRecord> { $0.key == key })
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
        _attacks = Query(filter: #Predicate<AttackRecord> { $0.raidID == raidID })
    }

    private var session: FocusSession {
        sessions.first?.model ?? FocusSession(raidID: raidID, memberID: LocalIdentity.current.memberID)
    }

    private var remainingCapSeconds: Int {
        let me = LocalIdentity.current.memberID
        let calc = DDStore.shared.calculator
        let context = DamageCalculator.Context(memberID: me, attacks: attacks.map(\.model), memberCount: 1, lockedMaxHP: nil, now: .now)
        return calc.remainingFocusSeconds(context)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    timer
                    capInfo
                    controls
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: feedbackTrigger) { _, _ in hapticsOn }
            .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Parts

    private var timer: some View {
        VStack(spacing: 8) {
            Group {
                if session.state == .running {
                    Text(timerInterval: session.timerReferenceDate(at: .now)...Date.distantFuture, countsDown: false)
                } else {
                    Text(Duration.seconds(Int(session.elapsed(at: .now))), format: .time(pattern: .hourMinuteSecond))
                }
            }
            .font(.system(size: timerSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .accessibilityLabel(timerAccessibilityLabel)

            Text(stateText)
                .font(.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.readableSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("focusTimer")
    }

    private var timerAccessibilityLabel: Text {
        Text("Focus time \(A11yText.duration(Int(session.elapsed(at: .now))))")
    }

    private var stateText: LocalizedStringKey {
        switch session.state {
        case .idle: "Ready when you are"
        case .running: "Attacking: 2 damage per minute"
        case .paused: "Paused"
        }
    }

    private var capInfo: some View {
        // One Text (with an inline symbol) so it wraps instead of clipping at large sizes.
        Text("\(Image(systemName: "gauge.with.dots.needle.33percent")) \(A11yText.shortDuration(remainingCapSeconds)) of focus damage left today")
            .font(.subheadline)
            .foregroundStyle(.readableSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(Text("\(A11yText.duration(remainingCapSeconds)) of focus damage left today"))
    }

    private var controls: some View {
        GlassEffectContainer(spacing: 16) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 16))
                : AnyLayout(HStackLayout(spacing: 16))
            layout {
                switch session.state {
                case .idle:
                    control("Start focus", systemImage: "play.fill", id: "primary", prominent: true) { start() }
                        .accessibilityIdentifier("startFocusButton")
                case .running:
                    control("Pause", systemImage: "pause.fill", id: "primary", prominent: false) { pause() }
                        .accessibilityIdentifier("pauseFocusButton")
                    control("Stop and attack", systemImage: "bolt.fill", id: "stop", prominent: true) { stop() }
                        .accessibilityIdentifier("stopFocusButton")
                case .paused:
                    control("Resume", systemImage: "play.fill", id: "primary", prominent: false) { start() }
                        .accessibilityIdentifier("resumeFocusButton")
                    control("Stop and attack", systemImage: "bolt.fill", id: "stop", prominent: true) { stop() }
                        .accessibilityIdentifier("stopFocusButton")
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.4), value: session.state)
    }

    @ViewBuilder
    private func control(_ title: LocalizedStringKey, systemImage: String, id: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .controlSize(.large)
        .glassEffectID(id, in: glass)
        if prominent {
            button.primaryActionStyle()
        } else {
            button.secondaryActionStyle()
        }
    }

    // MARK: Actions

    private func start() {
        do {
            try GameActions.startFocus(raidID)
            feedbackTrigger += 1
            announcer.announce(String(localized: "Focus started."))
        } catch { errorMessage = error.localizedDescription }
    }

    private func pause() {
        do {
            try GameActions.pauseFocus(raidID)
            feedbackTrigger += 1
            announcer.announce(String(localized: "Focus paused."))
        } catch { errorMessage = error.localizedDescription }
    }

    private func stop() {
        do {
            let attack = try GameActions.stopFocus(raidID)
            feedbackTrigger += 1
            if let attack {
                announcer.announceOwnHit(attack)
            } else {
                announcer.announce(String(localized: "Focus stopped. No damage: today's focus limit is used up or the session was too short."))
            }
        } catch { errorMessage = error.localizedDescription }
    }
}
