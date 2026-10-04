import XCTest
import WhoopProtocol
import PulsoStore
@testable import PulsoAnalytics

final class AnalyticsTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    func tempDB() throws -> PulsoDatabase {
        let path = NSTemporaryDirectory() + "pulso-test-\(UUID().uuidString).sqlite"
        return try PulsoDatabase(path: path)
    }

    func midnight(_ y: Int, _ m: Int, _ d: Int) -> Int {
        Int(calendar.date(from: DateComponents(year: y, month: m, day: d))!.timeIntervalSince1970)
    }

    func testHRVMath() {
        // Alternating 800/850 ms → every successive diff is 50 ms → RMSSD 50.
        let run: RRRun = (0..<100).map { $0 % 2 == 0 ? 800 : 850 }
        XCTAssertEqual(HRV.rmssd([run])!, 50, accuracy: 0.001)
        // An ectopic beat is removed and splits the run instead of creating a huge difference.
        var withEctopic = run
        withEctopic[50] = 400
        let cleaned = HRV.clean([withEctopic])
        XCTAssertEqual(HRV.rmssd(cleaned)!, 50, accuracy: 0.001)
        XCTAssertGreaterThan(cleaned.count, 1)
    }

    func testRRRunsBreakOnMissedBeatButNotOnEmptySeconds() {
        // 50 bpm: 1200 ms beats, so every sixth second carries no beat — that must NOT break the run.
        var samples: [Sample] = []
        var beat = 0.3
        for t in 0..<120 {
            var rr: [Int] = []
            while beat < Double(t + 1) {
                if beat >= Double(t) { rr.append(1200) }
                beat += 1.2
            }
            // Drop one beat report at t == 60 (a missed beat).
            if t == 60 { rr = [] }
            samples.append(Sample(ts: t, hr: 50, rr: rr))
        }
        let runs = Epochs.rrRuns(samples, from: 0, to: 120)
        XCTAssertEqual(runs.count, 2, "a missed beat splits the run exactly once")
        XCTAssertGreaterThan(runs[0].count, 40)
    }

    func testRespiratoryRateFromRSA() {
        var s = SyntheticStrap()
        var samples: [Sample] = []
        for t in 0..<900 {
            let h = s.second(t, .sleep(stage: 1, baseHR: 56, rsa: 0.07), respHz: 0.25)
            samples.append(Sample(ts: t, hr: h.heartRate.map { Int($0) }, rr: h.rr.map { Int($0) }))
        }
        let runs = HRV.clean(Epochs.rrRuns(samples, from: 0, to: 900))
        let rate = HRV.respiratoryRate(runs)
        XCTAssertNotNil(rate)
        XCTAssertEqual(rate ?? 0, 15, accuracy: 1.5)
    }

    func testStrainScale() {
        XCTAssertEqual(Strain.score(load: 0), 0)
        XCTAssertEqual(Strain.score(load: Strain.ceilingLoad), 21, accuracy: 0.001)
        let hour3 = Strain.score(load: 180)
        XCTAssertTrue((11...15).contains(hour3), "60 min at 70% HRR should be a solid workout, got \(hour3)")
        XCTAssertLessThan(Strain.score(load: 30), Strain.score(load: 180))
    }

    func testRecoveryRespondsToHRV() {
        var hist: [DaySummary] = []
        for i in 0..<14 {
            var d = DaySummary(day: String(format: "2026-01-%02d", i + 1))
            d.hrv = 60 + Double(i % 3) * 3
            d.rhr = 52 + Double(i % 2)
            d.respRate = 14.5
            d.skinTemp = 34.5
            hist.append(d)
        }
        let b = Baselines.from(history: hist)
        let good = Recovery.compute(hrv: 75, rhr: 50, resp: 14.4, skinTemp: 34.5, spo2: nil, sleepPerformance: 0.95, baselines: b)
        let bad = Recovery.compute(hrv: 40, rhr: 60, resp: 16.5, skinTemp: 35.5, spo2: nil, sleepPerformance: 0.6, baselines: b)
        XCTAssertGreaterThan(good.score!, 67)
        XCTAssertLessThan(bad.score!, 34)
        let cold = Recovery.compute(hrv: 60, rhr: 52, resp: nil, skinTemp: nil, spo2: nil, sleepPerformance: 0.9, baselines: Baselines())
        XCTAssertTrue(cold.calibrating)
        XCTAssertNil(cold.score)
    }

    func testFullPipelineOnSyntheticWeek() throws {
        let db = try tempDB()
        var p = Profile()
        p.birthYear = 1990
        p.rawRetentionDays = 0
        db.profile = p
        var strap = SyntheticStrap()
        let start = midnight(2026, 9, 1)
        var all: [HistorySample] = []
        for d in 0..<7 {
            // Night 5 is a rough one: lower HRV (smaller RSA) and higher resting HR.
            let rough = d == 5
            all += strap.day(startingAt: start + d * 86400, restingHR: rough ? 62 : 53, rsa: rough ? 0.025 : 0.065)
        }
        try db.insert(all)
        XCTAssertEqual(try db.sampleCount(), all.count)

        let engine = DayEngine(db: db, calendar: calendar)
        let now = Date(timeIntervalSince1970: TimeInterval(start + 7 * 86400 + 12 * 3600))
        let days = try engine.recompute(now: now)
        XCTAssertGreaterThanOrEqual(days.count, 6)

        // Every morning from the 2nd has a main sleep near 23:00 → 07:00.
        let mornings = days.filter { $0.sleepStart != nil }
        XCTAssertGreaterThanOrEqual(mornings.count, 6)
        for d in mornings {
            let onset = SleepCoach.minutesAfterMidnight(ts: d.sleepStart!, calendar: calendar)
            let wake = SleepCoach.minutesAfterMidnight(ts: d.sleepEnd!, calendar: calendar)
            XCTAssertLessThan(Stats.circularDistanceMinutes(onset, 23 * 60), 45, "onset \(onset) on \(d.day)")
            XCTAssertLessThan(Stats.circularDistanceMinutes(wake, 7 * 60), 30, "wake \(wake) on \(d.day)")
            XCTAssertNotNil(d.hrv)
            XCTAssertNotNil(d.rhr)
            XCTAssertGreaterThan(d.deepMinutes ?? 0, 20)
            XCTAssertGreaterThan(d.remMinutes ?? 0, 20)
            if let r = d.respRate { XCTAssertEqual(r, 14, accuracy: 2) }
            XCTAssertEqual(d.spo2 ?? 0, 96, accuracy: 0.5)
        }

        // Workouts are detected and strain lands in a sensible range.
        let dayWithRun = days.first { $0.day == DayKey.string(ts: start + 86400, calendar: calendar) }!
        XCTAssertGreaterThanOrEqual(dayWithRun.workoutCount, 1)
        XCTAssertTrue((8.0...19.0).contains(dayWithRun.strain ?? 0), "strain \(String(describing: dayWithRun.strain))")
        let workouts = try db.workouts(from: start, to: start + 8 * 86400)
        XCTAssertTrue(workouts.contains { $0.sport == "Carrera" && abs($0.durationMinutes - 45) < 8 })

        // Recovery kicks in after calibration and punishes the rough night.
        let roughDay = DayKey.string(ts: start + 6 * 86400, calendar: calendar)
        let scored = days.filter { $0.recovery != nil }
        XCTAssertFalse(scored.isEmpty)
        if let rough = days.first(where: { $0.day == roughDay })?.recovery {
            let others = scored.filter { $0.day != roughDay }.compactMap { $0.recovery }
            XCTAssertLessThan(rough, Stats.mean(others)! - 15, "rough night should score clearly lower")
        } else {
            XCTFail("rough day should have a recovery score")
        }

        // Exports work.
        let csv = Exporter.daysCSV(days)
        XCTAssertTrue(csv.hasPrefix("fecha,recuperacion"))
    }

    func testWhoopCSVImport() {
        let csv = """
        Cycle start time,Cycle end time,Cycle timezone,Recovery score %,Resting heart rate (bpm),Heart rate variability (ms),Skin temp (celsius),Blood oxygen %,Day Strain,Energy burned (cal),Max HR (bpm),Average HR (bpm),Sleep onset,Wake onset,Sleep performance %,Respiratory rate (rpm),Asleep duration (min),In bed duration (min)
        2026-08-01 23:10:00,2026-08-02 23:30:00,UTC+02:00,72,51,68,34.2,96.5,12.4,2400,171,68,2026-08-01 23:10:00,2026-08-02 07:05:00,91,14.2,430,470
        """
        let days = WhoopExportImporter.parse(csv: csv, calendar: calendar)
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].day, "2026-08-02")
        XCTAssertEqual(days[0].hrv, 68)
        XCTAssertEqual(days[0].rhr, 51)
        XCTAssertEqual(days[0].sleepPerformance ?? 0, 0.91, accuracy: 0.0001)
    }

    func testInsights() {
        var days: [DaySummary] = []
        var journal: [JournalEntry] = []
        for i in 1...20 {
            let key = String(format: "2026-03-%02d", i)
            var d = DaySummary(day: key)
            let drankYesterday = i > 1 && (i - 1) % 2 == 0
            d.recovery = drankYesterday ? 40 : 70
            d.hrv = drankYesterday ? 45 : 65
            days.append(d)
            journal.append(JournalEntry(day: key, key: "alcohol", value: i % 2 == 0 ? 1 : 0))
        }
        let ins = Insights.compute(journal: journal, days: days, calendar: calendar)
        let alcohol = ins.first { $0.key == "alcohol" }
        XCTAssertNotNil(alcohol)
        XCTAssertEqual(alcohol?.recoveryDelta ?? 0, -30, accuracy: 0.1)
    }
}
