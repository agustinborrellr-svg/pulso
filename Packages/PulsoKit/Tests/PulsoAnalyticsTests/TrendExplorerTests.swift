import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class TrendExplorerTests: XCTestCase {
    func days(_ n: Int, to last: String, _ f: (Int) -> Double?) -> [DaySummary] {
        (0..<n).map { i in
            var d = DaySummary(day: DayKey.shift(last, days: -(n - 1 - i)))
            d.hrv = f(i)
            return d
        }
    }

    func testRangesAndYearBuckets() {
        let list = days(730, to: "2026-10-30") { i in i < 365 ? 40 : 60 }
        let m = TrendExplorer.window(days: list, value: { $0.hrv }, range: .quarter, today: "2026-10-30")
        XCTAssertEqual(m.points.count, 90)
        XCTAssertEqual(m.from, "2026-08-02")
        XCTAssertEqual(m.summary, 60)
        let y = TrendExplorer.window(days: list, value: { $0.hrv }, range: .year, today: "2026-10-30")
        XCTAssertEqual(y.points.count, 52)
        XCTAssertEqual(y.points.last?.day, "2026-10-24", "the last weekly point ends today")
        XCTAssertEqual(y.summary, 60)
        XCTAssertEqual(y.previous, 40)
    }

    func testMissingDaysStayMissing() {
        let list = days(7, to: "2026-10-30") { i in i == 3 ? nil : 50 }
        let w = TrendExplorer.window(days: list, value: { $0.hrv }, range: .week, today: "2026-10-30")
        XCTAssertNil(w.points[3].value)
        XCTAssertEqual(w.values.count, 6)
    }

    func testRecentChangeFlagsOnlyBeyondNormalSwing() {
        // Baseline alternating 45/55 (normal noise), then a week of the same noise: not notable.
        let calm = days(35, to: "2026-10-30") { i in i % 2 == 0 ? 45 : 55 }
        let c = TrendExplorer.recentChange(days: calm, value: { $0.hrv }, today: "2026-10-30")
        XCTAssertNotNil(c)
        XCTAssertFalse(c!.isNotable)
        // Same baseline, last week 15 ms lower: notable.
        let drop = days(35, to: "2026-10-30") { i in i >= 28 ? 35 : (i % 2 == 0 ? 45 : 55) }
        let d = TrendExplorer.recentChange(days: drop, value: { $0.hrv }, today: "2026-10-30")!
        XCTAssertTrue(d.isNotable)
        XCTAssertEqual(d.recent, 35)
        XCTAssertEqual(d.baselineDays, 28)
        // Too little baseline: no verdict.
        let short = days(12, to: "2026-10-30") { _ in 50 }
        XCTAssertNil(TrendExplorer.recentChange(days: short, value: { $0.hrv }, today: "2026-10-30"))
    }

    func testStandardized() {
        let s = TrendExplorer.standardized([TrendSample(day: "a", value: 10), TrendSample(day: "b", value: nil),
                                            TrendSample(day: "c", value: 20)])
        XCTAssertNil(s[1].value)
        XCTAssertEqual(s[0].value!, -0.7071, accuracy: 0.001)
        XCTAssertEqual(s[2].value!, 0.7071, accuracy: 0.001)
    }

    func testMonthSummarySeparatesImportedAndMissing() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var list: [DaySummary] = []
        for i in 1...10 {
            var d = DaySummary(day: String(format: "2026-10-%02d", i))
            d.recovery = i == 5 ? nil : Double(i * 10)
            if i <= 3 { d.source = "whoop" }
            list.append(d)
        }
        let s = CalendarMonth.summary(month: "2026-10", days: list, today: "2026-10-12", value: { $0.recovery }, calendar: cal)
        XCTAssertEqual(s.daysWithData, 9)
        XCTAssertEqual(s.elapsedDays, 12)
        XCTAssertEqual(s.daysWithoutData, 3)
        XCTAssertEqual(s.importedDays, 3)
        XCTAssertEqual(s.measuredDays, 6)
        XCTAssertEqual(s.highest, CalendarMonth.Extreme(day: "2026-10-10", value: 100))
        XCTAssertEqual(s.lowest?.day, "2026-10-01")
        XCTAssertEqual(CalendarMonth.layout("2026-10", calendar: cal).leading, 3, "1 Oct 2026 is a Thursday")
        XCTAssertEqual(CalendarMonth.layout("2026-10", calendar: cal).count, 31)
    }

    func testImportedDaysDoNotCountAsWorn() {
        var list: [DaySummary] = []
        for i in 1...6 {
            var d = DaySummary(day: String(format: "2026-10-%02d", i))
            d.wornMinutes = 900
            if i == 3 || i == 4 { d.source = "whoop"; d.recovery = 70 }
            list.append(d)
        }
        let s = Records.streak(list, today: "2026-10-06", rule: Records.wornWithStrap)
        XCTAssertEqual(s.current, 2)
        XCTAssertEqual(s.best, 2)
        XCTAssertEqual(Records.nextMilestone(after: 2), 7)
        XCTAssertEqual(Records.nextMilestone(after: 7), 14)
        XCTAssertNil(Records.nextMilestone(after: 400))
    }

    func testVO2RecordIsLabelledEstimated() {
        var d = DaySummary(day: "2026-10-01")
        d.vo2max = 48
        XCTAssertEqual(Records.personalBests([d]).first?.title, "VO₂ máx más alto (estimado)")
    }
}
