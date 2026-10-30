import XCTest
import PulsoStore
import PulsoAnalytics
@testable import PulsoIntelligence

final class IntelligenceTests: XCTestCase {
    struct LCG {
        var s: UInt64
        mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) }
        mutating func normal() -> Double { let u = max(next(), 1e-12), v = next(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
    }

    func day(_ i: Int) -> String { LoadResponse.shift("2026-08-01", i) }

    /// `n` normal nights with realistic noise and correlations (low HRV goes with higher RHR).
    func normalDays(_ n: Int, seed: UInt64 = 1) -> [DaySummary] {
        var r = LCG(s: seed)
        return (0..<n).map { i in
            var d = DaySummary(day: day(i))
            let common = r.normal()
            d.hrv = exp(log(65) + 0.12 * (-0.6 * common + 0.8 * r.normal()))
            d.rhr = 54 + 1.5 * (0.6 * common + 0.8 * r.normal())
            d.respRate = 14.5 + 0.3 * r.normal()
            d.skinTemp = 34.4 + 0.1 * r.normal()
            d.recovery = 60 + 12 * r.normal()
            d.strain = 10 + 2 * r.normal()
            d.sleepMinutes = 440 + 30 * r.normal()
            d.disturbances = Int(3 + 2 * r.next())
            return d
        }
    }

    // MARK: Toolkit

    func testStatisticsToolkit() {
        XCTAssertEqual(Num.chiSquareSurvival(4, k: 4), 0.40601, accuracy: 1e-4)
        XCTAssertEqual(Num.chiSquareSurvival(9.4877, k: 4), 0.05, accuracy: 1e-3)
        XCTAssertEqual(Num.chiSquareSurvival(0, k: 4), 1)
        XCTAssertEqual(Num.tCritical(df: 10, level: 0.9), 1.812, accuracy: 0.01)
        XCTAssertEqual(Num.tCritical(df: 30, level: 0.95), 2.042, accuracy: 0.01)
        let inv = Num.inverse([[4, 1], [1, 3]])!
        XCTAssertEqual(inv[0][0], 3.0 / 11, accuracy: 1e-9)
        XCTAssertEqual(inv[0][1], -1.0 / 11, accuracy: 1e-9)
        XCTAssertNil(Num.inverse([[1, 2], [2, 4]]))
        // OLS recovers an exact linear relation.
        let x = (0..<30).map { [Double($0), Double($0 % 7)] }
        let y = x.map { 3 + 2 * $0[0] - 1.5 * $0[1] }
        let fit = Num.ridge(x, y)!
        XCTAssertEqual(fit.beta[0], 3, accuracy: 1e-6)
        XCTAssertEqual(fit.beta[1], 2, accuracy: 1e-6)
        XCTAssertEqual(fit.beta[2], -1.5, accuracy: 1e-6)
    }

    // MARK: Deviation

    func testDeviationFlagsIllnessAndUnusualCombinations() {
        var days = normalDays(40)
        var sick = DaySummary(day: day(40))
        sick.hrv = 42; sick.rhr = 62; sick.respRate = 16; sick.skinTemp = 35.1
        days.append(sick)
        var series = Deviation.series(days)
        XCTAssertEqual(series.count, 41 - Deviation.minBaseline)
        let last = series.last!
        XCTAssertLessThan(last.coherence, 1)
        XCTAssertGreaterThan(last.strain, 2.5)
        XCTAssertTrue(last.contributors.first!.adverse)
        XCTAssertGreaterThan(last.debt, 1)
        let typical = series.dropLast().map { $0.coherence }
        XCTAssertGreaterThan(Num.median(typical)!, 30, "normal nights look normal")

        // Unusual *combination*: low VFC with low RHR (they normally move opposite) is flagged jointly,
        // but it isn't an adverse pattern for the debt (RHR low is good).
        days[40].hrv = 50; days[40].rhr = 51; days[40].respRate = 14.5; days[40].skinTemp = 34.4
        series = Deviation.series(days)
        XCTAssertLessThan(series.last!.coherence, 15)
        XCTAssertLessThan(series.last!.strain, last.strain)

        let m = Deviation.coherenceMetric(series)
        XCTAssertTrue(m.isAvailable)
        XCTAssertEqual(Deviation.coherenceMetric([]).status, .insufficient("\(Deviation.minBaseline) noches con VFC, FC en reposo, respiración y temperatura"))
    }

    func testDebtAccumulatesAndDecays() {
        var days = normalDays(30)
        for k in 0..<3 {
            var d = DaySummary(day: day(30 + k))
            d.hrv = 45; d.rhr = 60; d.respRate = 15.3; d.skinTemp = 34.7
            days.append(d)
        }
        days += normalDays(40, seed: 7).suffix(6).enumerated().map { i, d in var x = d; x.day = day(33 + i); return x }
        let s = Deviation.series(days)
        let debt = s.map { $0.debt }
        let peak = debt.enumerated().max { $0.element < $1.element }!
        XCTAssertGreaterThan(peak.element, 2)
        XCTAssertLessThan(debt.last!, peak.element * 0.3, "decays once nights are normal again")
    }

    // MARK: Load response

    func testLoadResponseMeasuresRecovery() {
        var days = normalDays(60, seed: 3)
        var workouts: [Workout] = []
        // Every 6 days a hard day; the next night is clearly off, the second slightly, the third normal.
        for i in stride(from: 20, to: 56, by: 6) {
            days[i].strain = 17
            days[i].cycleStart = 1_780_000_000 + i * 86400
            days[i].cycleEnd = days[i].cycleStart! + 50_000
            workouts.append(Workout(start: days[i].cycleStart! + 3600, end: days[i].cycleStart! + 7200, sport: "Carrera", source: .live, strain: 16))
            days[i + 1].hrv = 46; days[i + 1].rhr = 59; days[i + 1].respRate = 15.2
            days[i + 2].hrv = 58; days[i + 2].rhr = 56
        }
        for i in days.indices where days[i].strain ?? 0 >= 12 && days[i].strain != 17 { days[i].strain = 11 }
        let dev = Deviation.series(days)
        let events = LoadResponse.events(days: days, deviation: dev, workouts: workouts)
        let clean = events.filter { $0.sport == "Carrera" }
        XCTAssertGreaterThanOrEqual(clean.count, 5)
        for e in clean {
            XCTAssertNotNil(e.recoveryNights)
            XCTAssertGreaterThan(e.recoveryNights!, 0.9)
            XCTAssertLessThan(e.recoveryNights!, 3)
            XCTAssertGreaterThan(e.cost, 1)
            XCTAssertLessThan(e.hrvChangePct!, -15)
        }
        XCTAssertTrue(LoadResponse.velocityMetric(events).isAvailable)
        XCTAssertTrue(LoadResponse.efficiencyMetric(events).isAvailable)
        XCTAssertTrue(LoadResponse.consistencyMetric(events).isAvailable)
        let fp = LoadResponse.fingerprints(events)
        XCTAssertEqual(fp.first?.sport, "Carrera")
        XCTAssertEqual(fp.first?.intensity, "muy alta")
        if case .insufficient = LoadResponse.ceilingMetric(events).status {} else { XCTFail("ceiling needs 20 events") }
    }

    // MARK: Habits

    func testHabitImpactWithInterval() {
        var days = normalDays(50, seed: 5)
        var journal: [JournalEntry] = []
        for i in 0..<49 {
            // Balanced design: a quarter of both the meditation and the non-meditation days have alcohol,
            // so meditation is not confounded with it (an unbalanced pattern would show a spurious effect).
            journal.append(JournalEntry(day: days[i].day, key: "meditation", value: i % 8 < 4 ? 1 : 0))
            if i % 4 == 0 {
                journal.append(JournalEntry(day: days[i].day, key: "alcohol", value: 1))
                days[i + 1].recovery = (days[i + 1].recovery ?? 60) - 25
            }
        }
        let dev = Deviation.series(days)
        let items = HabitImpact.analyze(journal: journal, days: days, deviation: dev)
        let alcohol = items.first { $0.key == "alcohol" }!
        XCTAssertTrue(alcohol.isClear)
        XCTAssertLessThan(alcohol.interval.upperBound, 0)
        XCTAssertEqual(alcohol.recoveryDelta, -25, accuracy: 9)
        let med = items.first { $0.key == "meditation" }
        XCTAssertNotNil(med)
        XCTAssertFalse(med!.isClear, "no effect built in → interval spans zero")
        XCTAssertEqual(items.first?.key, "alcohol", "clear effects first")
    }

    // MARK: Predictor

    func testPredictorBeatsReferenceAndScenariosMoveTheRightWay() {
        var r = LCG(s: 11)
        var days: [DaySummary] = []
        var journal: [JournalEntry] = []
        var prev = 60.0
        for i in 0..<80 {
            var d = DaySummary(day: day(i))
            let sleep = 6 + 2.5 * r.next()
            let drank = i > 0 && r.next() < 0.2
            if drank { journal.append(JournalEntry(day: day(i - 1), key: "alcohol", value: 1)) }
            d.sleepMinutes = sleep * 60
            d.strain = 8 + 8 * r.next()
            d.recovery = Num.clamp(10 + 0.3 * prev + 7 * sleep - 18 * (drank ? 1 : 0) - 0.8 * (days.last?.strain ?? 10) + 4 * r.normal(), 1, 99)
            prev = d.recovery!
            d.hrv = 60; d.rhr = 55; d.respRate = 14.5; d.skinTemp = 34.4
            days.append(d)
        }
        let dev = Deviation.series(days)
        let rows = RecoveryModel.rows(days: days, deviation: dev, journal: journal)
        XCTAssertGreaterThan(rows.count, 70)
        let ev = RecoveryModel.evaluate(rows)!
        XCTAssertGreaterThan(ev.predictability, 0.2, "MAE \(ev.maeModel) vs ref \(ev.maeReference)")
        XCTAssertTrue(ev.predictions.allSatisfy { $0.day > rows[RecoveryModel.minTrain - 1].day }, "only future days are scored")
        let o = RecoveryModel.outlook(days: days, deviation: dev, journal: journal, today: days.last!.day)!
        let short = RecoveryModel.scenario(o, sleepHours: 5.5, alcohol: false, caffeine: false, lateMeal: false)
        let long = RecoveryModel.scenario(o, sleepHours: 8.5, alcohol: false, caffeine: false, lateMeal: false)
        let drunk = RecoveryModel.scenario(o, sleepHours: 8.5, alcohol: true, caffeine: false, lateMeal: false)
        XCTAssertGreaterThan(long.value, short.value + 10)
        XCTAssertLessThan(drunk.value, long.value - 8)
        XCTAssertTrue(long.interval.contains(long.value))
        XCTAssertTrue(RecoveryModel.forecastMetric(o).isAvailable)
        XCTAssertTrue(RecoveryModel.predictabilityMetric(o).isAvailable)
        XCTAssertTrue(RecoveryModel.surpriseMetric(o).isAvailable)
        XCTAssertNil(RecoveryModel.outlook(days: Array(days.prefix(10)), deviation: [], journal: [], today: days[9].day))
    }

    // MARK: Rhythms

    func session(start: Int, hours: Double) -> SleepSession {
        let n = Int(hours * 60)
        return SleepSession(start: start, end: start + n * 60, stages: [SleepStage](repeating: .light, count: n))
    }

    func testSleepRegularityIndex() {
        let base = 1_790_000_000 - 1_790_000_000 % 86400
        let regular = (0..<14).map { session(start: base + $0 * 86400 + 23 * 3600, hours: 8) }
        let now = base + 15 * 86400
        XCTAssertGreaterThan(Rhythms.sleepRegularityIndex(regular, now: now)!.sri, 95)
        var r = LCG(s: 4)
        let chaotic = (0..<14).map { session(start: base + $0 * 86400 + Int(19 * 3600 + r.next() * 8 * 3600), hours: 5 + 4 * r.next()) }
        XCTAssertLessThan(Rhythms.sleepRegularityIndex(chaotic, now: now)!.sri, 75)
        XCTAssertNil(Rhythms.sleepRegularityIndex(Array(regular.prefix(3)), now: now))
    }

    func testSleepEffectsRecoversAwakeningCost() {
        var r = LCG(s: 9)
        let base = 1_790_000_000
        let days: [DaySummary] = (0..<60).map { i in
            var d = DaySummary(day: day(i))
            let w = Int(r.next() * 8), h = 6 + 2.5 * r.next()
            let shift = r.next() * 2
            d.disturbances = w
            d.sleepMinutes = h * 60
            d.sleepStart = base + i * 86400 + Int((23 + shift) * 3600)
            // Recovery drops with distance from the usual bedtime (≈ 1 h shift here).
            d.recovery = 20 + 6 * h - 3 * Double(w) - 6 * abs(shift - 1) + 3 * r.normal()
            return d
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let m = Rhythms.sleepEffects(days: days, calendar: cal)
        let frag = m.first { $0.id == "fragmentationCost" }!
        XCTAssertEqual(frag.value!, -3, accuracy: 0.8)
        XCTAssertLessThan(frag.interval!.upperBound, 0)
        let timing = m.first { $0.id == "timingSensitivity" }!
        XCTAssertLessThan(timing.value!, 0)
    }

    func testImportedNightsCountForTimingButNotForAwakenings() {
        var r = LCG(s: 11)
        let base = 1_790_000_000
        // 120 imported nights (no awakenings, as in the WHOOP export) and 10 measured by Pulso.
        let days: [DaySummary] = (0..<130).map { i in
            var d = DaySummary(day: day(i))
            let h = 6 + 2.5 * r.next(), shift = r.next() * 2
            d.sleepMinutes = h * 60
            d.sleepStart = base + i * 86400 + Int((23 + shift) * 3600)
            d.recovery = 20 + 6 * h - 6 * abs(shift - 1) + 3 * r.normal()
            if i < 120 { d.source = "whoop" } else { d.disturbances = Int(r.next() * 8) }
            return d
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let m = Rhythms.sleepEffects(days: days, calendar: cal)
        let timing = m.first { $0.id == "timingSensitivity" }!
        XCTAssertEqual(timing.sampleSize, 130, "imported nights count")
        XCTAssertNotNil(timing.value)
        let frag = m.first { $0.id == "fragmentationCost" }!
        XCTAssertNil(frag.value)
        XCTAssertEqual(frag.unlock?.have, 10)
        XCTAssertEqual(frag.unlock?.need, 21)
    }

    // MARK: Workout

    func testWorkoutRecoveryCurveAndDrift() {
        let start = 1_790_000_000, end = start + 45 * 60
        var samples: [Sample] = []
        for t in start..<end {
            let k = Double(t - start) / Double(end - start)
            samples.append(Sample(ts: t, hr: Int(140 + 10 * k), rr: [], dyn: 0.9, steps: 1000 + (t - start) * 3 / 2))
        }
        // Exponential return to rest (55) with τ = 60 s from 150.
        for t in end..<(end + 1800) {
            let hr = 55 + 95 * exp(-Double(t - end) / 60)
            samples.append(Sample(ts: t, hr: Int(hr.rounded()), rr: [], dyn: 0.05, steps: 5000))
        }
        let w = Workout(start: start, end: end, sport: "Carrera", source: .live)
        let res = WorkoutAnalysis.analyze(workout: w, samples: samples, restingHR: 55, maxHR: 185)
        let rec = res.recovery!
        XCTAssertEqual(rec.endHR, 150, accuracy: 2)
        XCTAssertEqual(rec.drop60!, 95 * (1 - exp(-1)), accuracy: 6)
        XCTAssertEqual(rec.tau!, 60, accuracy: 12)
        XCTAssertNotNil(rec.minutesToBaseline)
        XCTAssertEqual(res.drift.percent!, 100 * (148.3 - 141.7) / 141.7, accuracy: 1.5)
        XCTAssertGreaterThan(res.reserve!.mean, 0.6)
        XCTAssertTrue(res.reserve!.approximate)

        // Changing intensity → drift not comparable.
        var interval = samples
        for i in interval.indices where interval[i].ts < end && (interval[i].ts - start) > 1800 { interval[i].steps = 1000 + (interval[i].ts - start) * 3 }
        let r2 = WorkoutAnalysis.analyze(workout: w, samples: interval, restingHR: 55, maxHR: 185)
        XCTAssertNil(r2.drift.percent)
    }

    // MARK: Whole report on demo data

    func testReportOnDemoData() throws {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Madrid")!
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-intel-\(UUID().uuidString).sqlite")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 21))!
        let days = try DemoData.populate(db: db, days: 30, now: now, calendar: cal)
        let sleeps = try db.sleeps(from: 0, to: Int(now.timeIntervalSince1970))
        let workouts = try db.workouts(from: 0, to: Int(now.timeIntervalSince1970))
        let report = Intelligence.report(days: days, sleeps: sleeps, workouts: workouts, journal: try db.allJournal(), now: now, calendar: cal)
        XCTAssertEqual(report.sections.count, 4)
        XCTAssertFalse(report.deviation.isEmpty)
        XCTAssertTrue(report.metric("coherence")?.isAvailable ?? false)
        XCTAssertTrue(report.metric("sri")?.isAvailable ?? false)
        XCTAssertTrue(report.metric("cardiacCost")?.isAvailable ?? false)
        // The demo ends with two "getting ill" nights: the deviation should notice.
        XCTAssertLessThan(report.deviation.last!.coherence, 30)
        for s in report.sections {
            for m in s.metrics {
                print("INTEL [\(s.title)] \(m.name): \(m.value.map { String(format: "%.1f", $0) } ?? "–") \(m.unit) · \(m.summary)")
                if m.isAvailable { XCTAssertFalse(m.summary.isEmpty) }
            }
        }
    }
}
