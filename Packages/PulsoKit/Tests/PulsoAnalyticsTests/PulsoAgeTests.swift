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
        XCTAssertEqual(good.measured, 8)
        // Total effect is bounded by the penalties / benefits.
        XCTAssertLessThanOrEqual(abs(good.difference ?? 0), 12 + 1e-9)
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

    /// The years each habit adds or takes off land where a WHOOP Age report put them for the same values.
    func testMatchesReferenceReport() {
        let specs = PulsoAge.specs(age: 25, sex: .male, zones: { _ in nil }, strength: { _ in nil })
        func y(_ key: String, _ v: Double) -> Double { specs.first { $0.key == key }!.years(v)! }
        XCTAssertEqual(y("sleepHours", 6 * 60 + 29), 0.5, accuracy: 0.1, "6:29 of sleep adds about half a year")
        XCTAssertEqual(y("regularity", 56), 0.9, accuracy: 0.1)
        XCTAssertEqual(y("zonesLight", 4 * 60 + 3), -1.2, accuracy: 0.1)
        XCTAssertEqual(y("zonesHard", 2), 0.1, accuracy: 0.1)
        XCTAssertEqual(y("strength", 2), 1.5, accuracy: 0.1)
        XCTAssertEqual(y("steps", 8975), -0.2, accuracy: 0.1)
        XCTAssertEqual(y("sleepHours", 7 * 60), 0, accuracy: 1e-9, "7 h is neutral")
        XCTAssertEqual(y("sleepHours", 9 * 60), -0.8, accuracy: 1e-9, "capped at the optimal end")
        XCTAssertEqual(y("rhr", 85), 1.2, accuracy: 1e-9, "decreasing scales work too")
    }

    /// Imported days have no whole-day zones: their workouts' zone minutes and strength sessions count instead.
    func testImportedDaysUseWorkouts() {
        var list = days(40, sleep: 420, steps: 8000, rhr: 60, vo2: 45, zones: [0, 0, 0, 0, 0], regularity: 70)
        for i in list.indices { list[i].source = "whoop" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var ws: [Workout] = []
        for d in list where d.day < "2026-10-26" {
            let ts = Int(DayKey.date(d.day, calendar: cal)!.timeIntervalSince1970) + 18 * 3600
            ws.append(Workout(start: ts, end: ts + 3600, sport: "Fuerza", source: .whoop, strain: 9, zoneMinutes: [20, 20, 10, 5, 0]))
        }
        let r = PulsoAge.compute(days: list, profile: profile(age: 30), today: "2026-10-26", workouts: ws, calendar: cal)
        let light = r.items.first { $0.key == "zonesLight" }!
        let strength = r.items.first { $0.key == "strength" }!
        XCTAssertEqual(light.recent ?? 0, 50 * 7, accuracy: 1, "weekly minutes in zones 1-3 from the workouts")
        XCTAssertEqual(strength.recent ?? 0, 60 * 7, accuracy: 1)
        XCTAssertLessThan(light.years ?? 0, 0)
        let none = PulsoAge.compute(days: list, profile: profile(age: 30), today: "2026-10-26").items.first { $0.key == "strength" }!
        XCTAssertGreaterThan(none.years ?? 0, 1, "no strength sessions adds years")
    }
}
