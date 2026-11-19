import Foundation
import Testing
@testable import GameCore

@Suite("DamageCalculator")
struct DamageCalculatorTests {
    let calc = Fixtures.calculator

    @Test("Task damage by size without streak", arguments: [(TaskSize.s, 50), (.m, 150), (.l, 400)])
    func taskDamageBySize(size: TaskSize, expected: Int) {
        #expect(calc.taskDamage(size: size, context: Fixtures.context()) == expected)
    }

    @Test("Streak multipliers 1.0, 1.1, 1.2 and capped")
    func streakMultipliers() {
        func attacks(days: Int) -> [Attack] {
            (0..<days).map { Fixtures.focus("a", minutes: 30, on: Fixtures.day(-$0)) }
        }
        #expect(calc.taskDamage(size: .m, context: Fixtures.context(attacks: attacks(days: 1))) == 150)
        #expect(calc.taskDamage(size: .m, context: Fixtures.context(attacks: attacks(days: 2))) == 165)
        #expect(calc.taskDamage(size: .m, context: Fixtures.context(attacks: attacks(days: 4))) == 180)
        #expect(calc.taskDamage(size: .m, context: Fixtures.context(attacks: attacks(days: 9))) == 180)
    }

    @Test("Streak survives until today qualifies")
    func streakAliveFromYesterday() {
        let log = [1, 2, 3].map { Fixtures.focus("a", minutes: 45, on: Fixtures.day(-$0)) }
        let days = Streaks.current(memberID: "a", attacks: log, now: Fixtures.now, minimumMinutes: 30, calendar: Fixtures.calendar)
        #expect(days == 3)
    }

    @Test("A gap breaks the streak; short days don't count")
    func streakGap() {
        let log = [
            Fixtures.focus("a", minutes: 40, on: Fixtures.day(0)),
            Fixtures.focus("a", minutes: 10, on: Fixtures.day(-1)),
            Fixtures.focus("a", minutes: 40, on: Fixtures.day(-2)),
        ]
        #expect(Streaks.current(memberID: "a", attacks: log, now: Fixtures.now, minimumMinutes: 30, calendar: Fixtures.calendar) == 1)
    }

    @Test("Focus damage is 2 per minute")
    func focusRate() {
        let r = calc.focusDamage(seconds: 30 * 60, context: Fixtures.context())
        #expect(r == .init(damage: 60, creditedSeconds: 1800))
    }

    @Test("Daily focus cap clips at 180 minutes and resets the next day")
    func focusCap() {
        let r = calc.focusDamage(seconds: 200 * 60, context: Fixtures.context())
        #expect(r.creditedSeconds == 180 * 60)
        #expect(r.damage == 360)

        let earlier = [Fixtures.focus("a", minutes: 170, on: Fixtures.day(0, hour: 9))]
        let r2 = calc.focusDamage(seconds: 30 * 60, context: Fixtures.context(attacks: earlier))
        #expect(r2.creditedSeconds == 10 * 60)

        let yesterday = [Fixtures.focus("a", minutes: 180, on: Fixtures.day(-1))]
        let r3 = calc.focusDamage(seconds: 60 * 60, context: Fixtures.context(attacks: yesterday))
        #expect(r3.creditedSeconds == 3600)
    }

    @Test("Another member's focus doesn't use my cap")
    func capIsPerMember() {
        let other = [Fixtures.focus("b", minutes: 180, on: Fixtures.day(0, hour: 9))]
        #expect(calc.focusDamage(seconds: 600, context: Fixtures.context(attacks: other)).creditedSeconds == 600)
    }

    @Test("Per-member daily cap only applies with 2+ members")
    func perMemberCap() {
        let today = [Fixtures.taskHit("a", damage: 200, on: Fixtures.day(0, hour: 8))]
        // cap = 25% of 1000 = 250, 50 left
        #expect(calc.taskDamage(size: .l, context: Fixtures.context(attacks: today, members: 2)) == 50)
        #expect(calc.taskDamage(size: .l, context: Fixtures.context(attacks: today, members: 1)) == 400)
        #expect(calc.taskDamage(size: .l, context: Fixtures.context(attacks: today, members: 2, maxHP: nil)) == 400)
    }

    @Test("Zero-damage attacks are not created")
    func noZeroAttacks() {
        let capped = [Fixtures.focus("a", minutes: 180, on: Fixtures.day(0, hour: 8))]
        #expect(calc.focusAttack(raidID: Fixtures.raidID, seconds: 600, context: Fixtures.context(attacks: capped)) == nil)
        let attack = calc.taskAttack(raidID: Fixtures.raidID, taskID: UUID(), size: .s, context: Fixtures.context())
        #expect(attack?.damage == 50)
        #expect(attack?.localDay == "2026-11-19")
    }

    @Test("Max single attack matches the rules limit")
    func maxSingle() {
        #expect(DamageConfig.standard.maxSingleAttackDamage == 480)
    }
}
