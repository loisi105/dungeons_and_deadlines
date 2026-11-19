import SwiftUI
import GameCore
import DDDesign

struct JoinRaidView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncEngine.self) private var sync

    @State private var code = ""
    @State private var role: Role?
    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title2.monospaced())
                        .accessibilityHint("Six letters and numbers from the raid leader.")
                } footer: {
                    Text("Ask the raid leader for the 6-character code. Raids hold up to 5 people.").readableFootnote()
                }
                Section {
                    RolePickerRow(role: $role)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .headerProminence(.increased)
            .navigationTitle("Join raid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button("Join", action: join).disabled(code.count < 6)
                    }
                }
            }
        }
    }

    private func join() {
        isJoining = true
        errorMessage = nil
        Task {
            defer { isJoining = false }
            do {
                try await sync.join(code: code, role: role)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
