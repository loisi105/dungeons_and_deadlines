import Foundation

public enum Outcome: String, Codable, Sendable {
    case planning, ongoing, won, lost
}

public struct MemberStats: Identifiable, Sendable, Hashable {
    public var memberID: String
    /// Damage from completed tasks.
    public var burst: Int
    /// Damage from focus time.
    public var sustained: Int
    public var focusSeconds: Int
    public var tasksCompleted: Int
    public var id: String { memberID }
    public var total: Int { burst + sustained }

    public init(memberID: String, burst: Int = 0, sustained: Int = 0, focusSeconds: Int = 0, tasksCompleted: Int = 0) {
        self.memberID = memberID
        self.burst = burst
        self.sustained = sustained
        self.focusSeconds = focusSeconds
        self.tasksCompleted = tasksCompleted
    }
}

public struct BossState: Sendable, Hashable {
    /// Locked max HP once active; the predicted value while planning.
    public var maxHP: Int
    public var currentHP: Int
    public var phase: Phase
    public var outcome: Outcome
    public var totalDamage: Int
    /// Sorted by total damage, highest first.
    public var memberStats: [MemberStats]

    public init(maxHP: Int, currentHP: Int, phase: Phase, outcome: Outcome, totalDamage: Int, memberStats: [MemberStats]) {
        self.maxHP = maxHP
        self.currentHP = currentHP
        self.phase = phase
        self.outcome = outcome
        self.totalDamage = totalDamage
        self.memberStats = memberStats
    }

    public var fraction: Double { maxHP > 0 ? Double(currentHP) / Double(maxHP) : 0 }
    public var percent: Int { Int((fraction * 100).rounded()) }
}

public enum BossEngine {
    /// Max HP from the planned tasks: ~65% from tasks, ~35% expected from focus time.
    public static func lockHP(tasks: [RaidTask], config: DamageConfig = .standard) -> Int {
        let taskTotal = tasks.reduce(0) { $0 + config.baseDamage(for: $1.size) }
        guard taskTotal > 0 else { return 0 }
        return Int((Double(taskTotal) / config.taskShare).rounded(.up))
    }

    public static func state(
        raid: Raid, tasks: [RaidTask], attacks: [Attack], now: Date, config: DamageConfig = .standard
    ) -> BossState {
        let raidAttacks = attacks.filter { $0.raidID == raid.id }
        let stats = memberStats(attacks: raidAttacks)
        let total = raidAttacks.reduce(0) { $0 + $1.damage }

        guard raid.status != .planning, let maxHP = raid.lockedMaxHP else {
            let predicted = lockHP(tasks: tasks.filter { $0.raidID == raid.id }, config: config)
            return BossState(
                maxHP: predicted, currentHP: predicted, phase: .calm,
                outcome: .planning, totalDamage: 0, memberStats: stats
            )
        }

        let current = max(0, maxHP - total)
        let outcome: Outcome
        if current == 0 {
            outcome = .won
        } else if now >= raid.deadline || raid.status == .lost {
            outcome = .lost
        } else {
            outcome = .ongoing
        }
        let phase = Phase.at(start: raid.startedAt ?? raid.createdAt, deadline: raid.deadline, now: now)
        return BossState(
            maxHP: maxHP, currentHP: current, phase: phase, outcome: outcome,
            totalDamage: total, memberStats: stats
        )
    }

    public static func memberStats(attacks: [Attack]) -> [MemberStats] {
        var byMember: [String: MemberStats] = [:]
        for attack in attacks {
            var s = byMember[attack.memberID] ?? MemberStats(memberID: attack.memberID)
            switch attack.kind {
            case .task:
                s.burst += attack.damage
                s.tasksCompleted += 1
            case .focus(let seconds):
                s.sustained += attack.damage
                s.focusSeconds += seconds
            }
            byMember[attack.memberID] = s
        }
        return byMember.values.sorted {
            $0.total != $1.total ? $0.total > $1.total : $0.memberID < $1.memberID
        }
    }

    /// HP after each attack, oldest first, starting with full HP at the fight start.
    public static func hpTimeline(raid: Raid, attacks: [Attack]) -> [(date: Date, hp: Int)] {
        guard let maxHP = raid.lockedMaxHP, let start = raid.startedAt else { return [] }
        var hp = maxHP
        var points: [(date: Date, hp: Int)] = [(start, hp)]
        for attack in attacks.filter({ $0.raidID == raid.id }).sorted(by: { $0.createdAt < $1.createdAt }) {
            hp = max(0, hp - attack.damage)
            points.append((attack.createdAt, hp))
        }
        return points
    }
}
