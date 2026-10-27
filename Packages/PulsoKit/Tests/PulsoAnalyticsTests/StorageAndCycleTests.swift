import XCTest
import PulsoStore
import WhoopProtocol
@testable import PulsoAnalytics

final class StorageAndCycleTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    func path() -> String { NSTemporaryDirectory() + "pulso-store-\(UUID().uuidString).sqlite" }

    // MARK: Schema

    func testOldDatabaseIsMigratedWithoutLosingData() throws {
        let p = path()
        // A database as version 0 left it: tables, no user_version.
        do {
            let db = try PulsoDatabase(path: p)
            try db.sql.execute("PRAGMA user_version = 0;")
            var d = DaySummary(day: "2026-10-20")
            d.recovery = 61
            try db.save(d)
            try db.setJournal(day: "2026-10-20", key: "alcohol", value: 1)
        }
        let db = try PulsoDatabase(path: p)
        XCTAssertEqual(db.diskSchemaVersion, PulsoDatabase.schemaVersion)
        XCTAssertEqual(try db.sql.scalarInt("PRAGMA user_version;").map(Int.init), PulsoDatabase.schemaVersion)
        XCTAssertEqual(try db.allDays().first?.recovery, 61)
        XCTAssertEqual(try db.journal(day: "2026-10-20")["alcohol"], 1)
        // Opening again changes nothing.
        let again = try PulsoDatabase(path: p)
        XCTAssertEqual(try again.allDays().count, 1)
    }

    // MARK: Tolerant decoding

    func testRowsFromOlderVersionsStillDecode() throws {
        // A day as an early version wrote it: most of today's fields missing.
        let oldDay = #"{"day":"2026-09-01","recovery":55,"hrv":70}"#
        let d = try JSONDecoder().decode(DaySummary.self, from: Data(oldDay.utf8))
        XCTAssertEqual(d.day, "2026-09-01")
        XCTAssertEqual(d.recovery, 55)
        XCTAssertEqual(d.zoneMinutes, [0, 0, 0, 0, 0])
        XCTAssertEqual(d.source, "strap")
        XCTAssertTrue(d.stressHourly.isEmpty)

        let oldSleep = #"{"start":100,"end":4000,"stages":[1,2]}"#
        let s = try JSONDecoder().decode(SleepSession.self, from: Data(oldSleep.utf8))
        XCTAssertEqual(s.end, 4000)
        XCTAssertEqual(s.stages.count, 2)
        XCTAssertFalse(s.isNap)

        // A workout whose source a newer version invented is still shown.
        let future = #"{"start":10,"end":70,"sport":"Remo","source":"garmin_direct"}"#
        let w = try JSONDecoder().decode(Workout.self, from: Data(future.utf8))
        XCTAssertEqual(w.sport, "Remo")
        XCTAssertEqual(w.source, .manual)

        // And everything round-trips with all fields.
        var full = DaySummary(day: "2026-10-26")
        full.stressHourly = [nil, 1.2]
        full.zoneMinutes = [1, 2, 3, 4, 5]
        XCTAssertEqual(try JSONDecoder().decode(DaySummary.self, from: JSONEncoder().encode(full)), full)
    }

    // MARK: The cycle after midnight

    func testHoursAfterMidnightBelongToYesterdayUntilYouSleep() throws {
        let db = try PulsoDatabase(path: path())
        func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))! }
        let evening = at(25, 20)
        _ = try DemoData.populate(db: db, days: 10, now: evening, calendar: cal, keepRawDays: nil)
        let engine = DayEngine(db: db, calendar: cal)
        let strainAtEight = try XCTUnwrap(try db.days(from: "2026-10-25", to: "2026-10-25").first?.strain)

        // A late night out: awake and moving from 20:00 to 00:30.
        var strap = DemoData.Strap(rng: DemoData.RNG(state: 9))
        var extra: [HistorySample] = []
        for t in Int(evening.timeIntervalSince1970)..<Int(at(26, 0, 30).timeIntervalSince1970) {
            extra.append(strap.second(t, .awake(hr: 112, motion: 0.25)))
        }
        try db.insert(extra)
        let late = at(26, 0, 30)
        var days = try engine.recompute(fromDay: "2026-10-24", now: late)
        XCTAssertNil(days.first { $0.day == "2026-10-26" }, "today has no cycle before sleeping")
        XCTAssertNil(try db.days(from: "2026-10-26", to: "2026-10-26").first)
        let open = try XCTUnwrap(days.first { $0.day == "2026-10-25" })
        XCTAssertEqual(open.cycleEnd, Int(late.timeIntervalSince1970), "yesterday's cycle is still open")
        XCTAssertGreaterThan(open.strain ?? 0, strainAtEight, "the hours after midnight count in yesterday's strain")

        // Then sleep from 01:00 to 08:30 and get up.
        extra.removeAll()
        var t = Int(late.timeIntervalSince1970)
        let bed = Int(at(26, 1).timeIntervalSince1970), wake = Int(at(26, 8, 30).timeIntervalSince1970), now = Int(at(26, 10).timeIntervalSince1970)
        while t < now {
            if t >= bed && t < wake {
                let minute = (t - bed) / 60, pos = minute % 90
                let stage = minute < 10 ? 0 : (pos < 20 && minute < 270 ? 2 : (pos >= 70 ? 3 : 1))
                extra.append(stage == 0 ? strap.second(t, .awake(hr: 62, motion: 0.03))
                                        : strap.second(t, .sleep(stage: stage, baseHR: 52, rsa: 0.065, temp: 34.5)))
            } else {
                extra.append(strap.second(t, .awake(hr: 75, motion: 0.12)))
            }
            t += 1
        }
        try db.insert(extra)
        days = try engine.recompute(fromDay: "2026-10-24", now: at(26, 10))
        let today = try XCTUnwrap(days.first { $0.day == "2026-10-26" }, "after waking up the new day exists")
        let closed = try XCTUnwrap(days.first { $0.day == "2026-10-25" })
        let sleepStart = try XCTUnwrap(today.sleepStart)
        XCTAssertLessThan(abs(sleepStart - bed), 30 * 60)
        XCTAssertEqual(closed.cycleEnd, sleepStart, "yesterday ends when you fall asleep")
        XCTAssertEqual(today.cycleStart, today.sleepEnd, "today starts when you wake up")
        // No second of the day is counted in both cycles.
        XCTAssertLessThanOrEqual(closed.cycleEnd ?? 0, today.cycleStart ?? 0)
    }
}
