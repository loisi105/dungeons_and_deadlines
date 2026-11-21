import Foundation

/// Game Center achievements. Raw values are the IDs to create in App Store Connect
/// (see docs/GAME_CENTER.md).
public enum Achievement: String, CaseIterable, Sendable {
    case firstBlood = "at.fhooe.sail.dungeonsanddeadlines.achievement.first_blood"
    case firstVictory = "at.fhooe.sail.dungeonsanddeadlines.achievement.first_victory"
    case slayer5 = "at.fhooe.sail.dungeonsanddeadlines.achievement.slayer_5"
    case slayer25 = "at.fhooe.sail.dungeonsanddeadlines.achievement.slayer_25"
    case focus10h = "at.fhooe.sail.dungeonsanddeadlines.achievement.focus_10h"
    case streak7 = "at.fhooe.sail.dungeonsanddeadlines.achievement.streak_7"
    case flawless = "at.fhooe.sail.dungeonsanddeadlines.achievement.flawless"
    case fullParty = "at.fhooe.sail.dungeonsanddeadlines.achievement.full_party"
    case mvp = "at.fhooe.sail.dungeonsanddeadlines.achievement.title_mvp"
    case sniper = "at.fhooe.sail.dungeonsanddeadlines.achievement.title_sniper"
    case grinder = "at.fhooe.sail.dungeonsanddeadlines.achievement.title_grinder"
    case consistent = "at.fhooe.sail.dungeonsanddeadlines.achievement.title_consistent"
    case lastMinuteHero = "at.fhooe.sail.dungeonsanddeadlines.achievement.title_last_minute_hero"
    case tasks10 = "at.fhooe.sail.dungeonsanddeadlines.achievement.tasks_10"
    case tasks100 = "at.fhooe.sail.dungeonsanddeadlines.achievement.tasks_100"
    case bigOne = "at.fhooe.sail.dungeonsanddeadlines.achievement.big_one"
    case cleanSweep = "at.fhooe.sail.dungeonsanddeadlines.achievement.clean_sweep"
    case focusFirst = "at.fhooe.sail.dungeonsanddeadlines.achievement.focus_first"
    case focusMarathon = "at.fhooe.sail.dungeonsanddeadlines.achievement.focus_marathon"
    case nightOwl = "at.fhooe.sail.dungeonsanddeadlines.achievement.focus_night_owl"
    case earlyBird = "at.fhooe.sail.dungeonsanddeadlines.achievement.focus_early_bird"
    case streak30 = "at.fhooe.sail.dungeonsanddeadlines.achievement.streak_30"
    case aheadOfSchedule = "at.fhooe.sail.dungeonsanddeadlines.achievement.ahead_of_schedule"
    case speedrun = "at.fhooe.sail.dungeonsanddeadlines.achievement.speedrun"
    case buzzerBeater = "at.fhooe.sail.dungeonsanddeadlines.achievement.buzzer_beater"
    case bestiary = "at.fhooe.sail.dungeonsanddeadlines.achievement.bestiary"
    case teamPlayer = "at.fhooe.sail.dungeonsanddeadlines.achievement.team_player"
    case carry = "at.fhooe.sail.dungeonsanddeadlines.achievement.carry"
    case delegator = "at.fhooe.sail.dungeonsanddeadlines.achievement.delegator"
}

/// Game Center leaderboards (classic, all-time). Raw values are the IDs.
public enum Leaderboard: String, CaseIterable, Sendable {
    case totalDamage = "at.fhooe.sail.dungeonsanddeadlines.leaderboard.total_damage"
    case bossesDefeated = "at.fhooe.sail.dungeonsanddeadlines.leaderboard.bosses_defeated"
    case focusMinutes = "at.fhooe.sail.dungeonsanddeadlines.leaderboard.focus_minutes"
}

/// Everything Game Center needs, computed from the local attack log.
/// Pure, so it's unit tested and every device reports the same numbers.
public struct PlayerProgress: Sendable, Equatable {
    public var totalDamage = 0
    public var focusMinutes = 0
    public var bossesDefeated = 0
    public var longestStreak = 0
    public var flawlessWins = 0
    public var fullPartyWins = 0
    public var titles: Set<Title> = []
    public var tasksCompleted = 0
    public var largeTasksCompleted = 0
    public var cleanSweeps = 0
    public var focusSessions = 0
    public var longestSessionMinutes = 0
    public var nightSessions = 0
    public var earlyMorningSessions = 0
    public var halfTimeWins = 0
    public var quarterTimeWins = 0
    public var lastHourWins = 0
    public var teamWins = 0
    public var carryWins = 0
    public var delegatedTasksDone = 0
    /// Boss looks defeated at least once, and how many looks exist (the Bestiary goal).
    public var looksDefeated: Set<String> = []
    public var lookCount = 12

    /// A raid has to be at least this long for the "ahead of schedule" wins to count.
    static let minimumPacedRaid: TimeInterval = 24 * 3600

    public init() {}

