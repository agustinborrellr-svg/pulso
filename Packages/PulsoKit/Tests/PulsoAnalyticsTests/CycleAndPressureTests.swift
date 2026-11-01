import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class CycleAndPressureTests: XCTestCase {
    var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func testCyclePhases() throws {
        let m = CyclePhases.map(starts: ["2026-04-08", "2026-03-11"], ovulations: ["2026-03-25"], averageLength: 28,
                                through: "2026-05-31", today: "2026-04-26", calendar: cal)
        XCTAssertEqual(m["2026-03-11"]?.phase, .menstrual)
        XCTAssertEqual(m["2026-03-11"]?.cycleDay, 1)
        XCTAssertEqual(m["2026-03-15"]?.phase, .menstrual)
        XCTAssertEqual(m["2026-03-16"]?.phase, .follicular)
        XCTAssertEqual(m["2026-03-25"]?.phase, .ovulatory, "detected ovulation")
        XCTAssertEqual(m["2026-03-27"]?.phase, .luteal)
        XCTAssertEqual(m["2026-04-07"]?.cycleDay, 28)
        // Second cycle: ovulation predicted 14 days before the next (predicted) start.
        XCTAssertEqual(m["2026-04-26"]?.cycleDay, 19)
        XCTAssertEqual(m["2026-04-26"]?.predicted, false)
        XCTAssertEqual(m["2026-05-06"]?.phase, .menstrual, "next period predicted 28 days later")
        XCTAssertEqual(m["2026-05-06"]?.predicted, true)
        XCTAssertNil(m["2026-03-01"], "nothing before the first known start")
        XCTAssertTrue(CyclePhases.map(starts: [], ovulations: [], averageLength: nil, through: "2026-05-01", today: "2026-05-01").isEmpty)
    }

    func testBloodPressure() {
        XCTAssertEqual(BloodPressure.category(systolic: 115, diastolic: 75), .normal)
        XCTAssertEqual(BloodPressure.category(systolic: 125, diastolic: 75), .elevated)
        XCTAssertEqual(BloodPressure.category(systolic: 118, diastolic: 84), .stage1)
        XCTAssertEqual(BloodPressure.category(systolic: 145, diastolic: 85), .stage2)
        XCTAssertEqual(BloodPressure.category(systolic: 190, diastolic: 100), .crisis)
        let t0 = 1_790_000_000
        let r = [BloodPressureReading(ts: t0, systolic: 118, diastolic: 78), BloodPressureReading(ts: t0 + 3600, systolic: 126, diastolic: 82),
                 BloodPressureReading(ts: t0 + 86400, systolic: 120, diastolic: 80)]
        let d = BloodPressure.daily(r, calendar: cal)
        XCTAssertEqual(d.count, 2)
        XCTAssertEqual(d[0].systolic, 118...126)
        XCTAssertEqual(d[0].count, 2)
        let avg = BloodPressure.average(r, days: 7, now: Date(timeIntervalSince1970: TimeInterval(t0 + 2 * 86400)))
        XCTAssertEqual(avg?.systolic, 121)
        XCTAssertEqual(avg?.diastolic, 80)
        XCTAssertNil(BloodPressure.average(r, days: 1, now: Date(timeIntervalSince1970: TimeInterval(t0 + 30 * 86400))))
    }

    func testPeriodAverages() {
        var pts: [(day: String, value: Double)] = []
        for d in 1...30 { pts.append((String(format: "2026-09-%02d", d), 60)) }
        for d in 1...31 { pts.append((String(format: "2026-10-%02d", d), 54)) }
        pts.append(("2026-11-01", 99)) // too few days: no segment
        let s = PeriodAverages.segments(pts, calendar: cal)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].mean, 60)
        XCTAssertNil(s[0].changePct)
        XCTAssertEqual(s[1].changePct!, -10, accuracy: 1e-9)
        XCTAssertEqual(s[1].start, "2026-10-01")
        XCTAssertEqual(s[1].end, "2026-10-31")
        let weekly = PeriodAverages.segments(pts, weeks: 1, calendar: cal)
        XCTAssertGreaterThan(weekly.count, 7)
    }
}

