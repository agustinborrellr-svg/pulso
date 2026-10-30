import XCTest
@testable import PulsoAnalytics

final class LiveSessionTests: XCTestCase {
    func steady(from t0: Double, seconds: Double, rr: Double, amp: Double = 30, breaths: Double = 6) -> [LiveMetrics.Beat] {
        var out: [LiveMetrics.Beat] = []
        var t = t0
        while t < t0 + seconds {
            let v = rr + amp * sin(2 * .pi * breaths / 60 * (t - t0)) + (out.count % 2 == 0 ? 6 : -6)
            t += v / 1000
            out.append(.init(t: t, rr: v))
        }
        return out
    }

    func testHistoryBinsKeepGapsAndStats() {
        let samples = (0..<600).map { (ts: 3_600 + $0, hr: 60 + $0 % 10) } + (1_800..<1_860).map { (ts: 3_600 + $0, hr: 100) }
        let bins = HRHistory.bin(samples, width: 60)
        XCTAssertEqual(bins.count, 11)
        let s = HRHistory.series(bins, from: 3_600, to: 3_600 + 3_600, width: 60)
        XCTAssertEqual(s.points.count, 11)
        XCTAssertEqual(Set(s.points.map(\.segment)).count, 2, "the hole starts a new line")
        XCTAssertEqual(s.gaps.first, HRHistory.Gap(from: 3_600 + 600, to: 3_600 + 1_800))
        XCTAssertEqual(s.gaps.last, HRHistory.Gap(from: 3_600 + 1_860, to: 7_200))
        XCTAssertEqual(s.coveredSeconds, 660)
        XCTAssertEqual(s.min, 60)
        XCTAssertEqual(s.max, 100)
        XCTAssertEqual(s.average!, (600 * 64.5 + 60 * 100) / 660, accuracy: 0.01)
        XCTAssertTrue(s.enoughData)
    }

    func testEmptyAndSparsePeriods() {
        let empty = HRHistory.series([], from: 0, to: 3_600, width: 60)
        XCTAssertTrue(empty.points.isEmpty)
        XCTAssertNil(empty.average)
        XCTAssertEqual(empty.gaps, [HRHistory.Gap(from: 0, to: 3_600)])
        let sparse = HRHistory.series(HRHistory.bin((0..<100).map { (ts: $0, hr: 70) }, width: 60), from: 0, to: 3_600, width: 60)
        XCTAssertFalse(sparse.enoughData)
        XCTAssertEqual(HRHistory.bin([(ts: 0, hr: 10), (ts: 1, hr: 250)], width: 60), [])
    }

    func testMergePrefersFullerSourceAndRebinAlignsToLocalTime() {
        let strap = [HRHistory.Bin(start: 0, seconds: 60, sum: 3_600, min: 55, max: 65)]
        let live = [HRHistory.Bin(start: 0, seconds: 20, sum: 2_000, min: 90, max: 110),
                    HRHistory.Bin(start: 60, seconds: 30, sum: 2_400, min: 75, max: 85)]
        let m = HRHistory.merge(strap, live)
        XCTAssertEqual(m.map(\.seconds), [60, 30])
        XCTAssertEqual(m[0].mean, 60)
        // Offset +1 h: local midnight is 23:00 UTC, so 4-hour bins start at 23:00 UTC.
        XCTAssertEqual(HRHistory.binStart(82_800 + 100, width: 14_400, offset: 3_600), 82_800)
        XCTAssertEqual(HRHistory.binStart(-10, width: 60), -60)
        let wide = HRHistory.rebin(m, width: 3_600)
        XCTAssertEqual(wide.count, 1)
        XCTAssertEqual(wide[0].seconds, 90)
        XCTAssertEqual(wide[0].max, 85)
    }

    func testRecoveryProblemSaysWhatWasMissing() {
        let stop = 1_000.0
        let onlyBefore = stride(from: 960.0, through: 1_000, by: 1).map { (t: $0, hr: 160.0) }
        XCTAssertNil(LiveMetrics.recovery(onlyBefore, stopAt: stop))
        let p = LiveMetrics.recoveryProblem(onlyBefore, stopAt: stop)!
        XCTAssertTrue(p.contains("55 y 65 s"), p)
        XCTAssertFalse(p.contains("30 s antes"), "only the missing part is named")
        let onlyAfter = stride(from: 1_001.0, through: 1_130, by: 1).map { (t: $0, hr: 120.0) }
        XCTAssertTrue(LiveMetrics.recoveryProblem(onlyAfter, stopAt: stop)!.hasPrefix("No llegó pulso (1 por segundo) en los 30 s antes"))
        XCTAssertNil(LiveMetrics.recoveryProblem(onlyBefore + onlyAfter, stopAt: stop))
    }

    func testOrthostaticCoverageNamesThePhaseWithoutRR() {
        let standAt = 1_200.0
        let lying = steady(from: 1_000, seconds: 200, rr: 950)
        let cov = LiveMetrics.orthostaticCoverage(lying, standAt: standAt)
        XCTAssertGreaterThan(cov.lying, 50)
        XCTAssertEqual(cov.settled, 0)
        XCTAssertTrue(cov.problem!.contains("de pie (minuto 2–3): 0"))
        XCTAssertFalse(cov.problem!.contains("tumbado"))
        let full = lying + steady(from: 1_200.5, seconds: 190, rr: 760)
        XCTAssertNil(LiveMetrics.orthostaticCoverage(full, standAt: standAt).problem)
    }

    func testBreathingSessionSummary() {
        let start = 2_000.0, end = 2_300.0
        let pre = steady(from: 1_900, seconds: 99, rr: 850, amp: 8, breaths: 14)
        let during = steady(from: 2_000, seconds: 300, rr: 900, amp: 60, breaths: 6)
        let scores = stride(from: 2_010.0, to: 2_300, by: 10).map { (t: $0, score: 30 + ($0 - 2_000) / 5) }
        let b = LiveMetrics.breathing(pre + during, start: start, end: end, scores: scores)
        XCTAssertFalse(b.beforeIsFirstMinute)
        XCTAssertGreaterThan(b.rmssdAfter!, b.rmssdBefore!)
        XCTAssertGreaterThan(b.coherenceTrend!, 0)
        XCTAssertGreaterThan(b.beats, 300)
        // No beats before: "before" falls back to the first minute and says so.
        let noPre = LiveMetrics.breathing(during, start: start, end: end, scores: [])
        XCTAssertTrue(noPre.beforeIsFirstMinute)
        XCTAssertNil(noPre.coherenceTrend)
        // A session too short for a last minute distinct from the first gives no "after".
        XCTAssertNil(LiveMetrics.breathing(during, start: start, end: start + 60, scores: []).rmssdAfter)
    }
}
