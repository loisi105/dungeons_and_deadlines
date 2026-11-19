import Foundation
import Testing
@testable import GameCore

@Suite("BossEngine and phases")
struct BossEngineTests {
    @Test("Locked HP = task total / 0.65, rounded up")
    func lockHP() {
        #expect(BossEngine.lockHP(tasks: []) == 0)
        #expect(BossEngine.lockHP(tasks: [Fixtures.task(.s)]) == 77) // 50 / 0.65 = 76.9
        #expect(BossEngine.lockHP(tasks: [Fixtures.task(.s), Fixtures.task(.m), Fixtures.task(.l)]) == 924) // 600 / 0.65 = 923.08
    }

    @Test("Planning shows predicted HP and no damage")
    func planning() {
        let raid = Fixtures.raid(status: .planning)
        let s = BossEngine.state(raid: raid, tasks: [Fixtures.task(.l)], attacks: [], now: Fixtures.now)
        #expect(s.outcome == .planning)
        #expect(s.maxHP == 616)
        #expect(s.currentHP == s.maxHP)
    }

    @Test("HP never below 0; win at 0")
    func win() {
        let raid = Fixtures.raid(maxHP: 100)
        let s = BossEngine.state(raid: raid, tasks: [], attacks: [Fixtures.taskHit("a", damage: 400, on: Fixtures.now)], now: Fixtures.now)
        #expect(s.currentHP == 0)
        #expect(s.outcome == .won)
    }

    @Test("Lost after the deadline with HP left")
    func lost() {
        let raid = Fixtures.raid(maxHP: 1000, deadline: Fixtures.day(-1))
        let s = BossEngine.state(raid: raid, tasks: [], attacks: [Fixtures.taskHit("a", damage: 50, on: Fixtures.day(-2))], now: Fixtures.now)
        #expect(s.outcome == .lost)
        #expect(s.currentHP == 950)
    }

    @Test("Member stats split burst and sustained, sorted by total")
    func stats() {
        let attacks = [
            Fixtures.taskHit("a", damage: 150, on: Fixtures.now),
            Fixtures.focus("b", minutes: 60, on: Fixtures.now),
            Fixtures.focus("b", minutes: 60, on: Fixtures.now),
            Fixtures.taskHit("b", damage: 50, on: Fixtures.now),
        ]
        let s = BossEngine.state(raid: Fixtures.raid(), tasks: [], attacks: attacks, now: Fixtures.now)
        #expect(s.memberStats.map(\.memberID) == ["b", "a"])
        #expect(s.memberStats[0] == MemberStats(memberID: "b", burst: 50, sustained: 240, focusSeconds: 7200, tasksCompleted: 1))
        #expect(s.totalDamage == 440)
    }

    @Test("Attacks from other raids are ignored")
    func otherRaids() {
        var foreign = Fixtures.taskHit("a", damage: 500, on: Fixtures.now)
        foreign.raidID = UUID()
        let s = BossEngine.state(raid: Fixtures.raid(), tasks: [], attacks: [foreign], now: Fixtures.now)
        #expect(s.currentHP == 1000)
    }

    @Test("Phase boundaries at 50 / 25 / 10 % time left")
    func phases() {
        let start = Date(timeIntervalSince1970: 0)
        let deadline = start.addingTimeInterval(1000)
        func at(_ t: Double) -> Phase { Phase.at(start: start, deadline: deadline, now: start.addingTimeInterval(t)) }
        #expect(at(0) == .calm)
        #expect(at(499) == .calm)
        #expect(at(500) == .angry)
        #expect(at(749) == .angry)
        #expect(at(750) == .enraged)
        #expect(at(899) == .enraged)
        #expect(at(900) == .berserk)
        #expect(at(2000) == .berserk)
        #expect(Phase.nextChange(start: start, deadline: deadline, after: start.addingTimeInterval(600)) == start.addingTimeInterval(750))
        #expect(Phase.nextChange(start: start, deadline: deadline, after: start.addingTimeInterval(950)) == nil)
    }

    @Test("Late tasks are detected")
    func late() {
        let start = Fixtures.day(-10)
        #expect(Fixtures.task(.s, createdAt: Fixtures.day(-5)).isLate(startedAt: start))
        #expect(!Fixtures.task(.s, createdAt: Fixtures.day(-11)).isLate(startedAt: start))
        #expect(!Fixtures.task(.s).isLate(startedAt: nil))
    }

    @Test("HP timeline starts full and drops per attack")
    func timeline() {
        let raid = Fixtures.raid(maxHP: 300)
        let t = BossEngine.hpTimeline(raid: raid, attacks: [
            Fixtures.taskHit("a", damage: 100, on: Fixtures.day(-3)),
            Fixtures.taskHit("a", damage: 250, on: Fixtures.day(-1)),
        ])
        #expect(t.map(\.hp) == [300, 200, 0])
    }
}
