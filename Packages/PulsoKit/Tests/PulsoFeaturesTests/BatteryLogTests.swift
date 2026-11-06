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

    func testDrainFindsAChargeSeenInSmallSteps() throws {
        let h = 3600
        // Discharging, then charged in 0.5-point readings (no 2-point jump between neighbours), then discharging.
        var log = [P(t: 0, pct: 45, live: false), P(t: 5 * h, pct: 40, live: false)]
        var t = 5 * h
        for i in 1...120 {
            t += 60
            log.append(P(t: t, pct: 40 + Double(i) * 0.5, live: false))
        }
        let peak = t
        log.append(P(t: peak + 2 * h, pct: 100, live: false)) // still full after unplugging: part of the run
        log.append(P(t: peak + 10 * h, pct: 96, live: false))
        log.append(P(t: peak + 20 * h, pct: 91, live: false))
        let d = try XCTUnwrap(BatteryLog.drain(log))
        XCTAssertEqual(d.hours, 20, accuracy: 1e-9, "the run starts at the first 100 % reading")
        XCTAssertEqual(d.perDay, 9.0 / 20 * 24, accuracy: 1e-9)
    }

    func testSmallWobblesAreNotCharges() throws {
        let h = 3600
        let log = [
            P(t: 0, pct: 80, live: false),
            P(t: 4 * h, pct: 78, live: false),
            P(t: 5 * h, pct: 78.5, live: false), // rounding wobble, under the charge threshold
            P(t: 6 * h, pct: 79, live: false),
            P(t: 10 * h, pct: 75, live: false),
        ]
        let d = try XCTUnwrap(BatteryLog.drain(log))
        XCTAssertEqual(d.hours, 10, accuracy: 1e-9)
    }

    func testDrainNeedsEnoughTime() {
        XCTAssertNil(BatteryLog.drain([P(t: 0, pct: 90, live: false), P(t: 3 * 3600, pct: 85, live: false)]))
        XCTAssertNil(BatteryLog.drain([P(t: 0, pct: 90, live: false), P(t: 10 * 3600, pct: 89, live: false)]))
        XCTAssertNil(BatteryLog.drain([]))
    }
}
