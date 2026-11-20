import Foundation
import Testing
@testable import GameCore

@Suite("Phase shift")
struct PhaseShiftTests {
    let start = Date(timeIntervalSince1970: 0)
    var deadline: Date { start.addingTimeInterval(1000) }
    func t(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
    func at(_ seconds: Double, _ shift: Int) -> Phase { Phase.at(start: start, deadline: deadline, now: t(seconds), shift: shift) }
    func next(_ seconds: Double, _ shift: Int) -> Date? { Phase.nextChange(start: start, deadline: deadline, after: t(seconds), shift: shift) }

    @Test("Shift is clamped to -3...3 on the raid")
    func clamping() {
        var raid = Raid(name: "R", bossName: "B", ownerID: "a", createdAt: start, deadline: deadline, phaseShift: 9)
        #expect(raid.phaseShift == 3)
        raid.phaseShift = -7
        #expect(raid.phaseShift == -3)
        raid.phaseShift = 1
        #expect(raid.phaseShift == 1)
        #expect(Phase.clampShift(4) == 3)
        #expect(Phase.clampShift(-4) == -3)
    }

    @Test("Default shift keeps the time rule")
    func unshifted() {
        for s in stride(from: 0.0, through: 1000, by: 50) {
            #expect(at(s, 0) == Phase.at(start: start, deadline: deadline, now: t(s)))
        }
        #expect(next(0, 0) == t(500))
        #expect(next(600, 0) == t(750))
        #expect(next(800, 0) == t(900))
        #expect(next(950, 0) == nil)
    }

    @Test("Promote at Calm: Angry now, then each later step one earlier, capped at Berserk")
    func promote() {
        #expect(at(0, 1) == .angry)
        #expect(at(500, 1) == .enraged)
        #expect(at(750, 1) == .berserk)
        #expect(at(900, 1) == .berserk)
        #expect(next(0, 1) == t(500))
        #expect(next(500, 1) == t(750))
        // Berserk from 750: the time rule's change at 900 is a no-op and is skipped.
        #expect(next(750, 1) == nil)

        #expect(at(0, 3) == .berserk)
        #expect(next(0, 3) == nil)
        #expect(at(0, 2) == .enraged)
        #expect(next(0, 2) == t(500)) // Berserk at the Angry boundary; 750 and 900 change nothing
        #expect(next(500, 2) == nil)
    }

    @Test("Demote at Berserk: one step calmer, floored at Calm")
    func demote() {
        #expect(at(950, -1) == .enraged)
        #expect(next(950, -1) == nil)
        #expect(at(0, -1) == .calm)
        // Calm until the time rule says Enraged; the Angry boundary is a no-op.
        #expect(next(0, -1) == t(750))
        #expect(at(750, -1) == .angry)
        #expect(next(750, -1) == t(900))
        #expect(at(900, -1) == .enraged)

        #expect(at(950, -3) == .calm)
        #expect(next(0, -3) == nil)
        #expect(at(950, -2) == .angry)
        #expect(next(0, -2) == t(900))
    }

    @Test("Raid helpers use the fight start and the shift")
    func raidHelpers() {
        var raid = Raid(name: "R", bossName: "B", ownerID: "a", createdAt: t(-500), deadline: deadline, startedAt: start, status: .active)
        #expect(raid.phase(at: t(100)) == .calm)
        #expect(raid.nextPhaseChange(after: t(100))?.date == t(500))
        #expect(raid.nextPhaseChange(after: t(100))?.phase == .angry)
        raid.phaseShift = 1
        #expect(raid.phase(at: t(100)) == .angry)
        #expect(raid.nextPhaseChange(after: t(100))?.phase == .enraged)
        raid.phaseShift = 3
        #expect(raid.nextPhaseChange(after: t(100)) == nil)

        // Planning raids count from creation.
        let planning = Raid(name: "R", bossName: "B", ownerID: "a", createdAt: start, deadline: deadline, phaseShift: 1)
        #expect(planning.phase(at: t(0)) == .angry)
    }

    @Test("BossEngine and the report use the shift")
    func engine() {
        var raid = Fixtures.raid() // day -10 ... day +10: Calm at "now"
        #expect(BossEngine.state(raid: raid, tasks: [], attacks: [], now: Fixtures.now).phase == .angry) // exactly 50 % left
        raid.phaseShift = 1
        #expect(BossEngine.state(raid: raid, tasks: [], attacks: [], now: Fixtures.now).phase == .enraged)
        raid.phaseShift = -1
        #expect(BossEngine.state(raid: raid, tasks: [], attacks: [], now: Fixtures.now).phase == .calm)
        #expect(Titles.report(raid: raid, members: [], tasks: [], attacks: [], now: Fixtures.now).highestPhase == .calm)
    }

    @Test("At every change date the phase is already the new one (realistic dates, odd durations)")
    func changeDatesLandOnNewPhase() {
        let start = Date(timeIntervalSinceReferenceDate: 784_000_000.123)
        let durations: [TimeInterval] = [
            1, 7.3, 59.999, 3_599.7, 86_399.3, 86_400 * 3 + 0.1, 604_799.9, 1_234_567.891, 31_536_000.17,
        ]
        for duration in durations {
            let deadline = start.addingTimeInterval(duration)
            for shift in Phase.shiftRange {
                let raid = Raid(name: "R", bossName: "B", ownerID: "a", createdAt: start.addingTimeInterval(-10),
                                deadline: deadline, startedAt: start, status: .active, phaseShift: shift)
                var cursor = start
                var changes = 0
                while let change = raid.nextPhaseChange(after: cursor), changes < 10 {
                    #expect(raid.phase(at: change.date) == change.phase, "duration \(duration), shift \(shift)")
                    #expect(raid.phase(at: change.date) > raid.phase(at: cursor))
                    cursor = change.date
                    changes += 1
                }
                #expect(changes < 4)
            }
        }
    }

    @Test("Raid JSON without phaseShift decodes as 0; out-of-range values are clamped")
    func decodingOldRaid() throws {
        let raid = Raid(name: "R", bossName: "B", ownerID: "a", createdAt: start, deadline: deadline,
                        startedAt: start, lockedMaxHP: 500, status: .active, inviteCode: "ABC", isMultiplayer: true, phaseShift: 2)
        let data = try JSONEncoder().encode(raid)
        #expect(try JSONDecoder().decode(Raid.self, from: data) == raid)

        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["phaseShift"] as? Int == 2)
        json["phaseShift"] = nil
        let old = try JSONDecoder().decode(Raid.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.phaseShift == 0)
        #expect(old.name == "R" && old.inviteCode == "ABC" && old.lockedMaxHP == 500 && old.status == .active)

        json["phaseShift"] = 9
        #expect(try JSONDecoder().decode(Raid.self, from: JSONSerialization.data(withJSONObject: json)).phaseShift == 3)
    }
}
