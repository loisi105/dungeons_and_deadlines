import UIKit

/// Tapping anywhere outside a text field hides the keyboard, on every screen and sheet.
///
/// A single tap recognizer on each app window ends editing. It never cancels the touch
/// (`cancelsTouchesInView = false`) and recognizes alongside every other gesture, so the
/// button, row or switch you tapped still works. Taps on text fields, text views and segmented
/// controls, switches, sliders and steppers are ignored, so moving between fields keeps the keyboard up. The keyboard lives in its own
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
        // Not on text fields (keep typing) and not on real controls such as the size picker: hiding the
        // keyboard there lets the half sheet shrink under the finger, and the tap is lost.
        !Self.isTextInput(touch.view) && !Self.isControl(touch.view)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    private static func isControl(_ view: UIView?) -> Bool {
        var current = view
        while let v = current {
            if v is UISegmentedControl || v is UISwitch || v is UISlider || v is UIStepper { return true }
            current = v.superview
        }
        return false
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
