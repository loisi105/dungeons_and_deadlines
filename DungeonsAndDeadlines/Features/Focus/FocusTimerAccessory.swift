import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// The running timer, shown on every tab like a music mini-player (`tabViewBottomAccessory`).
/// Tap to open the full timer; the trailing button starts or pauses.
struct FocusTimerAccessory: View {
    let raidID: UUID
    let open: () -> Void

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(Announcer.self) private var announcer
    @Query private var sessions: [FocusSessionRecord]
    @State private var toggles = 0
    @AppStorage("settings.haptics", store: AppGroup.defaults) private var hapticsOn = true

    init(raidID: UUID, open: @escaping () -> Void) {
        self.raidID = raidID
        self.open = open
        let key = MemberRecord.key(raidID: raidID, memberID: LocalIdentity.current.memberID)
        _sessions = Query(filter: #Predicate<FocusSessionRecord> { $0.key == key })
    }

    private var session: FocusSession {
        sessions.first?.model ?? FocusSession(raidID: raidID, memberID: LocalIdentity.current.memberID)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: session.state == .running ? "flame.fill" : "flame")
                        .foregroundStyle(session.state == .running ? .orange : .primary)
                        .symbolEffect(.pulse, isActive: session.state == .running)
                    if session.state == .running {
                        Text(timerInterval: session.timerReferenceDate(at: .now)...Date.distantFuture, countsDown: false)
                            .monospacedDigit()
                    } else if session.state == .paused {
                        Text("Paused · \(A11yText.shortDuration(Int(session.elapsed(at: .now))))")
                    } else {
                        Text("Focus timer")
                    }
                    if placement != .inline { Spacer(minLength: 0) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityHint("Opens the focus timer.")
            .accessibilityIdentifier("focusAccessory")

            Button(action: toggle) {
                Image(systemName: session.state == .running ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .medium), trigger: toggles) { _, _ in hapticsOn }
            .accessibilityLabel(session.state == .running ? Text("Pause focus") : Text("Start focus"))
            .accessibilityInputLabels(session.state == .running ? ["Pause", "Pause focus"] : ["Start", "Focus", "Start focus"])
        }
        .padding(.horizontal, 16)
        .animation(.smooth, value: session.state)
    }

    private var accessibilityLabel: Text {
        switch session.state {
        case .running: Text("Focus running, \(A11yText.duration(Int(session.elapsed(at: .now))))")
        case .paused: Text("Focus paused at \(A11yText.duration(Int(session.elapsed(at: .now))))")
        case .idle: Text("Focus timer")
        }
    }

    private func toggle() {
        toggles += 1
        do {
            if session.state == .running {
                try GameActions.pauseFocus(raidID)
                announcer.announce(String(localized: "Focus paused."))
            } else {
                try GameActions.startFocus(raidID)
                announcer.announce(String(localized: "Focus started."))
            }
        } catch {
            announcer.announce(error.localizedDescription, important: true)
        }
    }
}
