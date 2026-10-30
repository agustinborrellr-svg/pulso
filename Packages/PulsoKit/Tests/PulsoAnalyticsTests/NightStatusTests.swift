import XCTest
@testable import PulsoAnalytics
import PulsoStore

final class NightStatusTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var wakes: [Int] { (20...28).map { Int(at($0, 8).timeIntervalSince1970) } }

    func testTodaysCycleIsAlwaysOK() {
        XCTAssertEqual(NightStatus.evaluate(now: at(30, 12), currentCycleDay: "2026-10-30",
                                            recentCycleStarts: wakes, lastSampleTs: nil, calendar: cal), .ok)
    }

    func testStillAwakeAfterMidnightIsYesterdaysCycle() {
        XCTAssertEqual(NightStatus.evaluate(now: at(30, 2), currentCycleDay: "2026-10-29",
                                            recentCycleStarts: wakes, lastSampleTs: Int(at(30, 2).timeIntervalSince1970),
                                            calendar: cal), .ok)
    }

    func testMorningWithoutDownloadedNightIsAwaitingData() {
        XCTAssertEqual(NightStatus.evaluate(now: at(30, 9, 30), currentCycleDay: "2026-10-29",
                                            recentCycleStarts: wakes, lastSampleTs: Int(at(29, 23).timeIntervalSince1970),
                                            calendar: cal), .awaitingData)
    }

    func testMorningCoveredButNoSleepIsNotDetected() {
        XCTAssertEqual(NightStatus.evaluate(now: at(30, 10), currentCycleDay: "2026-10-29",
                                            recentCycleStarts: wakes, lastSampleTs: Int(at(30, 9, 55).timeIntervalSince1970),
                                            calendar: cal), .notDetected)
    }

    func testUsesTheUsualWakeTime() {
        let late = (20...28).map { Int(at($0, 10, 30).timeIntervalSince1970) }
        XCTAssertEqual(NightStatus.evaluate(now: at(30, 10), currentCycleDay: "2026-10-29",
                                            recentCycleStarts: late, lastSampleTs: nil, calendar: cal), .ok)
    }
}