final class SleepFactorsTests: XCTestCase {
    func testLevels() {
        var d = DaySummary(day: "2026-11-01")
        d.sleepMinutes = 333
        d.sleepNeedMinutes = 546
        d.sleepConsistency = 24
        d.sleepEfficiency = 0.96
        d.deepMinutes = 70
        d.remMinutes = 90
        let f = SleepFactors.of(d)
        XCTAssertEqual(f.map(\.key), ["hoursVsNeed", "regularity", "efficiency", "restorative"])
        XCTAssertEqual(f[0].value, 61, accuracy: 0.5)
        XCTAssertEqual(f[0].level, .deficient)
        XCTAssertEqual(f[1].level, .deficient)
        XCTAssertEqual(f[2].level, .optimal)
        XCTAssertEqual(f[3].level, .optimal, "48 % restorative")
        XCTAssertTrue(SleepFactors.of(DaySummary(day: "2026-11-01")).isEmpty)
    }
}

final class HRVTrendTests: XCTestCase {
    func testRollingAverageAgainstSmallestWorthwhileChange() {
        var days: [DaySummary] = []
        for i in 0..<70 {
            var d = DaySummary(day: DayKey.shift("2026-08-01", days: i))
            // Stable around 60 ms with night-to-night noise, then a week well below.
            d.hrv = i < 63 ? 60 * exp(0.1 * sin(Double(i) * 1.7)) : 42
            days.append(d)
        }
        let s = HRVTrend.series(days)
        XCTAssertEqual(s.first { $0.day == DayKey.shift("2026-08-01", days: 40) }?.status, .within)
        let last = s.last!
        XCTAssertEqual(last.status, .below, "a week of low nights leaves the normal range")
        XCTAssertLessThan(last.rolling, last.low)
        XCTAssertTrue(s.allSatisfy { $0.low < $0.high })
        // One somewhat low night inside a normal week does not.
        var oneNight = Array(days.prefix(63))
        oneNight[62].hrv = 52
        XCTAssertNotEqual(HRVTrend.series(oneNight).last?.status, .below)
    }
}

final class RRCorrectionTests: XCTestCase {
    func sinus(_ n: Int) -> [Double] { (0..<n).map { 900 + 40 * sin(Double($0) / 3) } }

    func testCleanRhythmIsUntouched() {
        let rr = sinus(200)
        let r = RRCorrection.correct(rr)
        XCTAssertTrue(r.artifacts.isEmpty)
        XCTAssertEqual(r.rr, rr)
    }

    func testEctopicMissedAndExtraBeatsAreCorrected() {
        var rr = sinus(200)
        // Premature beat with compensatory pause.
        rr[50] = 560; rr[51] = 1240
        // Missed beat: two intervals detected as one.
        rr[100] = rr[100] + rr[101]; rr.remove(at: 101)
        // Extra beat: one interval split in two.
        let v = rr[150]; rr[150] = v * 0.35; rr.insert(v * 0.65, at: 151)
        let r = RRCorrection.correct(rr)
        let kinds = r.artifacts.map(\.kind)
        XCTAssertTrue(kinds.contains(.ectopic) || kinds.contains(.longShort), "\(r.artifacts.map { ($0.index, $0.kind) })")
        XCTAssertTrue(kinds.contains(.missed))
        XCTAssertTrue(kinds.contains(.extra))
        XCTAssertEqual(r.rr.count, 200, "missed beat split, extra beat merged")
        XCTAssertEqual(r.rr.reduce(0, +), rr.reduce(0, +), accuracy: 1e-6, "total time is kept")
        XCTAssertLessThan(r.rr.map { abs($0 - 900) }.max()!, 150, "no artefact left")
        // RMSSD after correction is close to the clean signal's.
        let clean = HRV.rmssd([sinus(200)])!, fixed = HRV.rmssd([r.rr])!
        XCTAssertEqual(fixed, clean, accuracy: clean * 0.25)
    }
}

