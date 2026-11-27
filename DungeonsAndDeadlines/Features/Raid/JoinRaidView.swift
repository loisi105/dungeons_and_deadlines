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
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Invite code", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.join)
                        .focused($codeFocused)
                        .onSubmit { if code.count >= 6, !isJoining { join() } }
                        .font(.title2.monospaced())
                        .accessibilityHint("Six letters and numbers from the raid leader.")
                    Text("Ask the raid leader for the 6-character code. Raids hold up to 5 people.").readableFootnote()
                }
                .dungeonRow()
                Section {
                    RolePickerRow(role: $role)
                }
                .dungeonRow()
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                    .dungeonRow()
                }
            }
            .headerProminence(.increased)
            .scrollDismissesKeyboard(.interactively)
            .dungeonScreen()
            .onAppear { codeFocused = true }
            .navigationTitle("Join raid")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCancelConfirm("Join", confirmIdentifier: "joinRaidButton", isEnabled: code.count >= 6, isWorking: isJoining, hasChanges: !code.isEmpty || role != nil, onConfirm: join)
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
