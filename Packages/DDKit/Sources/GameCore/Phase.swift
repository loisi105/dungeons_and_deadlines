import Foundation

/// Boss phases, driven by the share of time left until the deadline.
///
/// The raid leader can shift the whole timeline by whole steps (`Raid.phaseShift`):
/// +1 means "one step angrier than the deadline says" — Angry right away, Enraged when
/// Angry would have started, and so on, capped at Berserk. −1 works the other way, floored at Calm.
public enum Phase: Int, Codable, Sendable, CaseIterable, Comparable {
    case calm = 1, angry, enraged, berserk

    public static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }

    /// How far a raid's phases can be shifted in either direction.
    public static let shiftRange: ClosedRange<Int> = -3...3

    /// `shift` limited to `shiftRange`.
    public static func clampShift(_ shift: Int) -> Int {
        min(max(shift, shiftRange.lowerBound), shiftRange.upperBound)
    }

    /// Phase starts when the share of time left drops to or below this value.
    public var threshold: Double {
        switch self {
        case .calm: 1.0
        case .angry: 0.5
        case .enraged: 0.25
        case .berserk: 0.10
        }
    }

    /// This phase moved `shift` steps, clamped to calm...berserk.
    public func shifted(by shift: Int) -> Phase {
        let raw = min(max(rawValue + shift, Phase.calm.rawValue), Phase.berserk.rawValue)
        return Phase(rawValue: raw) ?? self
    }

    /// The phase at `now`: the time-based phase moved by `shift` steps, clamped to calm...berserk.
    public static func at(start: Date, deadline: Date, now: Date, shift: Int = 0) -> Phase {
        natural(start: start, deadline: deadline, now: now).shifted(by: shift)
    }

    /// The phase from the time rule alone: the highest phase that has started by `now`.
    /// Uses the same arithmetic as `startDate(start:deadline:)`, so at a change date from
    /// `nextEffectiveChange` the phase is already the new one (no floating-point gap).
    static func natural(start: Date, deadline: Date, now: Date) -> Phase {
        guard deadline > start else { return .berserk }
        return Phase.allCases
            .filter { $0 != .calm }
            .last { $0.startDate(start: start, deadline: deadline) <= now } ?? .calm
    }

    /// The moment this phase begins (by the time rule, unshifted).
    public func startDate(start: Date, deadline: Date) -> Date {
        let total = deadline.timeIntervalSince(start)
        return deadline.addingTimeInterval(-total * threshold)
    }

    /// The next moment after `now` when the shifted phase changes, or nil if it won't change
    /// again before the deadline. Time-based changes that don't change the shifted phase
    /// (because it's already capped at Berserk) are skipped.
    public static func nextChange(start: Date, deadline: Date, after now: Date, shift: Int = 0) -> Date? {
        nextEffectiveChange(start: start, deadline: deadline, after: now, shift: shift)?.date
    }

    /// The next shifted-phase change and the phase it changes to.
    public static func nextEffectiveChange(start: Date, deadline: Date, after now: Date, shift: Int = 0) -> (date: Date, phase: Phase)? {
        guard deadline > start else { return nil }
        let current = at(start: start, deadline: deadline, now: now, shift: shift)
        let upcoming = Phase.allCases
            .filter { $0 != .calm }
            .map { (date: $0.startDate(start: start, deadline: deadline), phase: $0.shifted(by: shift)) }
            .filter { $0.date > now }
            .sorted { $0.date < $1.date }
        // Phases only ever rise over time, so the first one above the current phase is the change.
        return upcoming.first { $0.phase > current }
    }
}

extension Raid {
    /// When the phase timeline starts: the fight start, or creation while planning.
    public var phaseStart: Date { startedAt ?? createdAt }

    /// The boss's phase at `now`, including the leader's shift.
    public func phase(at now: Date) -> Phase {
        Phase.at(start: phaseStart, deadline: deadline, now: now, shift: phaseShift)
    }

    /// The next phase change after `now` (including the leader's shift), or nil if none before the deadline.
    public func nextPhaseChange(after now: Date) -> (date: Date, phase: Phase)? {
        Phase.nextEffectiveChange(start: phaseStart, deadline: deadline, after: now, shift: phaseShift)
    }
}
