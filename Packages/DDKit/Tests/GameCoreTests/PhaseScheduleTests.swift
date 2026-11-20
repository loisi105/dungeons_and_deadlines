import Foundation
import Testing
@testable import GameCore

/// A stand-in phase rule (angry at 50 %, enraged at 75 %, berserk at 90 % of the time),
/// so these tests don't depend on the real thresholds or the phase shift.
private func rule(start: Date, deadline: Date) -> (Date) -> (date: Date, phase: Phase)? {
    let total = deadline.timeIntervalSince(start)
    let changes: [(Double, Phase)] = [(0.5, .angry), (0.75, .enraged), (0.9, .berserk)]
    return { now in
        changes
            .map { (date: start.addingTimeInterval(total * $0.0), phase: $0.1) }
            .first { $0.date > now }
    }
}

private func raid(_ id: UUID = UUID(), status: RaidStatus = .active, start: Date = Fixtures.day(-10), deadline: Date = Fixtures.day(10)) -> Raid {
    Raid(id: id, name: "Thesis", bossName: "Exam Dragon", ownerID: "a", createdAt: start, deadline: deadline, startedAt: start, status: status)
}

private func next(_ raid: Raid, _ now: Date) -> (date: Date, phase: Phase)? {
    rule(start: raid.startedAt ?? raid.createdAt, deadline: raid.deadline)(now)
}

@Suite("Phase alert schedule")
struct PhaseScheduleTests {
    @Test("Walks every upcoming change in order")
    func walksAll() {
        let r = raid(start: Fixtures.day(-1), deadline: Fixtures.day(9)) // now is 10 % in
        let changes = PhaseSchedule.upcoming(after: Fixtures.now, until: r.deadline, limit: 4) { next(r, $0) }
        #expect(changes.map(\.phase) == [.angry, .enraged, .berserk])
        let total = r.deadline.timeIntervalSince(Fixtures.day(-1))
        #expect(changes.map(\.date) == [0.5, 0.75, 0.9].map { Fixtures.day(-1).addingTimeInterval(total * $0) })
    }

    @Test("Only changes after now; nothing once in the last phase")
    func onlyFuture() {
        let r = raid() // now is 50 % in: exactly at the angry change
        let changes = PhaseSchedule.upcoming(after: Fixtures.now, limit: 4) { next(r, $0) }
        #expect(changes.map(\.phase) == [.enraged, .berserk])

        let late = raid(start: Fixtures.day(-19), deadline: Fixtures.day(1)) // 95 % in
        #expect(PhaseSchedule.upcoming(after: Fixtures.now, limit: 4) { next(late, $0) }.isEmpty)
    }

    @Test("Respects the per-raid limit")
    func limit() {
        let r = raid(start: Fixtures.day(-1), deadline: Fixtures.day(9))
        #expect(PhaseSchedule.upcoming(after: Fixtures.now, limit: 2) { next(r, $0) }.map(\.phase) == [.angry, .enraged])
        #expect(PhaseSchedule.upcoming(after: Fixtures.now, limit: 0) { next(r, $0) }.isEmpty)
    }

    @Test("Stops at the deadline, skips repeats, and survives a rule that doesn't advance")
    func guards() {
        let stuck = PhaseSchedule.upcoming(after: Fixtures.now, limit: 4) { _ in (Fixtures.now, .angry) }
        #expect(stuck.isEmpty)

        var calls = 0
        let repeating = PhaseSchedule.upcoming(after: Fixtures.now, limit: 4) { now in
            calls += 1
            return (now.addingTimeInterval(60), calls < 3 ? .angry : .enraged)
        }
        #expect(repeating.map(\.phase) == [.angry, .enraged])

        let pastDeadline = PhaseSchedule.upcoming(after: Fixtures.now, until: Fixtures.now.addingTimeInterval(30), limit: 4) {
            ($0.addingTimeInterval(60), .berserk)
        }
        #expect(pastDeadline.isEmpty)
    }

    @Test("Plan covers only ongoing fights")
    func onlyOngoing() {
        let active = raid(start: Fixtures.day(-1), deadline: Fixtures.day(9))
        let planning = raid(status: .planning)
        let won = raid(status: .won)
        let overdue = raid(start: Fixtures.day(-10), deadline: Fixtures.day(-1))
        let plan = PhaseSchedule.plan(raids: [planning, won, overdue, active], now: Fixtures.now, next: next)
        #expect(Set(plan.map(\.raidID)) == [active.id])
        #expect(plan.count == 3)
    }

    @Test("Plan keeps the soonest changes under the total cap")
    func totalCap() {
        // Raid i: start 1 day ago, deadline 9 + i days ahead, so later raids change later.
        let raids = (0..<30).map { raid(start: Fixtures.day(-1), deadline: Fixtures.day(9 + $0)) }
        let plan = PhaseSchedule.plan(raids: raids, now: Fixtures.now, perRaid: 4, total: 60, next: next)
        #expect(plan.count == 60)
        #expect(plan.map(\.date) == plan.map(\.date).sorted())
        let all = PhaseSchedule.plan(raids: raids, now: Fixtures.now, perRaid: 4, total: .max, next: next)
        #expect(all.count == 90)
        #expect(plan == Array(all.prefix(60)))
        #expect(PhaseSchedule.plan(raids: raids, now: Fixtures.now, perRaid: 1, total: 60, next: next).count == 30)
    }
}
