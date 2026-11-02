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

    func spec(_ key: String, age: Int = 30, sex: Sex = .male) -> PulsoAge.Spec {
        PulsoAge.specs(age: age, sex: sex, zones: { _ in nil }, strength: { _ in nil }).first { $0.key == key }!
    }

    /// Years = 10 · ln(HR) (white paper), from the slopes the white paper cites.
    func testYearsFollowTheWhitePaper() {
        XCTAssertEqual(spec("sleepHours").years(6 * 60)!, 10 * log(1.12), accuracy: 1e-9, "short sleep HR 1.12 (Itani 2017)")
        XCTAssertEqual(spec("sleepHours").years(7 * 60)!, 0, accuracy: 1e-9, "7 h is the neutral point")
        XCTAssertLessThan(spec("sleepHours").years(8 * 60)!, 0, "7–9 h: a small benefit")
        XCTAssertEqual(spec("sleepHours").years(10 * 60)!, 0, accuracy: 1e-9, "over 9 h: no effect")
        XCTAssertEqual(spec("regularity").years(70)!, 0, accuracy: 1e-9)
        XCTAssertEqual(spec("rhr").years(70)!, 10 * log(1.09), accuracy: 1e-9, "Zhang 2016: +9 % per 10 bpm")
        XCTAssertEqual(spec("rhr", sex: .female).years(64)!, 0, accuracy: 1e-9, "64 bpm for women")
        XCTAssertEqual(spec("vo2max").years(44 + 3.5)!, 10 * log(0.87), accuracy: 1e-6, "−13 % per MET over the age-30 target of 44")
        XCTAssertEqual(PulsoAge.vo2Target(age: 30, sex: .female), 38)
        XCTAssertEqual(PulsoAge.vo2Target(age: 100, sex: .male), 21)
        XCTAssertEqual(spec("steps").years(8000)!, 0, accuracy: 1e-9)
        XCTAssertEqual(spec("steps", age: 65).years(5600)!, 0, accuracy: 1e-9, "5 600 steps from 60")
        XCTAssertEqual(spec("strength").years(40)!, 0, accuracy: 1e-9)
        XCTAssertEqual(spec("strength").years(300)!, spec("strength").years(120)!, accuracy: 1e-9, "no extra benefit past 120 min")
        XCTAssertEqual(spec("zonesHard").years(10)!, 0, accuracy: 1e-9)
        XCTAssertEqual(spec("zonesLight", age: 80).neutral, 70, "zones 1-3 target falls with age")
    }

    /// The white paper's median 30-year-old members score −1.6 years (lean body mass, not in Pulso, ~0).
    func testWhitePaperMedianMembers() {
        func total(sex: Sex, sleep: Double, cons: Double, steps: Double, light: Double, hard: Double, strength: Double,
                   vo2: Double, rhr: Double) -> Double {
            let v: [String: Double] = ["sleepHours": sleep, "regularity": cons, "steps": steps, "zonesLight": light,
                                       "zonesHard": hard, "strength": strength, "vo2max": vo2, "rhr": rhr]
            return PulsoAge.specs(age: 30, sex: sex, zones: { _ in nil }, strength: { _ in nil })
                .reduce(0) { $0 + ($1.years(v[$1.key]) ?? 0) * PulsoAge.adjustment }
        }
        XCTAssertEqual(total(sex: .male, sleep: 420, cons: 67, steps: 10900, light: 141, hard: 6, strength: 46, vo2: 46.8, rhr: 58),
                       -1.6, accuracy: 0.3)
        XCTAssertEqual(total(sex: .female, sleep: 438, cons: 68, steps: 11500, light: 124, hard: 7, strength: 56, vo2: 40, rhr: 63),
                       -1.6, accuracy: 0.3)
    }

    func testHealthyHabitsMakeYouYounger() {
        let p = profile(age: 40)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        func workouts(_ list: [DaySummary], zones: [Double], sport: String) -> [Workout] {
            list.map { d in
                let ts = Int(DayKey.date(d.day, calendar: cal)!.timeIntervalSince1970) + 18 * 3600
                return Workout(start: ts, end: ts + 2400, sport: sport, source: .manual, strain: 9, zoneMinutes: zones)
            }
        }
        let goodDays = days(200, sleep: 7.5 * 60, steps: 9000, rhr: 50, vo2: 48, zones: [], regularity: 85)
        let good = PulsoAge.compute(days: goodDays, profile: p, today: "2026-10-27",
                                    workouts: workouts(goodDays, zones: [20, 10, 5, 3, 2], sport: "Fuerza"), calendar: cal)
        let bad = PulsoAge.compute(days: days(200, sleep: 5.5 * 60, steps: 3000, rhr: 74, vo2: 30, zones: [], regularity: 45),
                                   profile: p, today: "2026-10-27", calendar: cal)
        XCTAssertEqual(good.age, 40)
        XCTAssertLessThan(good.difference ?? 0, -2)
        XCTAssertGreaterThan(bad.difference ?? 0, 6)
        // Same habits for 6 months: steady age, pace 1x.
        XCTAssertEqual(good.pace ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(good.recentAge ?? 0, good.pulsoAge ?? 1, accuracy: 1e-9)
    }

    func testRecentMonthSetsThePace() {
        let p = profile(age: 35)
        var list = days(200, sleep: 5.5 * 60, steps: 6000, rhr: 60, vo2: 40, zones: [10, 5, 0, 0, 0], regularity: 50)
        for i in (list.count - 30)..<list.count {
            list[i].sleepMinutes = 7.5 * 60
            list[i].sleepConsistency = 75
        }
        let r = PulsoAge.compute(days: list, profile: p, today: "2026-10-27")
        XCTAssertLessThan(r.recentAge ?? 99, r.pulsoAge ?? 0, "your last month is younger than your 6 months")
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
        XCTAssertTrue(light.counted)
        XCTAssertLessThan(light.years ?? 0, 0)
    }
}
