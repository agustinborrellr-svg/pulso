import XCTest
@testable import PulsoAnalytics

final class StressSummaryTests: XCTestCase {
    func testHighMinutesSplitByWhatWasGoingOn() {
        let origin = 0
        var m = [Double?](repeating: 0.5, count: 600)
        for i in 10..<20 { m[i] = 2.4 }      // just after waking
        for i in 200..<230 { m[i] = 2.6 }    // a workout 200-220 and its recovery
        for i in 400..<405 { m[i] = 2.2 }    // around a nap at 420-450
        for i in 500..<512 { m[i] = 2.1 }    // nothing going on
        m[550] = nil
        let s = StressSummary.split(minutes: m, origin: origin, workouts: [12_000...13_200], naps: [25_200...27_000])
        XCTAssertEqual(s.total, 57)
        XCTAssertEqual(s.activity, 30)
        XCTAssertEqual(s.waking, 15)
        XCTAssertEqual(s.asleep, 0)
        XCTAssertEqual(s.other, 12)
        XCTAssertEqual(s.counted, 27)
    }

    func testNightBeforeWakingCountsAsSleep() {
        var m = [Double?](repeating: 0.5, count: 900)
        for i in 100..<110 { m[i] = 2.3 }    // asleep (bed at 0, up at 480)
        for i in 700..<705 { m[i] = 2.3 }    // afternoon, nothing going on
        let s = StressSummary.split(minutes: m, origin: 0, wake: 480 * 60, workouts: [], naps: [])
        XCTAssertEqual(s.asleep, 10)
        XCTAssertEqual(s.other, 5)
        XCTAssertEqual(s.counted, 5)
    }

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func testDailyLeavesOutWorkoutsTheirRecoveryAndSleep() {
        // Bed at 00:00, up at 07:00 (minute 420); a workout 12:00-13:00 and a nap 16:00-16:30; 20 h of readings.
        var m = [Double?](repeating: 0.5, count: 1200)
        for i in 100..<130 { m[i] = 2.5 }      // asleep: not counted
        for i in 430..<440 { m[i] = 2.2 }      // just after waking: counted
        for i in 720..<780 { m[i] = 2.8 }      // in the workout: not counted
        for i in 780..<870 { m[i] = 2.3 }      // the 90 minutes after it: not counted
        for i in 870..<880 { m[i] = 2.1 }      // after those 90 minutes: counted
        for i in 960..<990 { m[i] = 2.4 }      // in the nap: not counted
        for i in 1000..<1005 { m[i] = nil }    // strap off: nothing
        let d = StressSummary.daily(minutes: m, origin: 0, wake: 420 * 60, workouts: [720 * 60...780 * 60],
                                    naps: [960 * 60...990 * 60], calendar: utc)
        XCTAssertEqual(d.highMinutes, 10 + 9, "waking and after the 90 minutes (minute 870 is still the last of them)")
        XCTAssertEqual(d.split.total, 30 + 10 + 60 + 90 + 10 + 30)
        XCTAssertEqual(d.split.counted, d.highMinutes)
        XCTAssertEqual(d.split.activity, 151, "the workout, its end minute and the 90 after")
        XCTAssertEqual(d.split.asleep, 30 + 30)
        // Counted: awake minutes outside workout + 90 and the nap, with a reading.
        let counted = 1200 - 420 - (871 - 720) - 31 - 5
        XCTAssertEqual(d.counted, counted)
        XCTAssertEqual(d.levelMinutes, [counted - 19, 0, 19])
        XCTAssertEqual(d.avg!, (Double(counted - 19) * 0.5 + 10 * 2.2 + 9 * 2.1) / Double(counted), accuracy: 1e-9)
        // The night's hours are empty; an awake hour is the mean of its counted minutes.
        XCTAssertNil(d.hourly[3])
        XCTAssertNil(d.hourly[12], "the workout hour")
        XCTAssertEqual(d.hourly[7]!, (10 * 2.2 + 50 * 0.5) / 60, accuracy: 1e-9)
        XCTAssertEqual(d.hourly[18]!, 0.5, accuracy: 1e-9)
        XCTAssertEqual(StressSummary.split(minutes: m, origin: 0, wake: 420 * 60, workouts: [720 * 60...780 * 60],
                                           naps: [960 * 60...990 * 60]), d.split)
    }

    func testDailyHourlyFollowsTheLocalClock() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!   // UTC+5:30
        var m = [Double?](repeating: 1.0, count: 120)
        for i in 0..<30 { m[i] = 2.0 }
        // Origin 00:00 UTC = 05:30 local: the first 30 minutes are 05:30-06:00 local.
        let d = StressSummary.daily(minutes: m, origin: 0, wake: 0, workouts: [], naps: [], calendar: cal)
        XCTAssertEqual(d.hourly[5]!, 2.0, accuracy: 1e-9)
        XCTAssertEqual(d.hourly[6]!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.hourly[7]!, 1.0, accuracy: 1e-9)
        XCTAssertEqual(d.hourly.compactMap { $0 }.count, 3)
        XCTAssertEqual(d.levelMinutes, [0, 90, 30])
        XCTAssertEqual(d.highMinutes, 30)
    }

    func testDailyWithoutReadings() {
        let d = StressSummary.daily(minutes: [nil, nil], origin: 0, workouts: [], naps: [], calendar: utc)
        XCTAssertNil(d.avg)
        XCTAssertEqual(d.counted, 0)
        XCTAssertEqual(d.highMinutes, 0)
        XCTAssertTrue(d.hourly.allSatisfy { $0 == nil })
    }

    func testUsualSleepWindowAcrossMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = 86_400
        let starts = [day + 23 * 3600 + 1800, 2 * day + 3600, 3 * day + 0]       // 23:30, 01:00, 00:00
        let ends = [2 * day + 7 * 3600 + 1800, 3 * day + 8 * 3600, 4 * day + 7 * 3600] // 07:30, 08:00, 07:00
        let w = StressSummary.sleepWindow(starts: starts, ends: ends, calendar: cal)
        XCTAssertEqual(w?.from, 23 * 60 + 30)
        XCTAssertEqual(w?.to, 8 * 60)
        XCTAssertTrue(StressSummary.contains(w!, clock: 3 * 60))
        XCTAssertTrue(StressSummary.contains(w!, clock: 23 * 60 + 45))
        XCTAssertFalse(StressSummary.contains(w!, clock: 15 * 60))
        XCTAssertNil(StressSummary.sleepWindow(starts: [1], ends: [2], calendar: cal))
    }
}
