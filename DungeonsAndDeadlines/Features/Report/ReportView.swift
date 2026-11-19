import SwiftUI
import SwiftData
import GameCore
import DDPersistence
import DDDesign

/// Simple victory/defeat summary. The full report with titles comes in M7.
struct ReportView: View {
    let raidID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let report = DDStore.shared.report(raidID) {
                    List {
                        Section {
                            LabeledContent("Result") { Text(report.state.outcome.title) }
                            LabeledContent("Damage dealt", value: "\(report.state.totalDamage)")
                            LabeledContent("Health left", value: "\(report.state.currentHP) / \(report.state.maxHP)")
                        }
                    }
                } else {
                    ContentUnavailableView("No report", systemImage: "doc")
                }
            }
            .headerProminence(.increased)
            .navigationTitle("Raid report")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
