import ActivityKit
import SwiftUI
import WidgetKit
import GameCore
import DDIntents
import DDDesign

/// Lock Screen and Dynamic Island for a running focus session.
struct FocusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            LockScreenFocusView(context: context)
                .activityBackgroundTint(Color(hex: 0x150C2B).opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        PixelArtView(BossKind.forName(context.attributes.bossName).art, eyeColor: state.phase.eyeColor)
                            .frame(width: 28, height: 28)
                        Text("\(percent(state))%")
                    }
                    .font(.headline)
                    .accessibilityLabel("Boss health \(percent(state)) percent")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    FocusTimerText(state: state)
                        .font(.headline)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.bossName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        ProgressView(value: Double(state.currentHP), total: Double(max(state.maxHP, 1)))
                            .tint(state.phase.tint)
                            .accessibilityLabel("\(context.attributes.bossName) health")
                            .accessibilityValue("\(state.currentHP) of \(state.maxHP)")
                        FocusActivityButtons(context: context)
                    }
                }
            } compactLeading: {
                PixelArtView(BossKind.forName(context.attributes.bossName).art, eyeColor: state.phase.eyeColor)
                    .frame(width: 22, height: 22)
                    .accessibilityLabel("\(context.attributes.bossName), \(percent(state)) percent")
            } compactTrailing: {
                FocusTimerText(state: state)
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: state.isRunning ? "flame.fill" : "pause.fill")
                    .foregroundStyle(state.phase.tint)
                    .accessibilityLabel(state.isRunning ? "Focus running" : "Focus paused")
            }
            .keylineTint(state.phase.tint)
        }
    }
}

private func percent(_ state: FocusActivityAttributes.ContentState) -> Int {
    state.maxHP > 0 ? Int((Double(state.currentHP) / Double(state.maxHP) * 100).rounded()) : 0
}

struct FocusTimerText: View {
    let state: FocusActivityAttributes.ContentState

    var body: some View {
        Group {
            if state.isRunning {
                Text(timerInterval: state.timerReference...Date.distantFuture, countsDown: false)
            } else {
                Text(A11yText.shortDuration(state.elapsedSeconds))
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

struct LockScreenFocusView: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let state = context.state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    PixelArtView(BossKind.forName(context.attributes.bossName).art, eyeColor: state.phase.eyeColor)
                        .frame(width: 40, height: 40)
                    Text(context.attributes.bossName).font(.headline).fontDesign(.serif)
                }
                Spacer()
                FocusTimerText(state: state)
                    .font(.title2.bold())
            }
            ProgressView(value: Double(state.currentHP), total: Double(max(state.maxHP, 1)))
                .tint(state.phase.tint)
                .accessibilityLabel("\(context.attributes.bossName) health")
                .accessibilityValue("\(state.currentHP) of \(state.maxHP), phase \(String(localized: state.phase.title))")
            HStack {
                if state.attackers.isEmpty {
                    Text(state.isRunning ? "You're attacking" : "Paused")
                } else {
                    Text("Also attacking: \(state.attackers.joined(separator: ", "))")
                        .lineLimit(1)
                }
                Spacer()
                FocusActivityButtons(context: context)
            }
            .font(.subheadline)
        }
        .padding()
        .foregroundStyle(.white)
    }
}

/// Pause/resume and stop, run in the app's process via `LiveActivityIntent`.
struct FocusActivityButtons: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        let raid = RaidEntity(id: context.attributes.raidID, name: context.attributes.raidName, bossName: context.attributes.bossName)
        HStack(spacing: 8) {
            if context.state.isRunning {
                Button(intent: PauseFocusIntent(raid: raid)) {
                    Label("Pause", systemImage: "pause.fill")
                }
            } else {
                Button(intent: StartFocusIntent(raid: raid)) {
                    Label("Resume", systemImage: "play.fill")
                }
            }
            Button(intent: StopFocusIntent(raid: raid)) {
                Label("Stop and attack", systemImage: "bolt.fill")
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .tint(.white)
    }
}
