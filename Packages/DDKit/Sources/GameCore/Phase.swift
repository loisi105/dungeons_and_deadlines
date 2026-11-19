import Foundation

/// Boss phases, driven by the share of time left until the deadline.
public enum Phase: Int, Codable, Sendable, CaseIterable, Comparable {
    case calm = 1, angry, enraged, berserk

    public static func < (lhs: Phase, rhs: Phase) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Phase starts when the share of time left drops to or below this value.
    public var threshold: Double {
        switch self {
        case .calm: 1.0
        case .angry: 0.5
        case .enraged: 0.25
        case .berserk: 0.10
        }
    }

    public static func at(start: Date, deadline: Date, now: Date) -> Phase {
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return .berserk }
        let left = deadline.timeIntervalSince(now) / total
        if left <= Phase.berserk.threshold { return .berserk }
        if left <= Phase.enraged.threshold { return .enraged }
        if left <= Phase.angry.threshold { return .angry }
        return .calm
    }

    /// The moment this phase begins.
    public func startDate(start: Date, deadline: Date) -> Date {
        let total = deadline.timeIntervalSince(start)
        return deadline.addingTimeInterval(-total * threshold)
    }

    /// Next phase change after `now`, or nil if already in the last phase.
    public static func nextChange(start: Date, deadline: Date, after now: Date) -> Date? {
        Phase.allCases
            .map { $0.startDate(start: start, deadline: deadline) }
            .filter { $0 > now }
            .min()
    }
}
