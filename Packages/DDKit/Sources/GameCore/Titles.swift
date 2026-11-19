import Foundation

public enum Title: String, Codable, Sendable, CaseIterable, Identifiable {
    case mvp, sniper, grinder, consistent, lastMinuteHero, afkLegend
    public var id: String { rawValue }
}

public struct RaidReport: Sendable {
    public struct Row: Identifiable, Sendable {
        public var member: Member
        public var stats: MemberStats
        public var titles: [Title]
        public var longestStreak: Int
        public var id: String { member.id }
    }

    public var raid: Raid
    public var state: BossState
    public var rows: [Row]
    public var lateTasks: [RaidTask]
    public var openTasks: [RaidTask]
    public var timeline: [(date: Date, hp: Int)]
    public var highestPhase: Phase
}

public enum Titles {
    /// Awards each title to at most one member. Ties go to the member who joined first,
    /// then by ID, so every device computes the same result.
    public static func award(
        raid: Raid, members: [Member], attacks: [Attack], config: DamageConfig = .standard,
        calendar: Calendar = .current
    ) -> [Title: String] {
        let raidAttacks = attacks.filter { $0.raidID == raid.id }
        let stats = Dictionary(uniqueKeysWithValues: BossEngine.memberStats(attacks: raidAttacks).map { ($0.memberID, $0) })
        let ordered = members.sorted { ($0.joinedAt, $0.id) < ($1.joinedAt, $1.id) }
        func stat(_ m: Member) -> MemberStats { stats[m.id] ?? MemberStats(memberID: m.id) }

        func best(_ value: (Member) -> Int) -> String? {
            var winner: Member?
            var top = 0
            for m in ordered where value(m) > top {
                top = value(m)
                winner = m
            }
            return winner?.id
        }

        var result: [Title: String] = [:]
        result[.mvp] = best { stat($0).total }
        result[.sniper] = best { stat($0).burst }
        result[.grinder] = best { stat($0).focusSeconds }
        result[.consistent] = best {
            Streaks.longest(memberID: $0.id, attacks: raidAttacks, minimumMinutes: config.streakMinimumMinutes, calendar: calendar)
        }

        if let start = raid.startedAt {
            let berserkStart = Phase.berserk.startDate(start: start, deadline: raid.deadline)
            let late = raidAttacks.filter { $0.createdAt >= berserkStart }
            result[.lastMinuteHero] = best { m in late.filter { $0.memberID == m.id }.reduce(0) { $0 + $1.damage } }
        }

        if ordered.count >= 2 {
            var lowest: Member?
            var minValue = Int.max
            for m in ordered where stat(m).total < minValue {
                minValue = stat(m).total
                lowest = m
            }
            if let lowest, lowest.id != result[.mvp] { result[.afkLegend] = lowest.id }
        }
        return result
    }

    public static func report(
        raid: Raid, members: [Member], tasks: [RaidTask], attacks: [Attack], now: Date,
        config: DamageConfig = .standard, calendar: Calendar = .current
    ) -> RaidReport {
        let state = BossEngine.state(raid: raid, tasks: tasks, attacks: attacks, now: now, config: config)
        let awards = award(raid: raid, members: members, attacks: attacks, config: config, calendar: calendar)
        let raidAttacks = attacks.filter { $0.raidID == raid.id }
        let rows = members.map { member in
            RaidReport.Row(
                member: member,
                stats: state.memberStats.first { $0.memberID == member.id } ?? MemberStats(memberID: member.id),
                titles: Title.allCases.filter { awards[$0] == member.id },
                longestStreak: Streaks.longest(memberID: member.id, attacks: raidAttacks, minimumMinutes: config.streakMinimumMinutes, calendar: calendar)
            )
        }.sorted { $0.stats.total != $1.stats.total ? $0.stats.total > $1.stats.total : $0.member.id < $1.member.id }

        let raidTasks = tasks.filter { $0.raidID == raid.id }
        let end = min(now, raid.deadline)
        let highest = raid.startedAt.map { Phase.at(start: $0, deadline: raid.deadline, now: end) } ?? .calm
        return RaidReport(
            raid: raid, state: state, rows: rows,
            lateTasks: raidTasks.filter { $0.isLate(startedAt: raid.startedAt) },
            openTasks: raidTasks.filter { !$0.isDone },
            timeline: BossEngine.hpTimeline(raid: raid, attacks: attacks),
            highestPhase: highest
        )
    }
}
