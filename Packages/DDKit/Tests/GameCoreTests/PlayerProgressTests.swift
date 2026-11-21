import Foundation
import Testing
@testable import GameCore

@Suite("Game Center progress")
struct PlayerProgressTests {
    func report(members: [String], attacks: [Attack], won: Bool, openTasks: Int = 0) -> RaidReport {
        let raid = Fixtures.raid(maxHP: won ? 100 : 100_000)
        let tasks = (0..<openTasks).map { _ in Fixtures.task(.s) }
        return Titles.report(
            raid: raid, members: members.map { Fixtures.member($0) }, tasks: tasks, attacks: attacks,
            now: Fixtures.now, calendar: Fixtures.calendar
        )
    }

    @Test("Totals, victories and flawless wins")
    func totals() {
        let r = report(members: ["a"], attacks: [
            Fixtures.taskHit("a", damage: 150, on: Fixtures.now),
            Fixtures.focus("a", minutes: 90, on: Fixtures.now),
        ], won: true)
        let p = PlayerProgress.compute(memberID: "a", reports: [r], calendar: Fixtures.calendar)
        #expect(p.totalDamage == 330)
        #expect(p.focusMinutes == 90)
        #expect(p.bossesDefeated == 1)
        #expect(p.flawlessWins == 1)
        #expect(p.achievements[.firstVictory] == 100)
        #expect(p.achievements[.slayer5] == 20)
        #expect(p.achievements[.focus10h] == 15)
        #expect(p.scores[.totalDamage] == 330)
    }

    @Test("Solo raids don't award title achievements; AFK Legend never does")
    func titles() {
        let solo = report(members: ["a"], attacks: [Fixtures.taskHit("a", damage: 150, on: Fixtures.now)], won: true)
        #expect(PlayerProgress.compute(memberID: "a", reports: [solo]).titles.isEmpty)

        let duo = report(members: ["a", "b"], attacks: [
            Fixtures.taskHit("a", damage: 90, on: Fixtures.now),
            Fixtures.taskHit("b", damage: 10, on: Fixtures.now),
        ], won: true)
        #expect(PlayerProgress.compute(memberID: "a", reports: [duo]).titles.contains(.mvp))
        #expect(PlayerProgress.compute(memberID: "b", reports: [duo]).titles.isEmpty)
    }

    @Test("Lost raids count damage but not victories")
    func lost() {
        let r = report(members: ["a"], attacks: [Fixtures.taskHit("a", damage: 50, on: Fixtures.now)], won: false)
        let p = PlayerProgress.compute(memberID: "a", reports: [r])
        #expect(p.totalDamage == 50)
        #expect(p.bossesDefeated == 0)
        #expect(p.achievements[.firstBlood] == 100)
        #expect(p.achievements[.firstVictory] == 0)
    }

    @Test("Every achievement and leaderboard has a unique ID")
    func ids() {
        #expect(Set(Achievement.allCases.map(\.rawValue)).count == Achievement.allCases.count)
        #expect(Set(Leaderboard.allCases.map(\.rawValue)).count == Leaderboard.allCases.count)
    }
}

@Suite("More achievements")
struct MoreAchievementTests {
    /// A raid of 10 days (start day -10, deadline day +10 => 20 days) won by the given attacks.
    func report(
        members: [String] = ["a"], attacks: [Attack], tasks: [RaidTask] = [], maxHP: Int = 100,
        start: Date = Fixtures.day(-10), deadline: Date = Fixtures.day(10)
    ) -> RaidReport {
        Titles.report(
            raid: Fixtures.raid(maxHP: maxHP, start: start, deadline: deadline), members: members.map { Fixtures.member($0) },
            tasks: tasks, attacks: attacks, now: Fixtures.now, calendar: Fixtures.calendar
        )
    }

    func progress(_ r: RaidReport, as id: String = "a") -> PlayerProgress {
        PlayerProgress.compute(memberID: id, reports: [r], calendar: Fixtures.calendar)
    }

    @Test("Task counts and the large-task achievement")
    func tasks() {
        var big = Fixtures.task(.l, done: true)
        big.completedBy = "a"
        let hits = (0..<10).map { _ in Fixtures.taskHit("a", damage: 1, on: Fixtures.now) }
        let p = progress(report(attacks: hits, tasks: [big], maxHP: 1000))
        #expect(p.achievements[.tasks10] == 100)
        #expect(p.achievements[.tasks100] == 10)
        #expect(p.achievements[.bigOne] == 100)
    }

