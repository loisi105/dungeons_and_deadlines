import SwiftUI

// MARK: - The overlay dismiss rule
//
// Every sheet and full-screen cover in the app dismisses the same way, following iOS 26:
//
// 1. A sheet that only shows things (a report, the focus timer, a picker that applies a
//    choice as soon as it is tapped, the paywall) gets a close X: `Button(role: .close)`
//    in `.cancellationAction`. Use `.sheetCloseButton()`.
// 2. A sheet that edits or creates something gets a cancel X (`Button(role: .cancel)`,
//    also drawn as an X) in `.cancellationAction`, and a labelled confirm action such as
//    "Create" or "Save" (`role: .confirm`) in `.confirmationAction`.
//    Use `.sheetCancelConfirm("Save") { save() }`.
// 3. The X is always on the leading side, the confirm action always on the trailing side.
//    Other trailing items (Share) go in `.primaryAction`.
// 4. Popovers dismiss by tapping outside and get no X. When a popover adapts to a sheet
//    (accessibility text sizes, compact width), that sheet follows rule 1.
// 5. Alerts and confirmation dialogs keep their system text buttons ("Cancel", "Not yet").
//
// The X buttons use the system label, so VoiceOver reads "Close" or "Cancel" in the
// user's language, and carry the identifiers `closeButton` / `cancelButton` unless a
// screen passes its own (UI tests rely on a few existing ones).

extension View {
    /// Rule 1: a close X on the leading side for an overlay that only shows things.
    /// - Parameters:
    ///   - identifier: Accessibility identifier for UI tests.
    ///   - action: What the X does. Defaults to dismissing the presentation.
    public func sheetCloseButton(
        identifier: String = "closeButton",
        action: (() -> Void)? = nil
    ) -> some View {
        modifier(SheetDismissToolbar(role: .close, identifier: identifier, action: action))
    }

    /// Rule 2: a cancel X on the leading side plus a labelled confirm action on the
    /// trailing side, for an overlay that edits or creates something.
    /// - Parameters:
    ///   - confirmTitle: The confirm action's label, a verb ("Create", "Save", "Join").
    ///   - confirmIdentifier: Accessibility identifier of the confirm button.
    ///   - isEnabled: Whether the confirm action can run yet.
    ///   - isWorking: Shows a spinner in place of the confirm button while it runs.
    ///   - cancelIdentifier: Accessibility identifier of the X.
    ///   - hasChanges: The user typed or changed something. A drag can't close the sheet
    ///     then, and the X asks "Discard Changes?" first (like Notes and Reminders).
    ///   - onCancel: What the X does. Defaults to dismissing the presentation.
    ///   - onConfirm: The confirm action. It dismisses the sheet itself when it succeeds.
    public func sheetCancelConfirm(
        _ confirmTitle: LocalizedStringKey,
        confirmIdentifier: String? = nil,
        isEnabled: Bool = true,
        isWorking: Bool = false,
        hasChanges: Bool = false,
        cancelIdentifier: String = "cancelButton",
        onCancel: (() -> Void)? = nil,
        onConfirm: @escaping () -> Void
    ) -> some View {
        modifier(SheetDismissToolbar(role: .cancel, identifier: cancelIdentifier, action: onCancel, confirmDiscard: hasChanges))
            .interactiveDismissDisabled(hasChanges)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button(confirmTitle, role: .confirm, action: onConfirm)
                            .disabled(!isEnabled)
                            .accessibilityIdentifier(confirmIdentifier ?? "confirmButton")
                    }
                }
            }
    }
}

/// The leading X shared by both rules.
private struct SheetDismissToolbar: ViewModifier {
    let role: ButtonRole
    let identifier: String
    let action: (() -> Void)?
    var confirmDiscard = false

    @Environment(\.dismiss) private var dismiss
    @State private var askingToDiscard = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: role) {
                        if confirmDiscard { askingToDiscard = true } else { leave() }
                    }
                    .accessibilityIdentifier(identifier)
                }
            }
            .confirmationDialog("Discard changes?", isPresented: $askingToDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) { leave() }
                Button("Keep Editing", role: .cancel) {}
            }
    }

    private func leave() {
        if let action { action() } else { dismiss() }
    }
}
