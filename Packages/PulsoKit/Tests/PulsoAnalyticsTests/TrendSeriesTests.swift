import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class TrendSeriesTests: XCTestCase {
    func days(_ n: Int, to last: String, _ f: (Int) -> Double?) -> [DaySummary] {
        (0..<n).map { i in
            var d = DaySummary(day: DayKey.shift(last, days: -(n - 1 - i)))
            d.recovery = f(i)
            return d
        }
    }

    func testWeekWindowAverageAndPrevious() {
        // 14 days: the first week at 40, the second at 60, one missing day in the current week.
        let list = days(14, to: "2026-10-26") { i in i == 10 ? nil : (i < 7 ? 40 : 60) }
        let w = TrendSeries.window(days: list, value: { $0.recovery }, period: .week, today: "2026-10-26")
        XCTAssertEqual(w.from, "2026-10-20")
        XCTAssertEqual(w.to, "2026-10-26")
        XCTAssertEqual(w.points.count, 7)
        XCTAssertNil(w.points[3].value)
        XCTAssertEqual(w.summary, 60)
        XCTAssertEqual(w.previous, 40)
        XCTAssertEqual(w.values.count, 6)
        // One period back.
        let back = TrendSeries.window(days: list, value: { $0.recovery }, period: .week, offset: 1, today: "2026-10-26")
        XCTAssertEqual(back.to, "2026-10-19")
        XCTAssertEqual(back.summary, 40)
        XCTAssertNil(back.previous)
    }

    func testTotalsAreWeekly() {
        // 30 minutes a day in zones: 210 a week, whatever the window length.
        let list = days(60, to: "2026-10-26") { _ in 30 }
        let week = TrendSeries.window(days: list, value: { $0.recovery }, period: .week, today: "2026-10-26", aggregate: .total)
        XCTAssertEqual(week.summary ?? 0, 210, accuracy: 1e-9)
        let month = TrendSeries.window(days: list, value: { $0.recovery }, period: .month, today: "2026-10-26", aggregate: .total)
        XCTAssertEqual(month.summary ?? 0, 210, accuracy: 1e-9)
        // Only two weeks measured inside a six-month window: still 210 a week, not diluted over 26 weeks.
        let short = days(14, to: "2026-10-26") { _ in 30 }
        let half = TrendSeries.window(days: short, value: { $0.recovery }, period: .halfYear, today: "2026-10-26", aggregate: .total)
        XCTAssertEqual(half.summary ?? 0, 210, accuracy: 1e-9)
    }

    func testHalfYearIsWeekly() {
        let list = days(200, to: "2026-10-26") { i in Double(i % 7) }
        let w = TrendSeries.window(days: list, value: { $0.recovery }, period: .halfYear, today: "2026-10-26")
        XCTAssertEqual(w.points.count, 26)
        XCTAssertEqual(w.points.last?.day, DayKey.shift("2026-10-26", days: -6))
        XCTAssertEqual(w.points.compactMap(\.value).allSatisfy { abs($0 - 3) < 1e-9 }, true, "every week averages 0…6 = 3")
    }

    func testEmptyHistory() {
        let w = TrendSeries.window(days: [], value: { $0.recovery }, period: .month, today: "2026-10-26")
        XCTAssertEqual(w.points.count, 30)
        XCTAssertNil(w.summary)
        XCTAssertNil(w.previous)
    }
}
