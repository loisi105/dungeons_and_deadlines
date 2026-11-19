import SwiftUI
import DDPersistence
import DDDesign

/// First launch: explain the idea and pick a nickname.
struct OnboardingView: View {
    @State private var name = ""
    @State private var showValidation = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    BossAvatar(bossName: "Deadline Clock", phase: .angry)
                        .padding(.top, 32)
                    VStack(spacing: 12) {
                        Text("Deadlines are bosses.")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Finish tasks and focus to deal damage. Beat the boss before the deadline, alone or with up to 4 friends.")
                            .font(.body)
                            .foregroundStyle(.readableSecondary)
                            .multilineTextAlignment(.center)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your nickname")
                            .font(.headline)
                        TextField("e.g. Ada", text: $name)
                            .textContentType(.nickname)
                            .submitLabel(.continue)
                            .focused($nameFocused)
                            .onSubmit(save)
                            .padding(12)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("nicknameField")
                        if showValidation {
                            Label("Enter a nickname to continue.", systemImage: "exclamationmark.circle")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.red)
                        } else {
                            Text("Teammates see this in raids.")
                                .readableFootnote()
                        }
                    }
                    Button(action: save) {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .primaryActionStyle()
                    .controlSize(.large)
                    .accessibilityIdentifier("continueButton")
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .dungeonScreen()
        }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty else {
            showValidation = true
            AccessibilityNotification.Announcement(String(localized: "Enter a nickname to continue.")).post()
            return
        }
        LocalIdentity.setNickname(trimmed)
    }
}

#Preview { OnboardingView() }
