import XCTest
import PulsoStore
import PulsoAnalytics
@testable import PulsoIntelligence

final class BehaviorsTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testAutomaticAndJournalBehaviours() throws {
        var days: [DaySummary] = []
        var journal: [JournalEntry] = []
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        for i in 0..<40 {
            let day = DayKey.string(start.addingTimeInterval(Double(i) * 86400), calendar: cal)
            var d = DaySummary(day: day)
            // Good sleep on even days → higher recovery the same day.
            let good = i % 2 == 0
            d.sleepPerformance = good ? 0.9 : 0.6
            // Alcohol logged on days divisible by 3 → lower recovery the next day.
            let drankYesterday = i > 0 && (i - 1) % 3 == 0
            d.recovery = (good ? 75 : 55) - (drankYesterday ? 20 : 0)
            d.strain = Double(8 + i % 5)
            let wake = start.addingTimeInterval(Double(i) * 86400 + 7 * 3600)
            d.sleepEnd = Int(wake.timeIntervalSince1970)
            d.sleepStart = d.sleepEnd! - 8 * 3600
            days.append(d)
            if i % 3 == 0 { journal.append(JournalEntry(day: day, key: "alcohol", value: 1)) }
            else { journal.append(JournalEntry(day: day, key: "reading", value: 1)) }
        }
        // One habit with too few answers stays locked.
        journal.append(JournalEntry(day: days[0].day, key: "whoop:¿Desayunaste?", value: 1))
        let r = Behaviors.analyze(days: days, workouts: [], journal: journal, label: { JournalCatalog.label($0) }, calendar: cal)

        let sleep = try XCTUnwrap(r.impact.first { $0.key == "auto.sleepScore" })
        XCTAssertTrue(sleep.automatic)
        XCTAssertGreaterThan(sleep.impactPct!, 20, "good sleep helps")
        XCTAssertEqual(sleep.helps, true)
        XCTAssertTrue(sleep.label.hasSuffix("%+ calificación del sueño"))

        let alcohol = try XCTUnwrap(r.impact.first { $0.key == "alcohol" })
        XCTAssertLessThan(alcohol.impactPct!, -15, "alcohol hurts the next day")
        XCTAssertEqual(alcohol.helps, false)
        XCTAssertGreaterThanOrEqual(alcohol.yes, 5)
        XCTAssertGreaterThanOrEqual(alcohol.no, 5)

        XCTAssertEqual(r.impact.first?.helps, true, "sorted from what helps most")
        XCTAssertEqual(r.impact.last?.helps, false)
        let breakfast = try XCTUnwrap(r.locked.first { $0.key == "whoop:¿Desayunaste?" })
        XCTAssertEqual(breakfast.yes, 1)
        XCTAssertNil(breakfast.impactPct)
        // Constant wake time every day: no «without» days, so it stays locked.
        XCTAssertTrue(r.locked.contains { $0.key == "auto.wakeConsistent" })
    }

    func testWorkoutTiming() {
        var days: [DaySummary] = []
        var workouts: [Workout] = []
        let start = cal.date(from: DateComponents(year: 2026, month: 9, day: 1))!
        for i in 0..<30 {
            let date = start.addingTimeInterval(Double(i) * 86400)
            var d = DaySummary(day: DayKey.string(date, calendar: cal))
            d.recovery = 60
            d.strain = 10
            days.append(d)
            if i % 2 == 0 {
                let late = i % 4 == 0
                let ts = Int(date.timeIntervalSince1970) + (late ? 20 : 8) * 3600
                workouts.append(Workout(start: ts, end: ts + 3600, sport: "Carrera", source: .manual, strain: 12))
            }
        }
        // Next-day recovery after late sessions is lower.
        for i in 0..<30 where i % 4 == 0 && i + 1 < 30 { days[i + 1].recovery = 40 }
        let r = Behaviors.analyze(days: days, workouts: workouts, journal: [], label: { $0 }, calendar: cal)
        let late = r.impact.first { $0.key == "auto.lateWorkout" }
        XCTAssertNotNil(late)
        XCTAssertLessThan(late?.impactPct ?? 0, -10)
    }
}
