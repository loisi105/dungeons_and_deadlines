import Foundation

/// Pure damage rules. Everything that decides "how hard did that hit" lives here.
public struct DamageCalculator: Sendable {
    public var config: DamageConfig
    public var calendar: Calendar

    public init(config: DamageConfig = .standard, calendar: Calendar = .current) {
        self.config = config
        self.calendar = calendar
    }

    /// Context the rules need about the raid and the member's history.
    public struct Context: Sendable {
        public var memberID: String
        /// All attacks in the raid so far (any member).
        public var attacks: [Attack]
        public var memberCount: Int
        public var lockedMaxHP: Int?
        public var now: Date

        public init(memberID: String, attacks: [Attack], memberCount: Int, lockedMaxHP: Int?, now: Date) {
            self.memberID = memberID
            self.attacks = attacks
            self.memberCount = memberCount
            self.lockedMaxHP = lockedMaxHP
            self.now = now
        }
    }

    public struct FocusResult: Sendable, Equatable {
        public var damage: Int
        /// Seconds that counted after the daily focus cap.
        public var creditedSeconds: Int
    }

    public func streakDays(_ context: Context) -> Int {
        Streaks.current(
            memberID: context.memberID, attacks: context.attacks, now: context.now,
            minimumMinutes: config.streakMinimumMinutes, calendar: calendar
        )
    }

    public func multiplier(_ context: Context) -> Double {
        config.multiplier(forStreak: streakDays(context))
    }

    public func taskDamage(size: TaskSize, context: Context) -> Int {
        let raw = Int((Double(config.baseDamage(for: size)) * multiplier(context)).rounded(.down))
        return applyPerMemberCap(raw, context: context)
    }

    public func focusDamage(seconds: Int, context: Context) -> FocusResult {
        let today = LocalDay.key(for: context.now, calendar: calendar)
        let usedToday = context.attacks
            .filter { $0.memberID == context.memberID && $0.localDay == today }
            .reduce(0) { $0 + $1.kind.focusSeconds }
        let remaining = max(0, config.dailyFocusCapMinutes * 60 - usedToday)
        let credited = min(max(0, seconds), remaining)
        let minutes = Double(credited) / 60
        let raw = Int((minutes * config.focusDamagePerMinute * multiplier(context)).rounded(.down))
        return FocusResult(damage: applyPerMemberCap(raw, context: context), creditedSeconds: credited)
    }

    /// Damage this member has dealt today (any kind).
    public func damageToday(_ context: Context) -> Int {
        let today = LocalDay.key(for: context.now, calendar: calendar)
        return context.attacks
            .filter { $0.memberID == context.memberID && $0.localDay == today }
            .reduce(0) { $0 + $1.damage }
    }

    /// Remaining focus minutes today under the cap.
    public func remainingFocusSeconds(_ context: Context) -> Int {
        let today = LocalDay.key(for: context.now, calendar: calendar)
        let used = context.attacks
            .filter { $0.memberID == context.memberID && $0.localDay == today }
            .reduce(0) { $0 + $1.kind.focusSeconds }
        return max(0, config.dailyFocusCapMinutes * 60 - used)
    }

    func applyPerMemberCap(_ raw: Int, context: Context) -> Int {
        guard context.memberCount >= 2,
              let fraction = config.perMemberDailyCapFraction,
              let maxHP = context.lockedMaxHP
        else { return raw }
        let cap = Int(Double(maxHP) * fraction)
        let remaining = max(0, cap - damageToday(context))
        return min(raw, remaining)
    }

    /// Builds the attack for a completed task, or nil if it would deal no damage.
    public func taskAttack(raidID: UUID, taskID: UUID, size: TaskSize, context: Context) -> Attack? {
        let damage = taskDamage(size: size, context: context)
        guard damage > 0 else { return nil }
        return Attack(
            raidID: raidID, memberID: context.memberID, kind: .task(taskID), damage: damage,
            createdAt: context.now, localDay: LocalDay.key(for: context.now, calendar: calendar)
        )
    }

    /// Builds the attack for a finished focus session, or nil if it would deal no damage.
    public func focusAttack(raidID: UUID, seconds: Int, context: Context) -> Attack? {
        let result = focusDamage(seconds: seconds, context: context)
        guard result.damage > 0 else { return nil }
        return Attack(
            raidID: raidID, memberID: context.memberID, kind: .focus(seconds: result.creditedSeconds),
            damage: result.damage, createdAt: context.now,
            localDay: LocalDay.key(for: context.now, calendar: calendar)
        )
    }
}
