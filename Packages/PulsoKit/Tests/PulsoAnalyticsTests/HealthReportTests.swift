import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class HealthReportTests: XCTestCase {
    private let end = "2026-11-04"

    private func days(_ n: Int) -> [DaySummary] {
        (0..<n).map { i in
            var d = DaySummary(day: DayKey.shift(end, days: -i))
            d.rhr = 50 + Double(i % 5)
            d.respRate = 15.8
            d.sleepMinutes = 420
            return d
        }
    }

    func testThirtyDaysInsideASixMonthWindow() {
        let r = HealthReport.build(days: days(200), workouts: [], end: end)
        XCTAssertEqual(r.days.count, 30)
        XCTAssertEqual(r.longDays.count, 180)
        XCTAssertEqual(r.days.last, end)
        XCTAssertEqual(r.longDays.first, DayKey.shift(end, days: -179))
        XCTAssertEqual(r.recent(r.sleep).average, 7)
        XCTAssertEqual(r.long["rhr"]?.range, 50...54, "10th to 90th percentile of the six months")
    }

    func testAMonthNeedsAWeekOfData() {
        let r = HealthReport.build(days: days(12), workouts: [], end: end)
        XCTAssertEqual(r.long["resp"]?.monthly["2026-10"] ?? 0, 15.8, accuracy: 1e-9, "eight days of October")
        XCTAssertNil(r.long["resp"]?.monthly["2026-11"], "four days of November are not a month yet")
        XCTAssertNil(r.long["resp"]?.range, "no usual band from twelve nights")
    }

    func testAerobicMinutesComeFromTheWorkoutZones() {
        let ts = Int(DayKey.date(end)!.timeIntervalSince1970) + 18 * 3600
        let w = [Workout(start: ts, end: ts + 3600, sport: "Natación", source: .auto, strain: 10, avgHR: 130, maxHR: 160,
                         kcal: 400, zoneMinutes: [10, 20, 15, 8, 2]),
                 Workout(start: ts - 86400, end: ts - 86400 + 600, sport: "Caminata", source: .auto, strain: 4, avgHR: 100,
                         maxHR: 110, kcal: 50, zoneMinutes: [5, 0, 0, 0, 0])]
        let r = HealthReport.build(days: days(30), workouts: w, end: end)
        XCTAssertEqual(r.recent(r.moderate).values.last, 45)
        XCTAssertEqual(r.recent(r.vigorous).values.last, 10)
        XCTAssertEqual(r.aerobicAverage!, 60.0 / 30, accuracy: 1e-9)
        XCTAssertEqual(r.topSports.map(\.name), ["Caminata", "Natación"])
    }
}
