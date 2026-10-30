import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class PulsoAgeTests: XCTestCase {
    func profile(age: Int) -> Profile {
        var p = Profile()
        p.birthYear = Calendar.current.component(.year, from: Date()) - age
        p.sex = .male
        return p
    }

    func days(_ n: Int, sleep: Double, steps: Int, rhr: Double, vo2: Double, zones: [Double], regularity: Double) -> [DaySummary] {
        (0..<n).map { i in
            var d = DaySummary(day: DayKey.shift("2026-10-26", days: -(n - 1 - i)))
            d.sleepMinutes = sleep
            d.steps = steps
            d.rhr = rhr
            d.vo2max = vo2
            d.zoneMinutes = zones
            d.strain = 10
            d.sleepConsistency = regularity
            return d
        }
    }

    func testHealthyHabitsMakeYouYounger() {
        let p = profile(age: 40)
        let good = PulsoAge.compute(days: days(60, sleep: 8 * 60, steps: 12000, rhr: 48, vo2: 52, zones: [20, 20, 15, 5, 3], regularity: 92),
                                    profile: p, today: "2026-10-26")
        let bad = PulsoAge.compute(days: days(60, sleep: 5.5 * 60, steps: 3000, rhr: 74, vo2: 30, zones: [2, 0, 0, 0, 0], regularity: 50),
                                   profile: p, today: "2026-10-26")
        XCTAssertEqual(good.age, 40)
        XCTAssertLessThan(good.difference ?? 0, -4)
        XCTAssertGreaterThan(bad.difference ?? 0, 3)
        XCTAssertEqual(good.measured, 7)
        // Total effect is bounded by the weights (±7.2 years).
        XCTAssertLessThanOrEqual(abs(good.difference ?? 0), 7.2 + 1e-9)
        // Same habits for six months: steady pace.
        XCTAssertEqual(good.pace ?? 0, 1, accuracy: 1e-9)
    }

    func testTooLittleDataGivesNoAge() {
        let r = PulsoAge.compute(days: days(5, sleep: 480, steps: 9000, rhr: 55, vo2: 45, zones: [10, 10, 5, 0, 0], regularity: 80),
                                 profile: profile(age: 30), today: "2026-10-26")
        XCTAssertNil(r.pulsoAge)
        XCTAssertNil(r.pace)
    }

    func testImprovingLatelyRaisesPaceBelowOne() {
        let p = profile(age: 35)
        // 5 months of poor sleep, then a good month (31 days: today's open cycle is left out).
        var list = days(150, sleep: 5.5 * 60, steps: 6000, rhr: 60, vo2: 40, zones: [10, 5, 0, 0, 0], regularity: 60)
        for i in (list.count - 31)..<list.count {
            list[i].sleepMinutes = 8 * 60
            list[i].sleepConsistency = 95
        }
        let r = PulsoAge.compute(days: list, profile: p, today: "2026-10-26")
        XCTAssertNotNil(r.pace)
        XCTAssertLessThan(r.pace ?? 9, 1, "better habits than your 6-month norm slow the clock")
        let sleep = r.items.first { $0.key == "sleepHours" }
        XCTAssertEqual(sleep?.position(sleep?.recent), 1)
    }
}
