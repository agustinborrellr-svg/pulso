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

    func spec(_ key: String, age: Int = 30) -> PulsoAge.Spec {
        PulsoAge.specs(age: age, sex: .male, zones: { _ in nil }, strength: { _ in nil }).first { $0.key == key }!
    }

    /// Each habit's years come straight from the study's relative risk through the Gompertz rate.
    func testYearsFollowThePublishedRisks() {
        let g = PulsoAge.gompertz
        XCTAssertEqual(spec("sleepHours").years(6 * 60)!, log(1.06) / g, accuracy: 1e-9, "RR 1.06 for 6 h (Liu 2017)")
        XCTAssertEqual(spec("sleepHours").years(7.5 * 60)!, 0, accuracy: 1e-9, "7–8 h is the reference")
        XCTAssertEqual(spec("sleepHours").years(9 * 60)!, log(1.30) / g, accuracy: 1e-9, "RR 1.30 at 9 h (Cappuccio 2010)")
        XCTAssertEqual(spec("regularity").years(41)!, log(1.53) / g, accuracy: 1e-9, "Pase 2023")
        XCTAssertEqual(spec("regularity").years(75)!, log(0.90) / g, accuracy: 1e-9)
        XCTAssertEqual(spec("steps").years(2000)!, log(1 / 0.53) / g, accuracy: 1e-9, "Ding 2025")
        XCTAssertEqual(spec("steps").years(9000)!, 0, accuracy: 1e-9, "no extra benefit past 7 000")
        XCTAssertEqual(spec("strength").years(0)!, log(1 / 0.85) / g, accuracy: 1e-9, "Momma 2022")
        XCTAssertEqual(spec("strength").years(45)!, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(spec("strength").years(200)!, 0, "J-shape: very high volumes lose the benefit")
        XCTAssertEqual(spec("rhr").years(70)!, log(1.09) / g, accuracy: 1e-9, "Zhang 2016: RR 1.09 per 10 bpm")
        let avg = 47 - 0.4 * 10.0
        XCTAssertEqual(spec("vo2max").years(avg + 3.5)!, log(0.86) / g, accuracy: 1e-6, "RR 0.86 per MET")
        XCTAssertEqual(spec("vo2max").years(avg + 30)!, log(sqrt(0.47)) / g, accuracy: 1e-6, "bounded by high vs low fitness")
        // Same values as a reference report, within half a year.
        XCTAssertEqual(spec("sleepHours").years(6 * 60 + 29)!, 0.5, accuracy: 0.25)
        XCTAssertEqual(spec("regularity").years(56)!, 0.9, accuracy: 0.25)
        XCTAssertEqual(spec("strength").years(2)!, 1.5, accuracy: 0.5)
    }

    func testHealthyHabitsMakeYouYounger() {
        let p = profile(age: 40)
        let good = PulsoAge.compute(days: days(100, sleep: 7.5 * 60, steps: 9000, rhr: 50, vo2: 48, zones: [20, 20, 10, 8, 4], regularity: 80),
                                    profile: p, today: "2026-10-27")
        let bad = PulsoAge.compute(days: days(100, sleep: 5.5 * 60, steps: 3000, rhr: 74, vo2: 30, zones: [2, 0, 0, 0, 0], regularity: 45),
                                   profile: p, today: "2026-10-27")
        XCTAssertEqual(good.age, 40)
        XCTAssertLessThan(good.difference ?? 0, -2)
        XCTAssertGreaterThan(bad.difference ?? 0, 8)
        // Same habits for 90 days: steady age.
        XCTAssertEqual(good.pace ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(good.recentAge ?? 0, good.pulsoAge ?? 1, accuracy: 1e-9)
    }

    /// Steps, moderate and vigorous minutes are one habit: only the best of them counts.
    func testAerobicActivityCountsOnce() {
        let p = profile(age: 30)
        let r = PulsoAge.compute(days: days(100, sleep: 450, steps: 9000, rhr: 60, vo2: 43, zones: [0, 0, 0, 0, 0], regularity: 60),
                                 profile: p, today: "2026-10-27")
        let counted = r.items.filter { PulsoAge.aerobicKeys.contains($0.key) && $0.counted }
        XCTAssertEqual(counted.map(\.key), ["steps"], "9 000 steps meet the aerobic guideline; zero zone minutes don't add years")
        XCTAssertEqual(r.difference ?? 9, PulsoAge.specs(age: 30, sex: .male, zones: { _ in nil }, strength: { _ in nil })
            .first { $0.key == "strength" }!.years(0)!, accuracy: 0.01, "only the missing strength training remains")
    }

    func testRecentMonthSetsThePace() {
        let p = profile(age: 35)
        var list = days(120, sleep: 5.5 * 60, steps: 6000, rhr: 60, vo2: 40, zones: [10, 5, 0, 0, 0], regularity: 50)
        for i in (list.count - 30)..<list.count {
            list[i].sleepMinutes = 7.5 * 60
            list[i].sleepConsistency = 75
        }
        let r = PulsoAge.compute(days: list, profile: p, today: "2026-10-27")
        XCTAssertLessThan(r.recentAge ?? 99, r.pulsoAge ?? 0, "your last month is younger than your 90 days")
        XCTAssertLessThan(r.pace ?? 9, 1)
        let sleep = r.items.first { $0.key == "sleepHours" }!
        XCTAssertEqual(sleep.recent ?? 0, 450, accuracy: 1e-9)
        XCTAssertGreaterThan(sleep.longTerm ?? 0, 330)
    }

    func testTooLittleDataGivesNoAge() {
        let r = PulsoAge.compute(days: days(10, sleep: 480, steps: 9000, rhr: 55, vo2: 45, zones: [10, 10, 5, 0, 0], regularity: 80),
                                 profile: profile(age: 30), today: "2026-10-27")
        XCTAssertNil(r.pulsoAge)
        XCTAssertNil(r.pace)
    }

    /// Imported days have no whole-day zones: their workouts' zone minutes and strength sessions count instead.
    func testImportedDaysUseWorkouts() {
        var list = days(100, sleep: 420, steps: 3000, rhr: 60, vo2: 45, zones: [0, 0, 0, 0, 0], regularity: 70)
        for i in list.indices { list[i].source = "whoop" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var ws: [Workout] = []
        for d in list {
            let ts = Int(DayKey.date(d.day, calendar: cal)!.timeIntervalSince1970) + 18 * 3600
            ws.append(Workout(start: ts, end: ts + 600, sport: "Fuerza", source: .whoop, strain: 9, zoneMinutes: [20, 20, 10, 5, 0]))
        }
        let r = PulsoAge.compute(days: list, profile: profile(age: 30), today: "2026-10-27", workouts: ws, calendar: cal)
        let light = r.items.first { $0.key == "zonesLight" }!
        let strength = r.items.first { $0.key == "strength" }!
        XCTAssertEqual(light.longTerm ?? 0, 50 * 7, accuracy: 1, "weekly minutes in zones 1-3 from the workouts")
        XCTAssertEqual(strength.longTerm ?? 0, 10 * 7, accuracy: 1)
        XCTAssertTrue(light.counted, "350 min/week beats 3 000 steps")
        XCTAssertLessThan(light.years ?? 0, 0)
    }
}