    @Test("Focus sessions: first, marathon, night owl and early bird use the start time")
    func focus() {
        let night = Fixtures.focus("a", minutes: 130, on: Fixtures.day(-3, hour: 3)) // began 00:50
        let early = Fixtures.focus("a", minutes: 30, on: Fixtures.day(-2, hour: 5)) // began 04:30
        let p = progress(report(attacks: [night, early], maxHP: 100_000))
        #expect(p.achievements[.focusFirst] == 100)
        #expect(p.achievements[.focusMarathon] == 100)
        #expect(p.achievements[.nightOwl] == 100)
        #expect(p.achievements[.earlyBird] == 100)
        let day = progress(report(attacks: [Fixtures.focus("a", minutes: 60, on: Fixtures.day(-1, hour: 15))], maxHP: 100_000))
        #expect(day.achievements[.nightOwl] == 0)
        #expect(day.achievements[.focusMarathon] == 50)
    }

    @Test("Pacing: halfway, first quarter and last hour")
    func pacing() {
        // 20-day raid: start day -10, deadline day +10.
        let half = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(-1))]))
        #expect(half.achievements[.aheadOfSchedule] == 100)
        #expect(half.achievements[.speedrun] == 0)
        let quick = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(-6))]))
        #expect(quick.achievements[.speedrun] == 100)
        let late = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(5))]))
        #expect(late.achievements[.aheadOfSchedule] == 0)
        let buzzer = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(10).addingTimeInterval(-1800))]))
        #expect(buzzer.achievements[.buzzerBeater] == 100)
        #expect(half.achievements[.buzzerBeater] == 0)
    }

    @Test("Short raids can't earn the pacing wins")
    func shortRaid() {
        let start = Fixtures.now.addingTimeInterval(-3600 * 5)
        let r = report(attacks: [Fixtures.taskHit("a", damage: 100, on: start.addingTimeInterval(600))], start: start, deadline: start.addingTimeInterval(3600 * 20))
        #expect(progress(r).achievements[.aheadOfSchedule] == 0)
    }

    @Test("Clean sweep needs every task done while the boss was calm or angry")
    func cleanSweep() {
        var done = Fixtures.task(.s, done: true)
        done.completedBy = "a"
        let early = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(-8))], tasks: [done]))
        #expect(early.achievements[.cleanSweep] == 100)
        let late = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(9))], tasks: [done]))
        #expect(late.achievements[.cleanSweep] == 0)
        let open = progress(report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(-8))], tasks: [done, Fixtures.task(.s)]))
        #expect(open.achievements[.cleanSweep] == 0)
    }

    @Test("Team wins and carrying a full party")
    func team() {
        let duo = report(members: ["a", "b"], attacks: [
            Fixtures.taskHit("a", damage: 60, on: Fixtures.day(-1)), Fixtures.taskHit("b", damage: 40, on: Fixtures.day(-1)),
        ])
        #expect(progress(duo).achievements[.teamPlayer] == 100)
        #expect(progress(duo).achievements[.carry] == 0)
        let four = report(members: ["a", "b", "c", "d"], attacks: [
            Fixtures.taskHit("a", damage: 60, on: Fixtures.day(-1)), Fixtures.taskHit("b", damage: 40, on: Fixtures.day(-1)),
        ])
        #expect(progress(four).achievements[.carry] == 100)
        #expect(progress(four, as: "b").achievements[.carry] == 0)
        let idle = progress(four, as: "c")
        #expect(idle.achievements[.teamPlayer] == 0)
    }

    @Test("Delegator: the leader's task, done by someone else")
    func delegator() {
        var t = Fixtures.task(.s, done: true)
        t.assigneeID = "b"
        t.completedBy = "b"
        let r = report(members: ["a", "b"], attacks: [Fixtures.taskHit("b", damage: 100, on: Fixtures.day(-1))], tasks: [t])
        #expect(progress(r).achievements[.delegator] == 100)
        #expect(progress(r, as: "b").achievements[.delegator] == 0)
    }

    @Test("Bestiary counts distinct looks of won raids")
    func bestiary() {
        let r = report(attacks: [Fixtures.taskHit("a", damage: 100, on: Fixtures.day(-1))])
        let p = PlayerProgress.compute(memberID: "a", reports: [r, r], calendar: Fixtures.calendar, lookOf: { _ in "dragon" }, lookCount: 12)
        #expect(p.looksDefeated == ["dragon"])
        #expect(abs((p.achievements[.bestiary] ?? 0) - 100.0 / 12) < 0.001)
    }

    @Test("Streak 30 follows the streak")
    func streak30() {
        var p = PlayerProgress()
        p.longestStreak = 15
        #expect(p.achievements[.streak30] == 50)
        #expect(p.achievements.count == Achievement.allCases.count)
    }
}