final class FitnessFormulaTests: XCTestCase {
    /// ACSM running equation + %HRR = %VO₂R (Swain & Leutholtz 1997).
    func testVO2maxFromRun() throws {
        // 10 km in 50 min (200 m/min): VO₂ = 0.2·200 + 3.5 = 43.5. At 75 % of HRR: 3.5 + 40 / 0.75 = 56.83.
        let rest = 50.0, max = 190.0, avg = rest + 0.75 * (max - rest)
        let v = try XCTUnwrap(Fitness.vo2maxFromRun(distanceMeters: 10_000, seconds: 3000, avgHR: avg, restingHR: rest, maxHR: max))
        XCTAssertEqual(v, 3.5 + 40 / 0.75, accuracy: 1e-9)
        XCTAssertNil(Fitness.vo2maxFromRun(distanceMeters: 2_000, seconds: 1800, avgHR: avg, restingHR: rest, maxHR: max), "walking pace: equation not valid")
        XCTAssertNil(Fitness.vo2maxFromRun(distanceMeters: 3_000, seconds: 600, avgHR: avg, restingHR: rest, maxHR: max), "under 12 min")
        XCTAssertNil(Fitness.vo2maxFromRun(distanceMeters: 10_000, seconds: 3000, avgHR: 80, restingHR: rest, maxHR: max), "too easy to extrapolate")
        let runs: [(ts: Int, vo2: Double)] = [(100, 50), (200, 52), (300, 60), (400, 51)]
        XCTAssertEqual(Fitness.vo2maxFromRuns(runs, through: 500), 51.5, "median of the last 90 days")
        XCTAssertNil(Fitness.vo2maxFromRuns(Array(runs.prefix(2)), through: 500))
    }

    func testRunningVO2ReplacesRestingEstimate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var p = Profile()
        p.birthYear = Calendar.current.component(.year, from: Date()) - 30
        p.maxHROverride = 190
        var days: [DaySummary] = []
        var ws: [Workout] = []
        for i in 0..<40 {
            var d = DaySummary(day: DayKey.shift("2026-09-01", days: i, calendar: cal))
            d.rhr = 50
            d.vo2max = 58 // resting-HR estimate
            days.append(d)
            if i % 7 == 0 {
                let ts = Int(DayKey.date(d.day, calendar: cal)!.timeIntervalSince1970) + 8 * 3600
                var w = Workout(start: ts, end: ts + 3000, sport: "Carrera", source: .strava, avgHR: 155)
                w.distanceMeters = 10_000
                ws.append(w)
            }
        }
        let merged = HistoryMerge.days(measured: days, imported: [], profile: p, workouts: ws, calendar: cal)
        let expected = 3.5 + 40 / ((155.0 - 50) / 140)
        XCTAssertEqual(merged.last!.vo2max!, (expected * 10).rounded() / 10, accuracy: 1e-9)
        XCTAssertEqual(merged.first!.vo2max, 58, "before three runs, the resting estimate stays")
    }

    /// Keytel 2005 with VO₂max (male): (−95.7735 + 0.634·HR + 0.404·VO₂ + 0.394·W + 0.271·A) / 4.184.
    func testKeytelWithVO2max() {
        var p = Profile()
        p.birthYear = Calendar.current.component(.year, from: Date()) - 30
        p.weightKg = 75
        p.sex = .male
        let k = Calories.keytelPerMinute(hr: 150, p, vo2max: 50)
        let withVO2: Double = (-95.7735 + 95.1 + 20.2 + 29.55 + 8.13) / 4.184
        XCTAssertEqual(k, withVO2, accuracy: 1e-9)
        let plain: Double = (-55.0969 + 94.635 + 14.91 + 6.051) / 4.184
        XCTAssertEqual(Calories.keytelPerMinute(hr: 150, p), plain, accuracy: 1e-9)
    }
}
