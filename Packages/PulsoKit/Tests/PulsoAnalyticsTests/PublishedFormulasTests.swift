import XCTest
import PulsoStore
@testable import PulsoAnalytics

/// The formulas that follow published sources exactly.
final class PublishedFormulasTests: XCTestCase {
    /// Sleep-need strain term (patent US12318226B2): the API example's strain 5.2951527 gives 208 595 ms.
    func testStrainSleepNeedMatchesTheAPIExample() {
        XCTAssertEqual(SleepCoach.strainMinutes(5.2951527) * 60_000, 208_595, accuracy: 1)
        XCTAssertEqual(SleepCoach.strainMinutes(21), 60 * 1.7 / (1 + exp(-4 / 3.5)), accuracy: 1e-9)
        XCTAssertEqual(SleepCoach.strainMinutes(nil), 0)
        let base = SleepCoach.need(baseHours: 8, previousStrain: 17, debtMinutes: 0, napMinutes: 0)
        XCTAssertEqual(base, 480 + 51, accuracy: 0.5, "strain 17 adds 51 min")
        XCTAssertEqual(SleepCoach.need(baseHours: 8, previousStrain: 17, debtMinutes: 0, napMinutes: 30), base - 30, accuracy: 1e-9)
        XCTAssertEqual(SleepCoach.need(baseHours: 8, previousStrain: 17, debtMinutes: 40, napMinutes: 0), base + 40, accuracy: 1e-9)
    }

    /// Zones by heart-rate reserve with zone 1 at 40–60 % (Healthspan white paper).
    func testZonesFollowTheWhitePaper() {
        let m = HeartRateModel(restingHR: 50, maxHR: 190)
        XCTAssertEqual(m.zone(50 + 0.39 * 140), 0)
        XCTAssertEqual(m.zone(50 + 0.45 * 140), 1)
        XCTAssertEqual(m.zone(50 + 0.59 * 140), 1)
        XCTAssertEqual(m.zone(50 + 0.65 * 140), 2)
        XCTAssertEqual(m.zone(50 + 0.75 * 140), 3)
        XCTAssertEqual(m.zone(50 + 0.85 * 140), 4)
        XCTAssertEqual(m.zone(50 + 0.95 * 140), 5)
        XCTAssertEqual(m.zone(195), 5)
        XCTAssertEqual(m.zoneFloor(1), 50 + 0.4 * 140, accuracy: 1e-9)
        XCTAssertEqual(m.zoneFloor(2), 50 + 0.6 * 140, accuracy: 1e-9)
        XCTAssertEqual(m.zoneFloor(5), 50 + 0.9 * 140, accuracy: 1e-9)
    }

    func night(_ dayOffset: Int, from h0: Double, to h1: Double, base: Int, wakeAt: [Int] = []) -> SleepSession {
        let start = base + dayOffset * 86400 + Int(h0 * 3600), end = base + dayOffset * 86400 + Int(h1 * 3600)
        var stages = [SleepStage](repeating: .light, count: (end - start) / 60)
        for i in wakeAt where i < stages.count { stages[i] = .awake }
        return SleepSession(start: start, end: end, isNap: false, manual: false, stages: stages)
    }

    /// Sleep consistency: identical schedules score 100, a shifted one less, too little history nothing.
    func testConsistencyIsStateMatchingAtClockTime() {
        let base = 1_790_000_000 - 1_790_000_000 % 86400
        let same = (-4...0).map { night($0, from: -1, to: 7, base: base) }
        XCTAssertEqual(SleepCoach.consistency(sessions: same, wake: same.last!.end) ?? 0, 100, accuracy: 0.01)
        var shifted = same
        shifted[3] = night(-1, from: 1, to: 9, base: base)
        let s = SleepCoach.consistency(sessions: shifted, wake: shifted.last!.end)!
        // Today's 24 h vs each of the 4 days before: the shifted night's 7–9 h tail falls in today's window and differs
        // from all four (2 h each), and against yesterday the −1–1 h start differs too (2 h): 10 of 96 h.
        XCTAssertEqual(s, 200 * (1 - 10.0 / 96) - 100, accuracy: 0.5)
        XCTAssertNil(SleepCoach.consistency(sessions: Array(same.suffix(2)), wake: same.last!.end), "needs two previous days")
        // Waking inside the night counts as awake, as WHOOP does.
        var restless = same
        restless[4] = night(0, from: -1, to: 7, base: base, wakeAt: Array(0..<60))
        XCTAssertLessThan(SleepCoach.consistency(sessions: restless, wake: restless.last!.end)!, 100)
    }

