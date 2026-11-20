import Foundation
import GameCore
import DDPersistence
#if os(iOS)
import FamilyControls
import ManagedSettings
import DeviceActivity
#endif

/// Screen Time blocking while focusing: the shield (ManagedSettings), the safety-net schedule
/// (DeviceActivity) and the picked apps. Shared by the app, the DeviceActivity monitor extension
/// and the shield configuration extension. Screen Time APIs exist on iOS only.
public enum ScreenTimeShield {
    /// The boss the shield screen names ("<boss> is still standing").
    public static let bossNameKey = "screenTime.shield.bossName"

    /// The boss art the shield screen shows, written by the app when the shield goes up.
    public static var bossIconURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appendingPathComponent("shield-boss.png")
    }

    public static var bossName: String? {
        AppGroup.defaults.string(forKey: bossNameKey)
    }
}

#if os(iOS)
extension ManagedSettingsStore.Name {
    /// The app's own settings store, so clearing it never touches other apps' restrictions.
    public static var dungeonsFocus: Self { Self("dungeonsFocus") }
}

extension DeviceActivityName {
    /// Ends at the daily focus cap or at midnight; its `intervalDidEnd` lifts the shield.
    public static var focusSafetyNet: Self { Self("focusSafetyNet") }
}

extension ScreenTimeShield {
    // MARK: Picked apps

    /// The apps, categories and websites to block, saved as JSON in the App Group.
    /// Saving also updates `settings.focusBlock.pickedCount`, which DDIntents reads.
    public static var selection: FamilyActivitySelection {
        get {
            guard let data = AppGroup.defaults.data(forKey: selectionKey),
                  let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return selection
        }
        set {
            AppGroup.defaults.set(try? JSONEncoder().encode(newValue), forKey: selectionKey)
            AppGroup.defaults.set(pickedCount(newValue), forKey: pickedCountKey)
        }
    }

    // Same keys as DDIntents.FocusBlockSettings (DDScreenTime doesn't link DDIntents,
    // so the extensions stay small).
    static let selectionKey = "settings.focusBlock.selection"
    static let pickedCountKey = "settings.focusBlock.pickedCount"

    public static func pickedCount(_ selection: FamilyActivitySelection) -> Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    // MARK: Authorization

    public static var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Asks for Screen Time access for this person's own device (no parent needed).
    /// Returns false if they declined or Screen Time isn't available.
    @MainActor
    public static func requestAuthorization() async -> Bool {
        if isAuthorized { return true }
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            return false
        }
        return isAuthorized
    }

    // MARK: Shield on and off

    /// Blocks the picked apps and schedules the safety net that lifts the block at `until`.
    @MainActor
    public static func engage(until: Date, bossName: String, now: Date = .now) {
        guard isAuthorized else { return }
        let picked = selection
        let store = ManagedSettingsStore(named: .dungeonsFocus)
        store.shield.applications = picked.applicationTokens.isEmpty ? nil : picked.applicationTokens
        store.shield.applicationCategories = picked.categoryTokens.isEmpty ? nil : .specific(picked.categoryTokens)
        store.shield.webDomains = picked.webDomainTokens.isEmpty ? nil : picked.webDomainTokens
        store.shield.webDomainCategories = picked.categoryTokens.isEmpty ? nil : .specific(picked.categoryTokens)
        AppGroup.defaults.set(bossName, forKey: bossNameKey)
        scheduleSafetyNet(until: until, now: now)
    }

    /// Lifts the block and cancels the safety net.
    @MainActor
    public static func release() {
        DeviceActivityCenter().stopMonitoring([.focusSafetyNet])
        clearShield()
    }

    /// Lifts the block. Safe to call from the monitor extension.
    public static func clearShield() {
        ManagedSettingsStore(named: .dungeonsFocus).clearAllSettings()
    }

    /// A one-off schedule ending at `until` (at least 15 minutes long, inside one day). Its
    /// `intervalDidEnd` runs in the monitor extension and clears the shield even if the app is gone.
    @MainActor
    static func scheduleSafetyNet(until: Date, now: Date) {
        let calendar = Calendar.current
        let window = FocusShieldPlan.safetyNetInterval(until: until, now: now, calendar: calendar)
        // Hour/minute/second only, so both ends must be on the same day: midnight becomes 23:59:59.
        var end = window.end
        if end == calendar.startOfDay(for: end) { end = end.addingTimeInterval(-1) }
        let parts: Set<Calendar.Component> = [.hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: window.start),
            intervalEnd: calendar.dateComponents(parts, from: end),
            repeats: false
        )
        let center = DeviceActivityCenter()
        center.stopMonitoring([.focusSafetyNet])
        do {
            try center.startMonitoring(.focusSafetyNet, during: schedule)
        } catch {
            // The shield still follows the timer while the app runs, and the app re-checks it
            // at launch; only the "app was killed" safety net is missing.
            print("Screen Time safety net not scheduled: \(error)")
        }
    }
}
#endif
