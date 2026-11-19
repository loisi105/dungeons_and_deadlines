#if DEBUG
import SwiftUI
import DDDesign

/// Simulated teammates for testing the raid UI offline (solo raids only).
struct DebugSection: View {
    let raidID: UUID
    @Environment(FakeTeammates.self) private var fakes

    var body: some View {
        Section {
            if fakes.canRun(in: raidID) {
                Toggle("Fake teammates", isOn: Binding(
                    get: { fakes.runningRaidID == raidID },
                    set: { $0 ? fakes.start(raidID: raidID) : fakes.stop() }
                ))
                .accessibilityIdentifier("fakeTeammatesToggle")
                Text("Adds 3 simulated members who hit the boss every few seconds.")
                    .readableFootnote()
            } else {
                Text("Fake teammates only work in solo raids, so fake hits are never uploaded.")
                    .readableFootnote()
            }
        } header: {
            Text("Debug").font(.headline)
        }
        .dungeonRow()
    }
}
#endif