    func testWeightedMedianAndRegression() {
        XCTAssertEqual(Stats.weightedMedian([(1, 1), (2, 1), (10, 5)]), 10)
        XCTAssertEqual(Stats.weightedMedian([(1, 3), (2, 1), (10, 1)]), 1)
        XCTAssertNil(Stats.weightedMedian([]))
        // y = 2 + 3a − b exactly.
        let x: [[Double]] = [[1, 0, 0], [1, 1, 0], [1, 0, 1], [1, 1, 1], [1, 2, 3]]
        let y = x.map { 2 + 3 * $0[1] - $0[2] }
        let b = Stats.ols(x, y)!
        XCTAssertEqual(b[0], 2, accuracy: 1e-9)
        XCTAssertEqual(b[1], 3, accuracy: 1e-9)
        XCTAssertEqual(b[2], -1, accuracy: 1e-9)
        XCTAssertNil(Stats.ols([[1, 1], [1, 1], [1, 1]], [1, 2, 3]), "collinear")
    }

    /// The baseline centre leans on recent nights.
    func testBaselineWeighsRecentNights() {
        let b = Baseline.from(Array(repeating: 50.0, count: 14) + Array(repeating: 60.0, count: 14), floor: 1)!
        XCTAssertEqual(b.center, 60, "the last 14 nights carry more than half the weight")
        XCTAssertEqual(b.count, 28)
    }

    /// Fitted to the user's WHOOP export (see SleepCoach): debt carry-over and the 2025 sleep-score blend.
    func testDebtAndSleepScoreFits() {
        XCTAssertEqual(SleepCoach.debt(previousDebt: 100, previousShortfall: 0), 70.3, accuracy: 1e-9)
        XCTAssertEqual(SleepCoach.debt(previousDebt: 100, previousShortfall: 60), 70.3 + 0.289 * 60, accuracy: 1e-9)
        XCTAssertEqual(SleepCoach.debt(previousDebt: 30, previousShortfall: -60), 0, "a long night pays it back")
        XCTAssertEqual(SleepCoach.debt(previousDebt: 180, previousShortfall: 600), SleepCoach.maxDebt)
        XCTAssertEqual(SleepCoach.performance(sufficiency: 0.8, consistency: 60, efficiency: 0.9), (-28.5 + 69.12 + 21.42 + 17.73) / 100, accuracy: 1e-9)
        XCTAssertEqual(SleepCoach.performance(sufficiency: 1, consistency: 90, efficiency: 0.95), 1, "capped at 100 %")
        XCTAssertEqual(SleepCoach.performance(sufficiency: 0.7, consistency: nil, efficiency: 0.9), 0.7)
    }

    /// Recovery = 100·σ(−2.166 + 0.504·zHRV − 0.049·zRHR + 4.096·sufficiency), fitted to the user's WHOOP export.
    func testRecoveryFollowsTheFittedModel() {
        let b = Baselines(lnHRV: Baseline(center: log(60), spread: 0.15, count: 20), rhr: Baseline(center: 52, spread: 2, count: 20))
        let at = Recovery.compute(hrv: 60, rhr: 52, resp: nil, skinTemp: nil, spo2: nil, sleepSufficiency: 0.85, baselines: b)
        XCTAssertEqual(at.score!, (100 / (1 + exp(-(-2.166 + 4.096 * 0.85)))).rounded())
        XCTAssertEqual(at.score!, RecoveryWaterfall.neutral.rounded(), "a night at your baselines is the waterfall's neutral")
        let good = Recovery.compute(hrv: 60 * exp(0.15), rhr: 50, resp: nil, skinTemp: nil, spo2: nil, sleepSufficiency: 1, baselines: b)
        XCTAssertEqual(good.score!, (100 / (1 + exp(-(-2.166 + 0.504 - 0.049 * -1 + 4.096)))).rounded())
        XCTAssertEqual(good.contributors.reduce(0) { $0 + $1.impact }, 0.504 + 0.049 + 4.096 * 0.15, accuracy: 1e-9)
    }

    func testPlannerGoals() {
        let wake = Date(timeIntervalSince1970: 1_790_000_000)
        let peak = SleepPlanner.plan(wake: wake, needMinutes: 480, recent: [], goal: .peak)
        let getBy = SleepPlanner.plan(wake: wake, needMinutes: 480, recent: [], goal: .getBy)
        XCTAssertEqual(peak.inBedMinutes, 480 / 0.9 + 15, accuracy: 1e-9)
        XCTAssertEqual(getBy.inBedMinutes, 480 * 0.75 / 0.9 + 15, accuracy: 1e-9)
    }
}
