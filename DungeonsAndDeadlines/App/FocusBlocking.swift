import SwiftUI
import UIKit
import FamilyControls
import DDDesign
import DDIntents
import DDScreenTime

/// The real shielder behind `FocusShield`: ManagedSettings plus the DeviceActivity safety net
/// (`ScreenTimeShield`). Set in `AppEnvironment.bootstrap()`, never in `-uiTesting`.
final class AppFocusShielder: FocusShielding {
    /// Side of the boss icon the shield screen shows, in pixels (64-pixel art, scaled 3×).
    static let iconSize = 192

    func engage(until: Date, bossName: String) -> Bool {
        guard ScreenTimeShield.isAuthorized else { return false }
        Self.writeBossIcon(bossName: bossName)
        return ScreenTimeShield.engage(until: until, bossName: bossName)
    }

    func release() {
        ScreenTimeShield.release()
    }

    /// Writes the boss art as a PNG to the App Group, where the shield configuration
    /// extension loads it. Scaled with nearest-neighbour so the pixels stay crisp.
    /// On any failure the shield screen just shows no boss.
    static func writeBossIcon(bossName: String) {
        guard let url = ScreenTimeShield.bossIconURL,
              let art = BossKind.forName(bossName).art.cgImage() else { return }
        let side = CGFloat(iconSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let png = renderer.pngData { context in
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: art).draw(in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        try? png.write(to: url, options: .atomic)
    }
}

/// "Block apps while focusing": the setting, the picked apps and Screen Time permission,
/// shared by the Party tab's settings row and the focus timer's shortcut.
///
/// The shield itself follows the focus timer through `FocusShield.reconcile()` (called by
/// `GameActions.changed`), so this only changes the setting and the selection and then
/// re-checks the shield, which makes a running timer pick up the change at once.
@MainActor
@Observable
final class FocusBlocking {
    /// Where the app picker is shown from. The focus timer is a sheet, so it presents its
    /// own picker; everything else uses the one at the app's root.
    enum PickerPlace {
        case root, focusTimer
    }

    /// Mirrors `FocusBlockSettings.isEnabled`.
    private(set) var isEnabled = FocusBlockSettings.isEnabled
    /// The apps, categories and websites to block. Saved to the App Group on change.
    var selection: FamilyActivitySelection {
        didSet { save() }
    }
    private(set) var pickedCount: Int
    /// Screen Time access was declined (or turned off later) while blocking is wanted.
    private(set) var isDenied = false
    /// Why access couldn't be granted, in words the player can act on (shown with `isDenied`).
    private(set) var deniedMessage = FocusBlocking.accessOffMessage

    static let accessOffMessage = String(localized: "Screen Time access is off for Dungeons & Deadlines. Turn it on in Settings > Screen Time > Apps with Screen Time Access.")
    /// Asking for Screen Time access; the toggle shows on meanwhile.
    private(set) var isTurningOn = false
    /// Which picker is open, if any.
    var showPicker: PickerPlace?

    init() {
        let selection = ScreenTimeShield.selection
        self.selection = selection
        pickedCount = ScreenTimeShield.pickedCount(selection)
        refreshAuthorization()
    }

    /// Turns blocking on: asks for Screen Time access first. If declined, it stays off and
    /// the settings row explains where to turn access on. Opens the picker when nothing is
    /// picked yet. In `-uiTesting` it only flips the setting.
    func turnOn(from place: PickerPlace = .root) async {
        guard !isTurningOn else { return }
        if LaunchOptions.isUITesting {
            setEnabled(true)
            return
        }
        isTurningOn = true
        defer { isTurningOn = false }
        guard await authorize() else {
            setEnabled(false) // stays off until access works
            return
        }
        setEnabled(true)
        if pickedCount == 0 { showPicker = place }
    }

    func turnOff() {
        setEnabled(false)
    }

    /// Opens the app picker, asking for Screen Time access first if needed.
    /// Does nothing in `-uiTesting`.
    func choose(from place: PickerPlace = .root) async {
        guard !LaunchOptions.isUITesting else { return }
        guard await authorize() else { return }
        FocusShield.reconcile() // access may be new: put up a shield that couldn't go up before
        showPicker = place
    }

    /// Re-reads Screen Time access (the person may have changed it in Settings).
    /// Called when the app becomes active.
    func refreshAuthorization() {
        guard !LaunchOptions.isUITesting else { return }
        if ScreenTimeShield.isAuthorized {
            isDenied = false
            FocusShield.reconcile() // access granted in Settings while a timer runs
        } else if isEnabled {
            deniedMessage = Self.accessOffMessage
            isDenied = true
        }
    }

    /// Asks for Screen Time access. On failure sets `isDenied` and a message that says what to do.
    private func authorize() async -> Bool {
        do {
            try await ScreenTimeShield.requestAuthorization()
            isDenied = false
            return true
        } catch {
            deniedMessage = Self.message(for: error)
            isDenied = true
            return false
        }
    }

    /// A readable reason for a failed Screen Time authorization.
    static func message(for error: Error) -> String {
        guard let error = error as? FamilyControlsError else {
            if error is ScreenTimeShield.AuthorizationFailure { return accessOffMessage }
            let ns = error as NSError
            return String(localized: "Screen Time access failed (\(ns.domain) \(ns.code)): \(error.localizedDescription)")
        }
        switch error {
        case .authorizationCanceled:
            return String(localized: "Screen Time access wasn't allowed. Turn the setting on again to retry, or allow it in Settings > Screen Time > Apps with Screen Time Access.")
        case .restricted:
            return String(localized: "Screen Time access is restricted on this device, e.g. by Content & Privacy Restrictions or a device management profile.")
        case .unavailable:
            return String(localized: "Screen Time isn't available. Turn on Screen Time in Settings, and make sure you're signed in with your Apple Account.")
        case .invalidAccountType:
            return String(localized: "This Apple Account can't give Screen Time access (for example, a Managed Apple Account).")
        case .invalidArgument:
            return String(localized: "This build of the app isn't set up for Screen Time: the Family Controls capability is missing from its signing profile. Rebuild it from Xcode with the FH team.")
        case .authorizationConflict:
            return String(localized: "Another app already manages Screen Time on this device. Remove its access in Settings > Screen Time, then try again.")
        case .networkError:
            return String(localized: "Couldn't reach Apple to confirm Screen Time access. Check your internet connection and try again.")
        case .authenticationMethodUnavailable:
            return String(localized: "Set a device passcode (Settings > Face ID & Passcode) to allow Screen Time access.")
        case .unauthorized:
            return String(localized: "Screen Time access isn't allowed for this app yet. Turn the setting on and choose Continue when iOS asks, or allow it in Settings > Screen Time > Apps with Screen Time Access.")
        @unknown default:
            return String(localized: "Screen Time access failed: \(error.localizedDescription)")
        }
    }

    /// Whether the picker for `place` is open.
    func isPickerShown(_ place: PickerPlace) -> Binding<Bool> {
        Binding(
            get: { self.showPicker == place },
            set: { shown in
                if shown {
                    self.showPicker = place
                } else if self.showPicker == place {
                    self.showPicker = nil
                }
            }
        )
    }

    private func setEnabled(_ on: Bool) {
        FocusBlockSettings.isEnabled = on
        isEnabled = on
        applyToShield()
    }

    private func save() {
        guard !LaunchOptions.isUITesting else { return }
        ScreenTimeShield.selection = selection
        pickedCount = ScreenTimeShield.pickedCount(selection)
        applyToShield()
    }

    /// Re-applies the shield even if the plan didn't change (a new selection must reach
    /// ManagedSettings while a timer runs).
    private func applyToShield() {
        FocusShield.invalidate()
        FocusShield.reconcile()
    }
}

extension View {
    /// The Screen Time app picker for "Block apps while focusing", presented from `place`.
    func focusBlockPicker(_ place: FocusBlocking.PickerPlace, blocking: FocusBlocking) -> some View {
        familyActivityPicker(
            headerText: String(localized: "Pick apps, categories or websites to block while you focus."),
            footerText: String(localized: "They stay blocked while your focus timer runs."),
            isPresented: blocking.isPickerShown(place),
            selection: Binding(get: { blocking.selection }, set: { blocking.selection = $0 })
        )
    }
}

/// "Block apps while focusing" for the Party tab's settings, next to Phase alerts.
/// Turning it on asks for Screen Time access; when on, a row opens the app picker.
/// The picker itself is attached at the app's root, so list refreshes can't dismiss it.
struct FocusBlockingSetting: View {
    @Environment(FocusBlocking.self) private var blocking
    @Environment(\.openURL) private var openURL

    var body: some View {
        Toggle("Block apps while focusing", isOn: Binding(
            get: { blocking.isEnabled || blocking.isTurningOn },
            set: { on in
                if on {
                    Task { await blocking.turnOn() }
                } else {
                    blocking.turnOff()
                }
            }
        ))
        .accessibilityHint("Blocks the apps you pick while your focus timer runs.")
        .accessibilityIdentifier("focusBlockToggle")

        if blocking.isEnabled {
            Button {
                Task { await blocking.choose() }
            } label: {
                HStack {
                    Text("Apps to block")
                    Spacer()
                    Group {
                        if blocking.pickedCount > 0 {
                            Text("\(blocking.pickedCount) picked")
                        } else {
                            Text("None picked")
                        }
                    }
                    .foregroundStyle(.readableSecondary)
                    .multilineTextAlignment(.trailing)
                }
                .contentShape(.rect)
            }
            .foregroundStyle(Theme.ink)
            .accessibilityHint("Opens the list of apps, categories and websites to block.")
            .accessibilityIdentifier("focusBlockPickButton")
        }

        if blocking.isDenied {
            Text(blocking.deniedMessage)
                .readableFootnote()
                .accessibilityIdentifier("focusBlockDeniedNote")
            Button("Open Settings", systemImage: "gear") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        }
    }
}
