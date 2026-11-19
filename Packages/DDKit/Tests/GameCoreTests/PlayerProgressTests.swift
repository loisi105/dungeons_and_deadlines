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
