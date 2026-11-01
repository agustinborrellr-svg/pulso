import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class CycleAndPressureTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testCyclePhases() throws {
        let m = CyclePhases.map(starts: ["2026-04-08", "2026-03-11"], ovulations: ["2026-03-25"], averageLength: 28,
                                through: "2026-05-31", today: "2026-04-26", calendar: cal)
        XCTAssertEqual(m["2026-03-11"]?.phase, .menstrual)
        XCTAssertEqual(m["2026-03-11"]?.cycleDay, 1)
        XCTAssertEqual(m["2026-03-15"]?.phase, .menstrual)
        XCTAssertEqual(m["2026-03-16"]?.phase, .follicular)
        XCTAssertEqual(m["2026-03-25"]?.phase, .ovulatory, "detected ovulation")
        XCTAssertEqual(m["2026-03-27"]?.phase, .luteal)
        XCTAssertEqual(m["2026-04-07"]?.cycleDay, 28)
        // Second cycle: ovulation predicted 14 days before the next (predicted) start.
        XCTAssertEqual(m["2026-04-26"]?.cycleDay, 19)
        XCTAssertEqual(m["2026-04-26"]?.predicted, false)
        XCTAssertEqual(m["2026-05-06"]?.phase, .menstrual, "next period predicted 28 days later")
        XCTAssertEqual(m["2026-05-06"]?.predicted, true)
        XCTAssertNil(m["2026-03-01"], "nothing before the first known start")
        XCTAssertTrue(CyclePhases.map(starts: [], ovulations: [], averageLength: nil, through: "2026-05-01", today: "2026-05-01").isEmpty)
    }

    func testBloodPressure() {
        XCTAssertEqual(BloodPressure.category(systolic: 115, diastolic: 75), .normal)
        XCTAssertEqual(BloodPressure.category(systolic: 125, diastolic: 75), .elevated)
        XCTAssertEqual(BloodPressure.category(systolic: 118, diastolic: 84), .stage1)
        XCTAssertEqual(BloodPressure.category(systolic: 145, diastolic: 85), .stage2)
        XCTAssertEqual(BloodPressure.category(systolic: 190, diastolic: 100), .crisis)
        let t0 = 1_790_000_000
        let r = [BloodPressureReading(ts: t0, systolic: 118, diastolic: 78), BloodPressureReading(ts: t0 + 3600, systolic: 126, diastolic: 82),
                 BloodPressureReading(ts: t0 + 86400, systolic: 120, diastolic: 80)]
        let d = BloodPressure.daily(r, calendar: cal)
        XCTAssertEqual(d.count, 2)
        XCTAssertEqual(d[0].systolic, 118...126)
        XCTAssertEqual(d[0].count, 2)
        let avg = BloodPressure.average(r, days: 7, now: Date(timeIntervalSince1970: TimeInterval(t0 + 2 * 86400)))
        XCTAssertEqual(avg?.systolic, 121)
        XCTAssertEqual(avg?.diastolic, 80)
        XCTAssertNil(BloodPressure.average(r, days: 1, now: Date(timeIntervalSince1970: TimeInterval(t0 + 30 * 86400))))
    }

    func testPeriodAverages() {
        var pts: [(day: String, value: Double)] = []
        for d in 1...30 { pts.append((String(format: "2026-09-%02d", d), 60)) }
        for d in 1...31 { pts.append((String(format: "2026-10-%02d", d), 54)) }
        pts.append(("2026-11-01", 99)) // too few days: no segment
        let s = PeriodAverages.segments(pts, calendar: cal)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].mean, 60)
        XCTAssertNil(s[0].changePct)
        XCTAssertEqual(s[1].changePct!, -10, accuracy: 1e-9)
        XCTAssertEqual(s[1].start, "2026-10-01")
        XCTAssertEqual(s[1].end, "2026-10-31")
        let weekly = PeriodAverages.segments(pts, weeks: 1, calendar: cal)
        XCTAssertGreaterThan(weekly.count, 7)
    }
}

final class SleepFactorsTests: XCTestCase {
    func testLevels() {
        var d = DaySummary(day: "2026-11-01")
        d.sleepMinutes = 333
        d.sleepNeedMinutes = 546
        d.sleepConsistency = 24
        d.sleepEfficiency = 0.96
        d.deepMinutes = 70
        d.remMinutes = 90
        let f = SleepFactors.of(d)
        XCTAssertEqual(f.map(\.key), ["hoursVsNeed", "regularity", "efficiency", "restorative"])
        XCTAssertEqual(f[0].value, 61, accuracy: 0.5)
        XCTAssertEqual(f[0].level, .deficient)
        XCTAssertEqual(f[1].level, .deficient)
        XCTAssertEqual(f[2].level, .optimal)
        XCTAssertEqual(f[3].level, .optimal, "48 % restorative")
        XCTAssertTrue(SleepFactors.of(DaySummary(day: "2026-11-01")).isEmpty)
    }
}
