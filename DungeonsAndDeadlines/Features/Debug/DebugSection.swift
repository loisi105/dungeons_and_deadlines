#if DEBUG
import SwiftUI
import DDDesign

/// Simulated teammates for testing the raid UI offline (solo raids only).
struct DebugSection: View {
    let raidID: UUID
    @Environment(FakeTeammates.self) private var fakes
    /// Read once when the section appears: fetching from the store inside `body` re-ran it on every
    /// refresh of the list, and froze the screen when a row was tapped.
    @State private var canRun = false

    var body: some View {
        Section {
            if canRun {
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
        .onAppear { canRun = fakes.canRun(in: raidID) }
    }
}
#endif
