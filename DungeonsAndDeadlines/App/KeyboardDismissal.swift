import UIKit

/// Tapping anywhere outside a text field hides the keyboard, on every screen and sheet.
///
/// A single tap recognizer on each app window ends editing. It never cancels the touch
/// (`cancelsTouchesInView = false`) and recognizes alongside every other gesture, so the
/// button, row or switch you tapped still works. Taps on text fields and text views are
/// ignored, so moving between fields keeps the keyboard up. The keyboard lives in its own
/// system window, so typing is unaffected.
final class KeyboardDismissal: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissal()
    private var windows = Set<ObjectIdentifier>()

    /// Adds the recognizer to app windows that don't have it yet. Safe to call repeatedly.
    func install() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for window in scenes.flatMap(\.windows) where window.windowLevel == .normal {
            let id = ObjectIdentifier(window)
            guard !windows.contains(id) else { continue }
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            windows.insert(id)
        }
    }

    @objc private func dismissKeyboard(_ recognizer: UITapGestureRecognizer) {
        recognizer.view?.endEditing(true)
    }

    // MARK: UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !Self.isTextInput(touch.view)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private static func isTextInput(_ view: UIView?) -> Bool {
        var current = view
        while let v = current {
            if v is UITextField || v is UITextView || v is UISearchBar { return true }
            current = v.superview
        }
        return false
    }
}
