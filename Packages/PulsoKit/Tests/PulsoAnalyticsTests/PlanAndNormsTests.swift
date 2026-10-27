import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class PlanAndNormsTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    func testNormalHelpers() {
        XCTAssertEqual(Stats.normalCDF(0), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Stats.normalCDF(1.6449), 0.95, accuracy: 1e-4)
        for p in [0.01, 0.2, 0.5, 0.8, 0.975] {
            XCTAssertEqual(Stats.normalCDF(Stats.normalQuantile(p)), p, accuracy: 1e-7)
        }
    }

    func testVO2Norms() {
        // The median of your group is the 50th percentile; it drops with age.
        XCTAssertEqual(VO2Norms.percentile(VO2Norms.median(age: 40, sex: .male), age: 40, sex: .male), 50, accuracy: 1e-6)
        XCTAssertLessThan(VO2Norms.median(age: 60, sex: .male), VO2Norms.median(age: 30, sex: .male))
        // 42 at 36 (male): somewhat below the median of ≈ 40.6? No: above it.
        let p = VO2Norms.percentile(42, age: 36, sex: .male)
        XCTAssertEqual(p, 100 * Stats.normalCDF((42 - 40.6) / 7), accuracy: 1e-6)
        let bands = VO2Norms.bands(age: 36, sex: .male)
        XCTAssertEqual(bands.count, 5)
        XCTAssertEqual(zip(bands, bands.dropFirst()).allSatisfy { $0.upper == $1.lower }, true, "bands are contiguous")
        XCTAssertEqual(VO2Norms.band(VO2Norms.median(age: 36, sex: .male), age: 36, sex: .male).label, "En la media")
        XCTAssertEqual(VO2Norms.band(70, age: 36, sex: .male).label, "Excelente")
        XCTAssertEqual(VO2Norms.band(20, age: 36, sex: .male).label, "Bajo")
    }

    func testWeekStartsOnMonday() {
        XCTAssertEqual(WeeklyPlan.weekStart("2026-10-29", calendar: cal), "2026-10-26") // Thursday → Monday
        XCTAssertEqual(WeeklyPlan.weekStart("2026-10-26", calendar: cal), "2026-10-26")
        XCTAssertEqual(WeeklyPlan.weekStart("2026-11-01", calendar: cal), "2026-10-26") // Sunday
    }

    func testPlanProgress() {
        // Five weeks of 30 min/day in zones 1-3, 7 h sleep, 7000 steps; alcohol twice a week.
        var days: [DaySummary] = []
        var journal: [JournalEntry] = []
        for i in 0..<35 {
            var d = DaySummary(day: DayKey.shift("2026-09-28", days: i, calendar: cal))
            d.strain = i % 7 == 6 ? 6 : 12
            d.zoneMinutes = [20, 7, 3, 0, 0]
            d.sleepMinutes = 7 * 60
            d.steps = 7000
            days.append(d)
            if i % 7 == 4 || i % 7 == 5 { journal.append(JournalEntry(day: d.day, key: "alcohol", value: 1)) }
        }
        let goals = [
            PlanGoal(id: "z", kind: .zonesLight, target: 150),
            PlanGoal(id: "s", kind: .sleepHours, target: 8 * 60),
            PlanGoal(id: "p", kind: .steps, target: 8000),
            PlanGoal(id: "a", kind: .habitNo, target: 1, habit: "alcohol"),
            PlanGoal(id: "d", kind: .activeDays, target: 4),
        ]
        // Wednesday of the last week: three days measured so far.
        let p = WeeklyPlan.progress(goals: goals, days: days.filter { $0.day <= "2026-10-28" }, workouts: [], journal: journal,
                                    today: "2026-10-28", calendar: cal)
        let byID = Dictionary(uniqueKeysWithValues: p.map { ($0.goal.id, $0) })
        XCTAssertEqual(byID["z"]?.value, 90, "3 days × 30 min")
        XCTAssertEqual(byID["z"]?.previous, 210, "a full week before")
        XCTAssertEqual(byID["z"]?.fraction ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertFalse(byID["z"]!.met)
        XCTAssertEqual(byID["s"]?.level, 1, "7 of 8 hours: sufficient")
        XCTAssertEqual(byID["p"]?.fraction ?? 0, 7000.0 / 8000, accuracy: 1e-9)
        XCTAssertTrue(byID["a"]!.met, "no alcohol yet this week")
        XCTAssertEqual(byID["a"]?.previous, 2)
        XCTAssertEqual(byID["d"]?.value, 3)
    }
}
