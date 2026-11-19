import Foundation
import Testing
@testable import GameCore

@Suite("FocusSession")
struct FocusSessionTests {
    let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("Elapsed counts running stretches across pauses")
    func elapsed() {
        var s = FocusSession(raidID: UUID(), memberID: "a")
        s.start(at: t0)
        #expect(s.elapsed(at: t0.addingTimeInterval(60)) == 60)
        s.pause(at: t0.addingTimeInterval(60))
        #expect(s.elapsed(at: t0.addingTimeInterval(500)) == 60)
        s.start(at: t0.addingTimeInterval(600))
        let total = s.stop(at: t0.addingTimeInterval(630))
        #expect(total == 90)
        #expect(s.state == .idle)
        #expect(s.elapsed(at: t0.addingTimeInterval(700)) == 0)
    }

    @Test("Backgrounded under the grace period keeps running")
    func shortBackground() {
        var s = FocusSession(raidID: UUID(), memberID: "a")
        s.start(at: t0)
        s.markBackgrounded(at: t0.addingTimeInterval(100))
        let paused = s.resumeFromBackground(at: t0.addingTimeInterval(190), grace: 120)
        #expect(!paused)
        #expect(s.state == .running)
        #expect(s.elapsed(at: t0.addingTimeInterval(200)) == 200)
    }

    @Test("Backgrounded over the grace period pauses at the moment it left")
    func longBackground() {
        var s = FocusSession(raidID: UUID(), memberID: "a")
        s.start(at: t0)
        s.markBackgrounded(at: t0.addingTimeInterval(100))
        let paused = s.resumeFromBackground(at: t0.addingTimeInterval(400), grace: 120)
        #expect(paused)
        #expect(s.state == .paused)
        #expect(s.elapsed(at: t0.addingTimeInterval(1000)) == 100)
    }

    @Test("Timer reference date reproduces elapsed time")
    func reference() {
        var s = FocusSession(raidID: UUID(), memberID: "a", accumulatedSeconds: 50)
        s.start(at: t0)
        let now = t0.addingTimeInterval(10)
        #expect(now.timeIntervalSince(s.timerReferenceDate(at: now)) == 60)
    }
}

@Suite("Titles and report")
struct TitlesTests {
    @Test("Every title goes to the right member")
    func awards() {
        let raid = Fixtures.raid(start: Fixtures.day(-10), deadline: Fixtures.day(1))
        let members = [Fixtures.member("a"), Fixtures.member("b"), Fixtures.member("c")]
        let attacks = [
            Fixtures.taskHit("a", damage: 400, on: Fixtures.day(-5)),
            Fixtures.focus("b", minutes: 60, on: Fixtures.day(-3)),
            Fixtures.focus("b", minutes: 60, on: Fixtures.day(-2)),
            Fixtures.focus("b", minutes: 60, on: Fixtures.day(-1)),
            Fixtures.taskHit("c", damage: 50, on: Fixtures.day(0)), // in the last 10%
        ]
        let t = Titles.award(raid: raid, members: members, attacks: attacks, calendar: Fixtures.calendar)
        #expect(t[.mvp] == "a")
        #expect(t[.sniper] == "a")
        #expect(t[.grinder] == "b")
        #expect(t[.consistent] == "b")
        #expect(t[.lastMinuteHero] == "c")
        #expect(t[.afkLegend] == "c")
    }

    @Test("Ties go to the member who joined first")
    func ties() {
        let raid = Fixtures.raid()
        let members = [Fixtures.member("z", joined: -12), Fixtures.member("y", joined: -11)]
        let attacks = [Fixtures.taskHit("y", damage: 100, on: Fixtures.now), Fixtures.taskHit("z", damage: 100, on: Fixtures.now)]
        let t = Titles.award(raid: raid, members: members, attacks: attacks)
        #expect(t[.mvp] == "z")
        #expect(t[.afkLegend] == nil) // equal totals: nobody is AFK
    }

    @Test("Solo raids get no AFK Legend; nobody gets titles for zero")
    func solo() {
        let t = Titles.award(raid: Fixtures.raid(), members: [Fixtures.member("a")], attacks: [])
        #expect(t.isEmpty)
    }

    @Test("Report lists late and open tasks")
    func report() {
        let raid = Fixtures.raid()
        let tasks = [Fixtures.task(.s, createdAt: Fixtures.day(-11), done: true), Fixtures.task(.m, createdAt: Fixtures.day(-2))]
        let r = Titles.report(raid: raid, members: [Fixtures.member("a")], tasks: tasks, attacks: [], now: Fixtures.now, calendar: Fixtures.calendar)
        #expect(r.lateTasks.count == 1)
        #expect(r.openTasks.count == 1)
        #expect(r.rows.count == 1)
    }
}
