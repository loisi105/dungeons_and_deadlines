import Foundation

public enum Streaks {
    /// Focus seconds per `localDay` for one member.
    public static func focusSecondsByDay(memberID: String, attacks: [Attack]) -> [String: Int] {
        var result: [String: Int] = [:]
        for attack in attacks where attack.memberID == memberID {
            result[attack.localDay, default: 0] += attack.kind.focusSeconds
        }
        return result
    }

    /// Consecutive qualifying days ending today. Today counts once it qualifies;
    /// until then the streak is still alive from yesterday.
    public static func current(
        memberID: String, attacks: [Attack], now: Date,
        minimumMinutes: Int, calendar: Calendar = .current
    ) -> Int {
        let byDay = focusSecondsByDay(memberID: memberID, attacks: attacks)
        let minimum = minimumMinutes * 60
        func qualifies(_ offset: Int) -> Bool {
            (byDay[LocalDay.key(daysBefore: offset, from: now, calendar: calendar)] ?? 0) >= minimum
        }
        var offset = qualifies(0) ? 0 : 1
        var count = 0
        while qualifies(offset) {
            count += 1
            offset += 1
        }
        return count
    }

    /// Longest run of consecutive qualifying days anywhere in the log.
    public static func longest(
        memberID: String, attacks: [Attack], minimumMinutes: Int, calendar: Calendar = .current
    ) -> Int {
        let minimum = minimumMinutes * 60
        let days = focusSecondsByDay(memberID: memberID, attacks: attacks)
            .filter { $0.value >= minimum }
            .keys
            .compactMap { date(fromKey: $0, calendar: calendar) }
            .sorted()
        var best = 0
        var run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.dateComponents([.day], from: previous, to: day).day == 1 {
                run += 1
            } else {
                run = 1
            }
            best = max(best, run)
            previous = day
        }
        return best
    }

    static func date(fromKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
