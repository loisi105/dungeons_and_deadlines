import Foundation

public enum FocusTimerState: String, Codable, Sendable {
    case idle, running, paused
}

/// A focus timer that only stores timestamps, so it survives suspension and app kills.
/// Time away from the app counts as focus: iOS can't tell a locked phone from another
/// app, so the timer runs until the user pauses or stops it (the daily cap still applies).
public struct FocusSession: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var raidID: UUID
    public var memberID: String
    public var state: FocusTimerState
    /// Start of the current running stretch.
    public var startedAt: Date?
    /// Seconds from earlier stretches (before pauses).
    public var accumulatedSeconds: TimeInterval

    public init(
        id: UUID = UUID(), raidID: UUID, memberID: String, state: FocusTimerState = .idle,
        startedAt: Date? = nil, accumulatedSeconds: TimeInterval = 0
    ) {
        self.id = id
        self.raidID = raidID
        self.memberID = memberID
        self.state = state
        self.startedAt = startedAt
        self.accumulatedSeconds = accumulatedSeconds
    }

    public func elapsed(at now: Date) -> TimeInterval {
        guard state == .running, let startedAt else { return accumulatedSeconds }
        return accumulatedSeconds + max(0, now.timeIntervalSince(startedAt))
    }

    /// A reference date such that `now - reference == elapsed`, for `Text(timerInterval:)`.
    public func timerReferenceDate(at now: Date) -> Date {
        now.addingTimeInterval(-elapsed(at: now))
    }

    public mutating func start(at now: Date) {
        guard state != .running else { return }
        state = .running
        startedAt = now
    }

    public mutating func pause(at now: Date) {
        guard state == .running else { return }
        accumulatedSeconds = elapsed(at: now)
        startedAt = nil
        state = .paused
    }

    /// Ends the session and returns the total focused seconds.
    @discardableResult
    public mutating func stop(at now: Date) -> Int {
        let total = Int(elapsed(at: now).rounded(.down))
        state = .idle
        startedAt = nil
        accumulatedSeconds = 0
        return total
    }
}
