import Foundation

/// Which phase changes to announce ahead of time (the app turns these into local
/// notifications). Pure: the "next change" rule is passed in, so this works with any
/// phase rule, including a user's phase shift.
public enum PhaseSchedule {
    /// One upcoming phase change of one raid.
    public struct Change: Equatable, Hashable, Sendable {
        public let raidID: UUID
        public let date: Date
        public let phase: Phase

        public init(raidID: UUID, date: Date, phase: Phase) {
            self.raidID = raidID
            self.date = date
            self.phase = phase
        }
    }

    /// A fight that can still change phase: running, deadline still ahead.
    public static func isOngoing(_ raid: Raid, now: Date) -> Bool {
        raid.status == .active && raid.deadline > now
    }

    /// Walks `next` from `now` and returns at most `limit` changes, in order.
    /// Stops at the first change at or after `until` (the deadline), and guards against
    /// a rule that doesn't move forward. A change to the phase it's already in is skipped.
    public static func upcoming(
        after now: Date, until: Date? = nil, limit: Int,
        next: (Date) -> (date: Date, phase: Phase)?
    ) -> [(date: Date, phase: Phase)] {
        guard limit > 0 else { return [] }
        var result: [(date: Date, phase: Phase)] = []
        var cursor = now
        var last: Phase?
        // Bounded, so a misbehaving rule can't loop forever.
        for _ in 0..<(limit + Phase.allCases.count + 4) {
            guard result.count < limit, let change = next(cursor), change.date > cursor else { break }
            if let until, change.date >= until { break }
            cursor = change.date
            if change.phase == last { continue }
            last = change.phase
            result.append(change)
        }
        return result
    }

    /// The changes to schedule for all `raids`: only ongoing fights, at most `perRaid` each
    /// and `total` overall (iOS keeps at most 64 pending notifications per app), keeping the
    /// soonest ones when there are too many.
    public static func plan(
        raids: [Raid], now: Date, perRaid: Int = 4, total: Int = 60,
        next: (Raid, Date) -> (date: Date, phase: Phase)?
    ) -> [Change] {
        let all = raids
            .filter { isOngoing($0, now: now) }
            .flatMap { raid in
                upcoming(after: now, until: raid.deadline, limit: perRaid) { next(raid, $0) }
                    .map { Change(raidID: raid.id, date: $0.date, phase: $0.phase) }
            }
            .sorted { ($0.date, $0.raidID.uuidString, $0.phase.rawValue) < ($1.date, $1.raidID.uuidString, $1.phase.rawValue) }
        return Array(all.prefix(max(0, total)))
    }
}
