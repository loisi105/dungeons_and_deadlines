import Foundation

public enum FocusTimerState: String, Codable, Sendable {
    case idle, running, paused
}

/// A focus timer that only stores timestamps, so it survives suspension and app kills.
public struct FocusSession: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var raidID: UUID
    public var memberID: String
    public var state: FocusTimerState
    /// Start of the current running stretch.
    public var startedAt: Date?
    /// Seconds from earlier stretches (before pauses).
    public var accumulatedSeconds: TimeInterval
    /// When the app went to the background while running.
    public var backgroundedAt: Date?

    public init(
        id: UUID = UUID(), raidID: UUID, memberID: String, state: FocusTimerState = .idle,
        startedAt: Date? = nil, accumulatedSeconds: TimeInterval = 0, backgroundedAt: Date? = nil
    ) {
        self.id = id
        self.raidID = raidID
        self.memberID = memberID
        self.state = state
        self.startedAt = startedAt
        self.accumulatedSeconds = accumulatedSeconds
        self.backgroundedAt = backgroundedAt
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
        backgroundedAt = nil
    }

    public mutating func pause(at now: Date) {
        guard state == .running else { return }
        accumulatedSeconds = elapsed(at: now)
        startedAt = nil
        state = .paused
        backgroundedAt = nil
    }

    /// Ends the session and returns the total focused seconds.
    @discardableResult
    public mutating func stop(at now: Date) -> Int {
        let total = Int(elapsed(at: now).rounded(.down))
        state = .idle
        startedAt = nil
        accumulatedSeconds = 0
        backgroundedAt = nil
        return total
    }

    public mutating func markBackgrounded(at now: Date) {
        guard state == .running else { return }
        backgroundedAt = now
    }

    /// Applies the background rule. If the app was away longer than `grace`,
    /// the session is paused as of the moment it left. Returns true if it paused.
    @discardableResult
    public mutating func resumeFromBackground(at now: Date, grace: TimeInterval) -> Bool {
        guard state == .running, let left = backgroundedAt else {
            backgroundedAt = nil
            return false
        }
        backgroundedAt = nil
        if now.timeIntervalSince(left) > grace {
            pause(at: left)
            return true
        }
        return false
    }
}
