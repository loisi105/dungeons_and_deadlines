import Foundation
@testable import GameCore

enum Fixtures {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()

    /// 2026-11-19 12:00 Vienna.
    static let now: Date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))!

    static func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(byAdding: .day, value: offset, to: now)!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base)!
    }

    static let raidID = UUID()

    static func focus(_ member: String, minutes: Int, on date: Date, damage: Int? = nil) -> Attack {
        Attack(
            raidID: raidID, memberID: member, kind: .focus(seconds: minutes * 60),
            damage: damage ?? minutes * 2, createdAt: date, localDay: LocalDay.key(for: date, calendar: calendar)
        )
    }

    static func taskHit(_ member: String, damage: Int, on date: Date) -> Attack {
        Attack(
            raidID: raidID, memberID: member, kind: .task(UUID()), damage: damage,
            createdAt: date, localDay: LocalDay.key(for: date, calendar: calendar)
        )
    }

    static func raid(
        status: RaidStatus = .active, maxHP: Int? = 1000, start: Date = day(-10),
        deadline: Date = day(10), multiplayer: Bool = false
    ) -> Raid {
        Raid(
            id: raidID, name: "Thesis", bossName: "Exam Dragon", ownerID: "a",
            createdAt: start, deadline: deadline, startedAt: status == .planning ? nil : start,
            lockedMaxHP: status == .planning ? nil : maxHP, status: status, isMultiplayer: multiplayer
        )
    }

    static func task(_ size: TaskSize, createdAt: Date = day(-11), done: Bool = false) -> RaidTask {
        RaidTask(raidID: raidID, title: "Task \(size)", size: size, createdAt: createdAt, completedAt: done ? now : nil)
    }

    static func member(_ id: String, joined offset: Int = -11) -> Member {
        Member(id: id, raidID: raidID, nickname: id.uppercased(), joinedAt: day(offset))
    }

    static func context(_ member: String = "a", attacks: [Attack] = [], members: Int = 1, maxHP: Int? = 1000, now: Date = now) -> DamageCalculator.Context {
        .init(memberID: member, attacks: attacks, memberCount: members, lockedMaxHP: maxHP, now: now)
    }

    static let calculator = DamageCalculator(config: .standard, calendar: calendar)
}