    /// - Parameter reports: one report per raid the player is in.
    /// - Parameters:
    ///   - lookOf: Maps a boss name to its look (GameCore can't see the art); used for the Bestiary.
    ///   - lookCount: How many looks there are.
    public static func compute(
        memberID: String, reports: [RaidReport], config: DamageConfig = .standard, calendar: Calendar = .current,
        lookOf: (String) -> String = { $0 }, lookCount: Int = 12
    ) -> PlayerProgress {
        var p = PlayerProgress()
        p.lookCount = lookCount
        var allAttacks: [Attack] = []
        for report in reports {
            guard let row = report.rows.first(where: { $0.member.id == memberID }) else { continue }
            p.totalDamage += row.stats.total
            p.focusMinutes += row.stats.focusSeconds / 60
            let mine = report.attacks.filter { $0.memberID == memberID }
            allAttacks += mine
            p.tasksCompleted += mine.filter { $0.kind.isTask }.count
            p.largeTasksCompleted += report.tasks.filter { $0.size == .l && $0.completedBy == memberID }.count
            for attack in mine where attack.kind.focusSeconds > 0 {
                p.focusSessions += 1
                p.longestSessionMinutes = max(p.longestSessionMinutes, attack.kind.focusSeconds / 60)
                // The attack is logged when the session ends; the hour that counts is when it began.
                let began = attack.createdAt.addingTimeInterval(-Double(attack.kind.focusSeconds))
                switch calendar.component(.hour, from: began) {
                case 0..<4: p.nightSessions += 1
                case 4..<6: p.earlyMorningSessions += 1
                default: break
                }
            }
            guard report.state.outcome == .won else { continue }
            p.bossesDefeated += 1
            p.looksDefeated.insert(lookOf(report.raid.bossName))
            p.addWinStats(of: report, memberID: memberID, row: row, config: config)
            if report.openTasks.isEmpty { p.flawlessWins += 1 }
            if report.rows.count >= config.maxMembers { p.fullPartyWins += 1 }
            // Titles only count when there was someone to beat.
            if report.rows.count >= 2 { p.titles.formUnion(row.titles.filter { $0 != .afkLegend }) }
        }
        p.longestStreak = Streaks.longest(memberID: memberID, attacks: allAttacks, minimumMinutes: config.streakMinimumMinutes, calendar: calendar)
        return p
    }

    /// Pacing, team and task-assignment stats of one won raid.
    private mutating func addWinStats(of report: RaidReport, memberID: String, row: RaidReport.Row, config: DamageConfig) {
        let raid = report.raid
        // The moment the boss's HP hit zero.
        let wonAt = report.timeline.first { $0.hp <= 0 }?.date
        if let wonAt, let start = raid.startedAt {
            let total = raid.deadline.timeIntervalSince(start)
            let elapsed = wonAt.timeIntervalSince(start)
            if total >= Self.minimumPacedRaid {
                if elapsed <= total / 2 { halfTimeWins += 1 }
                if elapsed <= total / 4 { quarterTimeWins += 1 }
            }
            let left = raid.deadline.timeIntervalSince(wonAt)
            if left >= 0 && left <= 3600 { lastHourWins += 1 }
            // Every task done, and the boss was still calm or angry when the last blow landed.
            if report.openTasks.isEmpty, !report.tasks.isEmpty,
               Phase.at(start: start, deadline: raid.deadline, now: wonAt, shift: raid.phaseShift) <= .angry {
                cleanSweeps += 1
            }
        }
        if report.rows.count >= 2, row.stats.total > 0 { teamWins += 1 }
        if report.rows.count >= 4, row.stats.total * 2 > report.state.totalDamage { carryWins += 1 }
        // Only the leader hands out tasks, so that's the only raid we can credit.
        if raid.ownerID == memberID {
            delegatedTasksDone += report.tasks.filter {
                guard let assignee = $0.assigneeID else { return false }
                return assignee != memberID && $0.completedBy == assignee
            }.count
        }
    }

    /// Percent complete (0–100) per achievement.
    public var achievements: [Achievement: Double] {
        func ratio(_ value: Int, _ goal: Int) -> Double { min(100, Double(value) / Double(goal) * 100) }
        return [
            .firstBlood: totalDamage > 0 ? 100 : 0,
            .firstVictory: ratio(bossesDefeated, 1),
            .slayer5: ratio(bossesDefeated, 5),
            .slayer25: ratio(bossesDefeated, 25),
            .focus10h: ratio(focusMinutes, 600),
            .streak7: ratio(longestStreak, 7),
            .flawless: ratio(flawlessWins, 1),
            .fullParty: ratio(fullPartyWins, 1),
            .mvp: titles.contains(.mvp) ? 100 : 0,
            .sniper: titles.contains(.sniper) ? 100 : 0,
            .grinder: titles.contains(.grinder) ? 100 : 0,
            .consistent: titles.contains(.consistent) ? 100 : 0,
            .lastMinuteHero: titles.contains(.lastMinuteHero) ? 100 : 0,
            .tasks10: ratio(tasksCompleted, 10),
            .tasks100: ratio(tasksCompleted, 100),
            .bigOne: ratio(largeTasksCompleted, 1),
            .cleanSweep: ratio(cleanSweeps, 1),
            .focusFirst: ratio(focusSessions, 1),
            .focusMarathon: ratio(longestSessionMinutes, 120),
            .nightOwl: ratio(nightSessions, 1),
            .earlyBird: ratio(earlyMorningSessions, 1),
            .streak30: ratio(longestStreak, 30),
            .aheadOfSchedule: ratio(halfTimeWins, 1),
            .speedrun: ratio(quarterTimeWins, 1),
            .buzzerBeater: ratio(lastHourWins, 1),
            .bestiary: ratio(looksDefeated.count, lookCount),
            .teamPlayer: ratio(teamWins, 1),
            .carry: ratio(carryWins, 1),
            .delegator: ratio(delegatedTasksDone, 1),
        ]
    }

    public var scores: [Leaderboard: Int] {
        [.totalDamage: totalDamage, .bossesDefeated: bossesDefeated, .focusMinutes: focusMinutes]
    }
}
