import XCTest
@testable import PulsoAnalytics

final class LiveMetricsTests: XCTestCase {
    /// Beats for `seconds` at mean R-R `rr`, with a breathing-driven sine (amplitude `amp` ms, `breaths`/min)
    /// plus deterministic jitter.
    func beats(seconds: Double, rr: (Double) -> Double, amp: Double = 0, breaths: Double = 6, jitter: Double = 0, t0: Double = 1_000) -> [LiveMetrics.Beat] {
        var out: [LiveMetrics.Beat] = []
        var t = t0
        var seed: UInt64 = 42
        while t < t0 + seconds {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let noise = (Double(seed >> 33) / Double(1 << 31) - 0.5) * 2 * jitter
            let v = rr(t - t0) + amp * sin(2 * .pi * breaths / 60 * (t - t0)) + noise
            t += v / 1000
            out.append(.init(t: t, rr: v))
        }
        return out
    }

    func testScanAgainstBaseline() throws {
        let calm = beats(seconds: 60, rr: { _ in 900 }, amp: 40, breaths: 12, jitter: 10)
        let base = LiveMetrics.Baseline(calmHR: 67, calmHRV: 40)
        let s = try XCTUnwrap(LiveMetrics.scan(calm, baseline: base))
        XCTAssertEqual(s.hr, 66.7, accuracy: 1)
        XCTAssertNotNil(s.rmssd)
        XCTAssertLessThan(s.stress!, 1.2)
        XCTAssertGreaterThan(s.state!, 55)
        if let resp = s.respRate { XCTAssertEqual(resp, 12, accuracy: 2) }

        let tense = beats(seconds: 60, rr: { _ in 650 }, amp: 4, breaths: 18, jitter: 3)
        let t = try XCTUnwrap(LiveMetrics.scan(tense, baseline: base))
        XCTAssertGreaterThan(t.stress!, 2)
        XCTAssertLessThan(t.state!, s.state!)
        XCTAssertEqual(t.label, "Muy activado")
        // Without any baseline the numbers are there but no verdict.
        XCTAssertNil(LiveMetrics.scan(calm, baseline: .init())?.state)
        XCTAssertNil(LiveMetrics.scan(Array(calm.prefix(10)), baseline: base))
    }

    func testPoincareSD1MatchesRMSSD() throws {
        let b = beats(seconds: 120, rr: { _ in 850 }, amp: 30, breaths: 10, jitter: 15)
        let p = try XCTUnwrap(LiveMetrics.poincare(b))
        let rmssd = try XCTUnwrap(HRV.rmssd(HRV.clean(LiveMetrics.runs(b))))
        // SD1 ≈ RMSSD / √2 (identity for zero-mean differences).
        XCTAssertEqual(p.sd1, rmssd / 2.0.squareRoot(), accuracy: rmssd * 0.05)
        XCTAssertGreaterThan(p.sd2, p.sd1, "slow breathing adds long-term variability")
        XCTAssertEqual(p.points.count, b.count - 1)
    }

    func testCoherenceHighWhenBreathingSlowly() throws {
        let slow = beats(seconds: 70, rr: { _ in 900 }, amp: 80, breaths: 6, jitter: 5)
        let c = try XCTUnwrap(LiveMetrics.coherence(slow))
        XCTAssertEqual(c.peakPerMinute, 6, accuracy: 1)
        XCTAssertGreaterThan(c.score, 70)
        XCTAssertEqual(c.level, "Alta")
        let messy = beats(seconds: 70, rr: { _ in 800 }, amp: 0, jitter: 40)
        let m = try XCTUnwrap(LiveMetrics.coherence(messy))
        XCTAssertLessThan(m.score, c.score - 30)
    }

    func testOrthostaticRiseAndRatio() throws {
        // Lying 62 bpm; standing: quick rise to ~95, overshoot back, settles at 78.
        let standAt = 1_000.0 + 120
        let b = beats(seconds: 300, rr: { t in
            let s = t - 120
            if s < 0 { return 968 }
            if s < 15 { return 968 - (968 - 630) * min(1, s / 8) }
            if s < 30 { return 630 + (830 - 630) * (s - 15) / 15 }
            return 770
        }, amp: 10, breaths: 12, jitter: 4)
        let o = try XCTUnwrap(LiveMetrics.orthostatic(b, standAt: standAt))
        XCTAssertEqual(o.lyingHR, 62, accuracy: 1.5)
        XCTAssertEqual(o.standingHR, 78, accuracy: 1.5)
        XCTAssertEqual(o.rise, 16, accuracy: 2.5)
        XCTAssertGreaterThan(o.peakHR, 90)
        XCTAssertGreaterThan(o.ratio3015!, 1.04, "healthy overshoot")
        XCTAssertTrue(o.verdict.hasPrefix("Respuesta normal"))
    }

    func testRecoveryAndPeak() throws {
        // 170 bpm until stop, then exponential fall to 110 (τ = 40 s).
        let stop = 600.0
        let s = stride(from: 400.0, through: 800, by: 1).map { t -> (t: Double, hr: Double) in
            (t, t <= stop ? 170 : 110 + 60 * exp(-(t - stop) / 40))
        }
        let r = try XCTUnwrap(LiveMetrics.recovery(s, stopAt: stop))
        XCTAssertEqual(r.peakHR, 170, accuracy: 0.1)
        XCTAssertEqual(r.drop60, 60 - 60 * exp(-60.0 / 40), accuracy: 1.5)
        XCTAssertEqual(r.level, "Excelente")
        XCTAssertNotNil(r.drop120)
        // A single-beat spike does not set the max.
        var spiky = s
        spiky[50].hr = 220
        XCTAssertLessThan(LiveMetrics.peakHR(spiky)!, 185)
    }

    func testZoneGuard() {
        var g = LiveMetrics.ZoneGuard(low: 130, high: 150)
        XCTAssertNil(g.update(hr: 140, at: 0))
        XCTAssertNil(g.update(hr: 160, at: 1))
        XCTAssertNil(g.update(hr: 160, at: 8), "grace period")
        XCTAssertEqual(g.update(hr: 160, at: 12), .tooHigh)
        XCTAssertNil(g.update(hr: 162, at: 30), "not every second")
        XCTAssertEqual(g.update(hr: 140, at: 31), .backIn)
        XCTAssertNil(g.update(hr: 120, at: 40))
        XCTAssertEqual(g.update(hr: 120, at: 80), .tooLow)
    }

    func testLapsAndStrainInverse() {
        let s: [(t: Double, hr: Double)] = stride(from: 0.0, to: 300.0, by: 1.0).map { (t: Double) in (t: t, hr: t < 100 ? 120.0 : 150.0) }
        let laps = LiveMetrics.laps(s, marks: [100, 999], start: 0, end: 300)
        XCTAssertEqual(laps.count, 2)
        XCTAssertEqual(laps[0].avgHR, 120)
        XCTAssertEqual(laps[1].avgHR, 150)
        XCTAssertEqual(laps[1].duration, 200)
        for v in [0.0, 4.2, 12.5, 20.9] {
            XCTAssertEqual(Strain.score(load: Strain.load(score: v)), v, accuracy: 1e-9)
        }
    }
}
