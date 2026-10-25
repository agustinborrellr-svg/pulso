import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class DemoDataTests: XCTestCase {
    func testDemoFillsEveryScreen() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-demo-\(UUID().uuidString).sqlite")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        var last = 0.0
        let start = Date()
        let days = try DemoData.populate(db: db, days: 14, now: now, calendar: cal, progress: { last = $0 })
        let elapsed = Date().timeIntervalSince(start)
        print("demo 14 days: \(String(format: "%.1f", elapsed)) s")
        XCTAssertEqual(last, 1, accuracy: 0.001)
        XCTAssertTrue(DemoData.isActive(db))
        XCTAssertGreaterThanOrEqual(days.count, 13)
        let withRecovery = days.filter { $0.recovery != nil }
        XCTAssertGreaterThanOrEqual(withRecovery.count, 7, "recovery after the 4-night calibration")
        XCTAssertTrue(days.contains { $0.workoutCount > 0 })
        XCTAssertTrue(days.contains { ($0.sleepMinutes ?? 0) > 300 })
        // Recovery varies (good and bad nights), not a flat line.
        let rec = withRecovery.compactMap { $0.recovery }
        XCTAssertGreaterThan((rec.max() ?? 0) - (rec.min() ?? 0), 20)
        // The last two nights simulate getting ill: the monitor should flag it.
        if let lastDay = days.last {
            let a = HealthMonitor.assess(lastDay, history: days.filter { $0.day < lastDay.day })
            XCTAssertGreaterThanOrEqual(a.level, .watch, "signals: \(a.signals.map { $0.key })")
        }
        XCTAssertFalse(try db.allJournal().isEmpty)
        // Same seed → same data.
        let db2 = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-demo-\(UUID().uuidString).sqlite")
        let again = try DemoData.populate(db: db2, days: 14, now: now, calendar: cal)
        XCTAssertEqual(again.map { $0.recovery }, days.map { $0.recovery })
    }
}

extension DemoDataTests {
    /// Sanity of the numbers the demo produces (what the screenshots showed as off).
    func testDemoNumbersArePlausible() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-demo-\(UUID().uuidString).sqlite")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        let days = try DemoData.populate(db: db, days: 21, now: now, calendar: cal)
        for d in days {
            print(String(format: "DEMO %@ rec=%@ sleep=%.0f need=%.0f debt=%.0f strain=%.1f", d.day,
                         d.recovery.map { String(Int($0)) } ?? "-", d.sleepMinutes ?? -1, d.sleepNeedMinutes ?? -1,
                         d.sleepDebtMinutes ?? -1, d.strain ?? -1))
        }
        for d in days {
            if let need = d.sleepNeedMinutes { XCTAssertLessThan(need, 9 * 60, d.day) }
            if let debt = d.sleepDebtMinutes { XCTAssertLessThan(debt, 5 * 60, d.day) }
            if let r = d.recovery { XCTAssertGreaterThanOrEqual(r, 8, d.day) }
            if d.workoutCount == 0, let st = d.strain, d.wornMinutes > 600 { XCTAssertGreaterThan(st, 3, "rest day strain \(d.day)") }
        }
    }
}
