import Foundation

/// Every tunable number in one place. Defaults match docs/IMPLEMENTATION_PLAN.md, Appendix B.
public struct DamageConfig: Sendable, Hashable, Codable {
    public var smallTaskDamage: Int
    public var mediumTaskDamage: Int
    public var largeTaskDamage: Int
    public var focusDamagePerMinute: Double
    public var dailyFocusCapMinutes: Int
    /// Share of max HP expected from tasks; max HP = task total / taskShare.
    public var taskShare: Double
    /// Minimum focus minutes on a day for it to count toward a streak.
    public var streakMinimumMinutes: Int
    /// (streak length in days, multiplier), highest first.
    public var streakSteps: [StreakStep]
    /// Per-member daily damage cap as a fraction of locked max HP (raids with >= 2 members only).
    public var perMemberDailyCapFraction: Double?
    public var maxMembers: Int

    public struct StreakStep: Sendable, Hashable, Codable {
        public var days: Int
        public var multiplier: Double
        public init(days: Int, multiplier: Double) {
            self.days = days
            self.multiplier = multiplier
        }
    }

    public init(
        smallTaskDamage: Int = 50,
        mediumTaskDamage: Int = 150,
        largeTaskDamage: Int = 400,
        focusDamagePerMinute: Double = 2,
        dailyFocusCapMinutes: Int = 180,
        taskShare: Double = 0.65,
        streakMinimumMinutes: Int = 30,
        streakSteps: [StreakStep] = [.init(days: 4, multiplier: 1.2), .init(days: 2, multiplier: 1.1)],
        perMemberDailyCapFraction: Double? = 0.25,
        maxMembers: Int = 5
    ) {
        self.smallTaskDamage = smallTaskDamage
        self.mediumTaskDamage = mediumTaskDamage
        self.largeTaskDamage = largeTaskDamage
        self.focusDamagePerMinute = focusDamagePerMinute
        self.dailyFocusCapMinutes = dailyFocusCapMinutes
        self.taskShare = taskShare
        self.streakMinimumMinutes = streakMinimumMinutes
        self.streakSteps = streakSteps.sorted { $0.days > $1.days }
        self.perMemberDailyCapFraction = perMemberDailyCapFraction
        self.maxMembers = maxMembers
    }

    public static let standard = DamageConfig()

    public func baseDamage(for size: TaskSize) -> Int {
        switch size {
        case .s: smallTaskDamage
        case .m: mediumTaskDamage
        case .l: largeTaskDamage
        }
    }

    public func multiplier(forStreak days: Int) -> Double {
        streakSteps.first { days >= $0.days }?.multiplier ?? 1.0
    }

    /// Largest damage a single attack can deal; mirrored in firestore.rules.
    public var maxSingleAttackDamage: Int {
        let top = streakSteps.map(\.multiplier).max() ?? 1
        let task = Double(max(smallTaskDamage, mediumTaskDamage, largeTaskDamage)) * top
        let focus = Double(dailyFocusCapMinutes) * focusDamagePerMinute * top
        return Int(max(task, focus))
    }
}
