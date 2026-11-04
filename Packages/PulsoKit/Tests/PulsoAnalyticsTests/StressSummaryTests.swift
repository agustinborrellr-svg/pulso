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
        XCTAssertEqual(s.sleep, 15)
        XCTAssertEqual(s.other, 12)
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
