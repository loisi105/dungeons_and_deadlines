import Foundation
import Testing
@testable import GameCore

@Suite("Focus shield plan")
struct FocusShieldPlanTests {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()
    /// 2026-11-20 10:00 in Vienna.
    var tenAM: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))! }

    func running(since start: Date, accumulated: TimeInterval = 0) -> FocusSession {
        var s = FocusSession(raidID: UUID(), memberID: "a", accumulatedSeconds: accumulated)
        s.start(at: start)
        return s
    }

    func plan(enabled: Bool = true, hasSelection: Bool = true, session: FocusSession?, remaining: Int = 3 * 3600, now: Date) -> FocusShieldPlan {
        FocusShieldPlan.decide(
            enabled: enabled, hasSelection: hasSelection, session: session,
            remainingCapSeconds: remaining, now: now, calendar: calendar
        )
    }

    @Test("A running timer shields until the daily cap runs out")
    func runningShieldsUntilCap() {
        let now = tenAM.addingTimeInterval(600)
        let p = plan(session: running(since: tenAM), remaining: 3 * 3600, now: now)
        // 3 h left today, 10 min of it already in this session.
        #expect(p == .on(until: tenAM.addingTimeInterval(3 * 3600)))
    }

    @Test("Earlier stretches of the same session count against the cap")
    func accumulatedCounts() {
        let p = plan(session: running(since: tenAM, accumulated: 1800), remaining: 3600, now: tenAM)
        #expect(p == .on(until: tenAM.addingTimeInterval(1800)))
    }

    @Test("The shield never outlives the day")
    func endsAtMidnight() {
        let late = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 23))!
        let p = plan(session: running(since: late), remaining: 3 * 3600, now: late)
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        #expect(p == .on(until: midnight))
    }

    @Test("Off when blocking is off, nothing is picked, or the timer isn't running")
    func off() {
        let s = running(since: tenAM)
        #expect(plan(enabled: false, session: s, now: tenAM) == .off)
        #expect(plan(hasSelection: false, session: s, now: tenAM) == .off)
        #expect(plan(session: nil, now: tenAM) == .off)
        var paused = s
        paused.pause(at: tenAM.addingTimeInterval(60))
        #expect(plan(session: paused, now: tenAM.addingTimeInterval(120)) == .off)
    }

    @Test("Off once today's focus cap is used up")
    func capUsedUp() {
        #expect(plan(session: running(since: tenAM), remaining: 0, now: tenAM) == .off)
        // 30 min left, but this session has already run 30 min.
        #expect(plan(session: running(since: tenAM), remaining: 1800, now: tenAM.addingTimeInterval(1800)) == .off)
    }

    @Test("Safety-net window is at least 15 minutes and ends at the shield's end")
    func safetyNetWindow() {
        let long = FocusShieldPlan.safetyNetInterval(until: tenAM.addingTimeInterval(3600), now: tenAM, calendar: calendar)
        #expect(long == DateInterval(start: tenAM, end: tenAM.addingTimeInterval(3600)))

        // Only 5 minutes left: start earlier so the window is 15 minutes, still ending on time.
        let short = FocusShieldPlan.safetyNetInterval(until: tenAM.addingTimeInterval(300), now: tenAM, calendar: calendar)
        #expect(short == DateInterval(start: tenAM.addingTimeInterval(300 - 900), end: tenAM.addingTimeInterval(300)))
    }

    @Test("Shield ending at midnight: window ends 23:59:59 and is still 15 minutes long")
    func safetyNetAtMidnight() {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        let w = FocusShieldPlan.safetyNetInterval(until: midnight, now: midnight.addingTimeInterval(-300), calendar: calendar)
        #expect(w.end == midnight.addingTimeInterval(-1))
        #expect(w.duration >= 900)
        #expect(calendar.isDate(w.start, inSameDayAs: w.end))
    }

    @Test("Safety-net window just after midnight stays inside the day")
    func safetyNetAfterMidnight() {
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20))!
        let w = FocusShieldPlan.safetyNetInterval(until: midnight.addingTimeInterval(300), now: midnight.addingTimeInterval(60), calendar: calendar)
        #expect(w.start == midnight)
        #expect(w.duration >= 900)
    }
}
