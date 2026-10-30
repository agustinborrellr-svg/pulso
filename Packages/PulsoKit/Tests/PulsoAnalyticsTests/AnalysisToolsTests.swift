import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class AnalysisToolsTests: XCTestCase {
    func testWaterfallAddsUpToTheScore() {
        let c = [
            Contributor(key: "hrv", label: "VFC", value: 45, baseline: 55, unit: "ms", impact: -0.45),
            Contributor(key: "rhr", label: "FC reposo", value: 55, baseline: 56, unit: "lpm", impact: 0.06),
            Contributor(key: "sleep", label: "Sueño", value: 92, baseline: 85, unit: "%", impact: 0.09),
            Contributor(key: "resp", label: "Respiración", value: 15, baseline: 15, unit: "rpm", impact: 0),
        ]
        let steps = RecoveryWaterfall.steps(c)
        XCTAssertEqual(steps.first?.key, "hrv", "biggest factor first")
        let expected = Recovery.curve(composite: c.reduce(0) { $0 + $1.impact })
        XCTAssertEqual(steps.last!.total, expected, accuracy: 1e-9)
        XCTAssertEqual(RecoveryWaterfall.neutral + steps.reduce(0) { $0 + $1.points }, expected, accuracy: 1e-9)
        XCTAssertLessThan(steps[0].points, 0)
    }

    func testRelation() throws {
        let x: [Double?] = (0..<30).map { Double($0) }
        let y: [Double?] = (0..<30).map { (i: Int) -> Double? in
            if i == 5 { return nil }
            let wobble: Double = i % 2 == 0 ? 0.5 : -0.5
            return 2 * Double(i) + 1 + wobble
        }
        let p = Relation.pairs(x, y)
        XCTAssertEqual(p.count, 29)
        let r = try XCTUnwrap(Relation.fit(p))
        XCTAssertGreaterThan(r.r, 0.99)
        XCTAssertEqual(r.slope, 2, accuracy: 0.05)
        XCTAssertEqual(r.strength, "Relación fuerte")
        // Next-day lag shifts the pairing.
        XCTAssertEqual(Relation.pairs(x, y, lag: 1).first?.y, y[1]!)
        XCTAssertNil(Relation.fit([(1, 1), (1, 2), (1, 3)]), "no spread in x")
    }

    func testStreaksAndRecords() {
        func d(_ k: String, _ rec: Double?, strain: Double? = nil) -> DaySummary {
            var x = DaySummary(day: k)
            x.recovery = rec
            x.strain = strain
            return x
        }
        let days = [d("2026-10-01", 70), d("2026-10-02", 80, strain: 15), d("2026-10-03", 40),
                    d("2026-10-04", 75), d("2026-10-05", 68), d("2026-10-06", 90)]
        let s = Records.streak(days, today: "2026-10-07") { $0.recovery.map { $0 >= 67 } }
        XCTAssertEqual(s.current, 3, "today without data does not break it")
        XCTAssertEqual(s.best, 3)
        XCTAssertEqual(s.bestEnd, "2026-10-06")
        let gap = Records.streak(days.filter { $0.day != "2026-10-05" }, today: "2026-10-06") { $0.recovery.map { $0 >= 67 } }
        XCTAssertEqual(gap.current, 1, "a missing day breaks the streak")
        let recs = Records.personalBests(days)
        XCTAssertEqual(recs.first { $0.title == "Mejor recuperación" }?.day, "2026-10-06")
        XCTAssertEqual(recs.first { $0.title == "Día más exigente" }?.value, 15)
    }

    func testMonthlyReport() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var days: [DaySummary] = []
        for i in 1...30 {
            var a = DaySummary(day: String(format: "2026-09-%02d", i))
            a.recovery = 50
            a.rhr = 58
            days.append(a)
            var b = DaySummary(day: String(format: "2026-10-%02d", i))
            b.recovery = i % 3 == 0 ? 20 : 80
            b.rhr = 55
            days.append(b)
        }
        let oct = cal.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 18))!
        let ws = [Workout(start: Int(oct.timeIntervalSince1970), end: Int(oct.timeIntervalSince1970) + 3600, sport: "Carrera", source: .manual,
                          strain: 12, avgHR: 150, maxHR: 175, kcal: 600, zoneMinutes: [0, 0, 0, 0, 0])]
        let r = MonthlyReport.build(month: "2026-10", days: days, workouts: ws, calendar: cal)
        XCTAssertEqual(r.daysWithData, 30)
        XCTAssertEqual(r.workouts, 1)
        XCTAssertEqual(r.workoutMinutes, 60)
        XCTAssertEqual(r.topSports.first?.name, "Carrera")
        XCTAssertEqual(r.redDays, 10)
        XCTAssertEqual(r.greenDays, 20)
        let rhr = r.lines.first { $0.title == "FC en reposo" }!
        XCTAssertEqual(rhr.delta!, -3, accuracy: 1e-9)
        XCTAssertFalse(rhr.higherIsBetter)
        XCTAssertEqual(MonthlyReport.shiftMonth("2026-01", -1), "2025-12")
        XCTAssertEqual(MonthlyReport.shiftMonth("2026-12", 1), "2027-01")
    }
}

final class RelationByDateTests: XCTestCase {
    func testNextDayPairsByDateAcrossGaps() {
        let days = ["2026-10-01", "2026-10-02", "2026-10-05", "2026-10-06"]
        let x: [Double?] = [1, 2, 3, 4]
        let y: [Double?] = [10, 20, 30, 40]
        let p = Relation.pairs(days: days, x, y, lagDays: 1)
        XCTAssertEqual(p.map(\.x), [1, 3], "Oct 2 → Oct 5 is not 'the next day'")
        XCTAssertEqual(p.map(\.y), [20, 40])
        XCTAssertEqual(Relation.pairs(days: days, x, y, lagDays: 0).count, 4)
    }
}
