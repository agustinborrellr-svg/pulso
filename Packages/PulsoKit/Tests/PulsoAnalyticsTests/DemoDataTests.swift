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
