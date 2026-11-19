import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// Brings a finished boss back for follow-up tasks: pick a new deadline, see how much
/// health it returns with, resume.
struct ResumeFightView: View {
    let raidID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(Announcer.self) private var announcer
    @Query private var tasks: [TaskRecord]
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 3, to: .now) ?? .now
    @State private var errorMessage: String?

    init(raidID: UUID) {
        self.raidID = raidID
        _tasks = Query(filter: #Predicate<TaskRecord> { $0.raidID == raidID && $0.deletedAt == nil && $0.completedAt == nil })
    }

    private var returningHP: Int { BossEngine.lockHP(tasks: tasks.map(\.model), config: DDStore.shared.config) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(tasks.isEmpty
                         ? "Add a follow-up task first. The boss comes back with health from the open tasks."
                         : "The boss comes back with \(returningHP) HP from \(tasks.count) open task(s). Earlier hits stay in the report.")
                        .readableFootnote()
                    DatePicker("New deadline", selection: $deadline, in: Date.now.addingTimeInterval(3600)..., displayedComponents: [.date, .hourAndMinute])
                }
                .dungeonRow()
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }.dungeonRow()
                }
            }
            .dungeonScreen()
            .navigationTitle("Resume the fight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Resume") { resume() }
                        .disabled(tasks.isEmpty)
                        .accessibilityIdentifier("confirmResumeButton")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func resume() {
        do {
            try GameActions.resumeFight(raidID, deadline: deadline)
            announcer.announce(String(localized: "The boss is back. The fight is on!"), important: true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
