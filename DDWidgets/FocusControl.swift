import AppIntents
import SwiftUI
import WidgetKit
import DDIntents

/// Control Center / Lock Screen / Action button toggle for focus.
struct FocusControl: ControlWidget {
    static let kind = "at.fhooe.sail.dungeonsanddeadlines.focus-control"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind, provider: Provider()) { isOn in
            ControlWidgetToggle("Boss Focus", isOn: isOn, action: ToggleFocusIntent()) { on in
                Label(on ? "Attacking" : "Focus", systemImage: on ? "flame.fill" : "flame")
            }
            .tint(.orange)
        }
        .displayName("Boss Focus")
        .description("Start or stop a focus session that damages your current boss.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            await MainActor.run { GameActions.isFocusRunning() }
        }
    }
}
