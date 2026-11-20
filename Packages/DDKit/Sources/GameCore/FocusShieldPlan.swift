import Foundation

/// Whether apps the player picked should be blocked (Screen Time shield) right now, and until when.
///
/// The shield follows the focus timer: on while it runs, off when it's paused or stopped.
/// It also ends when today's focus cap runs out or the day ends, so a timer left running
/// can't block apps forever (a DeviceActivity schedule enforces that end even if the app is killed).
public enum FocusShieldPlan: Equatable, Sendable {
    case off
    case on(until: Date)

    /// Apple's DeviceActivity schedules must be at least 15 minutes long.
    public static let minimumScheduleSeconds: TimeInterval = 15 * 60

    /// - Parameters:
    ///   - remainingCapSeconds: focus seconds still credited today, not counting the running session.
    public static func decide(
        enabled: Bool, hasSelection: Bool, session: FocusSession?,
        remainingCapSeconds: Int, now: Date, calendar: Calendar = .current
    ) -> FocusShieldPlan {
        guard enabled, hasSelection, let session, session.state == .running else { return .off }
        let capEnd = now.addingTimeInterval(TimeInterval(remainingCapSeconds) - session.elapsed(at: now))
        let dayEnd = calendar.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86_400)
        let until = min(capEnd, dayEnd)
        return until > now ? .on(until: until) : .off
    }

    /// The window for the safety-net schedule: ends at `until`, and starts early enough to be
    /// at least `minimumScheduleSeconds` long (a start in the past is fine), but not before
    /// the start of `until`'s day, so the schedule never crosses midnight.
    public static func safetyNetInterval(until: Date, now: Date, calendar: Calendar = .current) -> DateInterval {
        let dayStart = calendar.startOfDay(for: until == calendar.startOfDay(for: until) ? until.addingTimeInterval(-1) : until)
        var start = min(now, until.addingTimeInterval(-minimumScheduleSeconds))
        start = max(start, dayStart)
        var end = until
        if end.timeIntervalSince(start) < minimumScheduleSeconds {
            end = start.addingTimeInterval(minimumScheduleSeconds)
        }
        return DateInterval(start: start, end: end)
    }
}
