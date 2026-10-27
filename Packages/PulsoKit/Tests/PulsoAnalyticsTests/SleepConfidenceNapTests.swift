import XCTest
import PulsoStore
import WhoopProtocol
@testable import PulsoAnalytics

final class SleepConfidenceNapTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Int {
        Int(cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!.timeIntervalSince1970)
    }

    /// Demo history up to the evening of the 25th, then a night 23:30–07:30 and a day on the 26th with
    /// optional daytime sleep, viewed at 22:00.
    func scenario(daySleep: ClosedRange<Int>?, poorNight: Bool = false, decision: SleepDecision.Kind? = nil) throws -> (PulsoDatabase, [DaySummary]) {
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-naps-\(UUID().uuidString).sqlite")
        let evening = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 20))!
        _ = try DemoData.populate(db: db, days: 10, now: evening, calendar: cal, keepRawDays: nil)
        var strap = DemoData.Strap(rng: DemoData.RNG(state: 21))
        var out: [HistorySample] = []
        let bed = at(25, 23, 30), wake = at(26, 7, 30)
        for t in Int(evening.timeIntervalSince1970)..<at(26, 22) {
            if t >= bed && t < wake {
                let minute = (t - bed) / 60, pos = minute % 90
                let stage = minute < 10 ? 0 : (pos < 20 && minute < 270 ? 2 : (pos >= 70 ? 3 : 1))
                var s = stage == 0 ? strap.second(t, .awake(hr: 62, motion: 0.03))
                                   : strap.second(t, .sleep(stage: stage, baseHR: 52, rsa: 0.065, temp: 34.5))
                // A loose strap: 30 % of the minutes without a reading.
                if poorNight && minute % 10 < 3 && minute > 15 { s = HistorySample(unix: UInt32(t), recordIndex: UInt32(t), signalPoor: true, offWrist: true) }
                out.append(s)
            } else if let d = daySleep, d.contains(t) {
                let minute = (t - d.lowerBound) / 60
                out.append(minute < 6 ? strap.second(t, .awake(hr: 64, motion: 0.03))
                                      : strap.second(t, .sleep(stage: minute % 90 < 25 ? 2 : 1, baseHR: 54, rsa: 0.06, temp: 34.4)))
            } else {
                out.append(strap.second(t, .awake(hr: 76, motion: 0.12)))
            }
        }
        try db.insert(out)
        if let decision, let d = daySleep {
            try db.saveSleepDecision(SleepDecision(start: d.lowerBound, end: d.upperBound, kind: decision))
        }
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 22))!
        let days = try DayEngine(db: db, calendar: cal).recompute(fromDay: "2026-10-24", now: now)
        return (db, days)
    }

    func testNightHasConfidenceWithReasons() throws {
        let (db, days) = try scenario(daySleep: nil)
        let d = try XCTUnwrap(days.first { $0.day == "2026-10-26" })
        let s = try XCTUnwrap(db.sleep(id: try XCTUnwrap(d.sleepId)))
        let c = try XCTUnwrap(s.stageConfidence)
        print("CONF clean night: \(c.level) \(c.score) \(c.reasons)")
        XCTAssertGreaterThan(c.coverage, 0.9)
        XCTAssertNotEqual(c.level, .low)
        if c.level != .high { XCTAssertFalse(c.reasons.isEmpty, "anything below high says why") }

        let (db2, days2) = try scenario(daySleep: nil, poorNight: true)
        let d2 = try XCTUnwrap(days2.first { $0.day == "2026-10-26" })
        let s2 = try XCTUnwrap(try db2.sleep(id: try XCTUnwrap(d2.sleepId, "the night is still detected")))
        let c2 = try XCTUnwrap(s2.stageConfidence)
        print("CONF poor night: \(c2.level) \(c2.score) \(c2.reasons)")
        XCTAssertLessThan(c2.score, c.score)
        XCTAssertNotEqual(c2.level, .high)
        XCTAssertTrue(c2.reasons.contains { $0.contains("no leyó bien") })
    }

    func testShortDaytimeSleepIsANapAndLowersTomorrowsNeed() throws {
        let nap = at(26, 15)...at(26, 15, 45)
        let (db, days) = try scenario(daySleep: nap)
        let d = try XCTUnwrap(days.first { $0.day == "2026-10-26" })
        let naps = try db.sleeps(from: at(26, 10), to: at(26, 23)).filter { $0.isNap }
        XCTAssertEqual(naps.count, 1)
        XCTAssertFalse(naps[0].kindConfirmed, "not asked yet")
        XCTAssertGreaterThan(d.napMinutes ?? 0, 20)
        let noNap = try scenario(daySleep: nil).1.first { $0.day == "2026-10-26" }
        XCTAssertEqual(d.sleepMinutes ?? 0, noNap?.sleepMinutes ?? -1, accuracy: 1, "a nap doesn't add to the night")
    }

    func testLongDaytimeSleepCountsAsSleep() throws {
        let long = at(26, 14)...at(26, 17, 30)
        let (db, days) = try scenario(daySleep: long)
        let d = try XCTUnwrap(days.first { $0.day == "2026-10-26" })
        let base = try XCTUnwrap(try scenario(daySleep: nil).1.first { $0.day == "2026-10-26" })
        XCTAssertGreaterThan((d.sleepMinutes ?? 0) - (base.sleepMinutes ?? 0), 150, "3.5 h of daytime sleep adds to sleep")
        XCTAssertNil(d.napMinutes)
        XCTAssertTrue(try db.sleeps(from: at(26, 10), to: at(26, 23)).contains { !$0.isNap && $0.start >= at(26, 13) })
    }

    func testTheUsersAnswerWins() throws {
        // A 3.5 h daytime sleep the user calls a nap…
        let long = at(26, 14)...at(26, 17, 30)
        let (db, days) = try scenario(daySleep: long, decision: .nap)
        let d = try XCTUnwrap(days.first { $0.day == "2026-10-26" })
        XCTAssertGreaterThan(d.napMinutes ?? 0, 150)
        let nap = try XCTUnwrap(try db.sleeps(from: at(26, 10), to: at(26, 23)).first { $0.isNap })
        XCTAssertTrue(nap.kindConfirmed)
        // …and a 45-minute one the user calls sleep.
        let short = at(26, 15)...at(26, 15, 45)
        let (_, days2) = try scenario(daySleep: short, decision: .sleep)
        let d2 = try XCTUnwrap(days2.first { $0.day == "2026-10-26" })
        XCTAssertNil(d2.napMinutes)
        let base = try XCTUnwrap(try scenario(daySleep: nil).1.first { $0.day == "2026-10-26" })
        XCTAssertGreaterThan((d2.sleepMinutes ?? 0) - (base.sleepMinutes ?? 0), 25)
    }

    func testDecisionsMatchByOverlap() throws {
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-dec-\(UUID().uuidString).sqlite")
        try db.saveSleepDecision(SleepDecision(start: 1000, end: 4600, kind: .sleep))
        XCTAssertEqual(db.sleepDecision(start: 1200, end: 4400)?.kind, .sleep, "edges moved a little on recompute")
        XCTAssertNil(db.sleepDecision(start: 5000, end: 6000))
        try db.saveSleepDecision(SleepDecision(start: 1100, end: 4500, kind: .nap))
        XCTAssertEqual(db.sleepDecisions().count, 1, "a new answer replaces the old one")
        XCTAssertEqual(db.sleepDecision(start: 1000, end: 4600)?.kind, .nap)
    }
}
