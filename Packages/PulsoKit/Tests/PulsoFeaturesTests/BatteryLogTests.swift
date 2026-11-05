import XCTest
@testable import PulsoFeatures

final class BatteryLogTests: XCTestCase {
    typealias P = BatteryLog.Point

    func testAppendSkipsRepeatsAndOldReadings() {
        var log: [P] = []
        log = BatteryLog.append(P(t: 0, pct: 80, live: false), to: log)
        log = BatteryLog.append(P(t: 60, pct: 80.2, live: false), to: log)
        XCTAssertEqual(log.count, 1, "under half a point and same stream: skipped")
        log = BatteryLog.append(P(t: 120, pct: 80.2, live: true), to: log)
        XCTAssertEqual(log.count, 2, "the stream switched")
        log = BatteryLog.append(P(t: 4000, pct: 80.2, live: true), to: log)
        XCTAssertEqual(log.count, 3, "an hour went by")
        log = BatteryLog.append(P(t: 4100, pct: 140, live: true), to: log)
        XCTAssertEqual(log.count, 3, "impossible level")
        log = BatteryLog.append(P(t: 4000 + BatteryLog.keep + 200, pct: 50, live: false), to: log)
        XCTAssertEqual(log.map(\.t), [4000 + BatteryLog.keep + 200])
    }

    func testDrainSinceLastChargeSplitsLiveAndIdle() throws {
        let h = 3600
        let log = [
            P(t: 0, pct: 40, live: false),
            P(t: 2 * h, pct: 38, live: false),
            P(t: 3 * h, pct: 100, live: false), // charged
            P(t: 13 * h, pct: 95, live: true), // 10 h idle: 0.5/h
            P(t: 17 * h, pct: 87, live: false), // 4 h live: 2/h
        ]
        let d = try XCTUnwrap(BatteryLog.drain(log))
        XCTAssertEqual(d.hours, 14, accuracy: 1e-9)
        XCTAssertEqual(d.perDay, 13.0 / 14 * 24, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.idleHourly), 0.5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(d.liveHourly), 2, accuracy: 1e-9)
        XCTAssertEqual(d.liveHours, 4, accuracy: 1e-9)
        XCTAssertEqual(d.daysPerCharge, 100 / d.perDay, accuracy: 1e-9)
    }

    func testDrainNeedsEnoughTime() {
        XCTAssertNil(BatteryLog.drain([P(t: 0, pct: 90, live: false), P(t: 3 * 3600, pct: 85, live: false)]))
        XCTAssertNil(BatteryLog.drain([P(t: 0, pct: 90, live: false), P(t: 10 * 3600, pct: 89, live: false)]))
        XCTAssertNil(BatteryLog.drain([]))
    }
}
