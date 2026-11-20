import DeviceActivity
import DDScreenTime

/// The safety net for "Block apps while focusing". The app schedules `focusSafetyNet` to end
/// at the daily focus cap or at midnight; when it ends, the system runs this extension, which
/// lifts the shield even if the app was killed with the timer still running.
final class FocusMonitorExtension: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == .focusSafetyNet else { return }
        ScreenTimeShield.clearShield()
    }
}
