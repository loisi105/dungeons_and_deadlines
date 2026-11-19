import Foundation

/// Game Center achievements. Raw values are the IDs to create in App Store Connect
/// (see docs/GAME_CENTER.md).
public enum Achievement: String, CaseIterable, Sendable {
    case firstBlood = "dd.achievement.first_blood"
    case firstVictory = "dd.achievement.first_victory"
    case slayer5 = "dd.achievement.slayer_5"
    case slayer25 = "dd.achievement.slayer_25"
    case focus10h = "dd.achievement.focus_10h"
    case streak7 = "dd.achievement.streak_7"
    case flawless = "dd.achievement.flawless"
    case fullParty = "dd.achievement.full_party"
    case mvp = "dd.achievement.title_mvp"
    case sniper = "dd.achievement.title_sniper"
    case grinder = "dd.achievement.title_grinder"
    case consistent = "dd.achievement.title_consistent"
    case lastMinuteHero = "dd.achievement.title_last_minute_hero"
}

/// Game Center leaderboards (classic, all-time). Raw values are the IDs.
public enum Leaderboard: String, CaseIterable, Sendable {
    case totalDamage = "dd.leaderboard.total_damage"
    case bossesDefeated = "dd.leaderboard.bosses_defeated"
    case focusMinutes = "dd.leaderboard.focus_minutes"
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

    public init() {}

    /// - Parameter reports: one report per raid the player is in.
    public static func compute(memberID: String, reports: [RaidReport], config: DamageConfig = .standard, calendar: Calendar = .current) -> PlayerProgress {
        var p = PlayerProgress()
        var allAttacks: [Attack] = []
        for report in reports {
            guard let row = report.rows.first(where: { $0.member.id == memberID }) else { continue }
            p.totalDamage += row.stats.total
            p.focusMinutes += row.stats.focusSeconds / 60
            allAttacks += report.attacks.filter { $0.memberID == memberID }
            guard report.state.outcome == .won else { continue }
            p.bossesDefeated += 1
            if report.openTasks.isEmpty { p.flawlessWins += 1 }
            if report.rows.count >= config.maxMembers { p.fullPartyWins += 1 }
            // Titles only count when there was someone to beat.
            if report.rows.count >= 2 { p.titles.formUnion(row.titles.filter { $0 != .afkLegend }) }
        }
        p.longestStreak = Streaks.longest(memberID: memberID, attacks: allAttacks, minimumMinutes: config.streakMinimumMinutes, calendar: calendar)
        return p
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
        ]
    }

    public var scores: [Leaderboard: Int] {
        [.totalDamage: totalDamage, .bossesDefeated: bossesDefeated, .focusMinutes: focusMinutes]
    }
}
