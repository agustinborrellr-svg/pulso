import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class StressTests: XCTestCase {
    /// An ordinary day of still moments, spread around your usual HR and HRV.
    private func ordinaryDay(seed: UInt64 = 3) -> [Stress.StillWindow] {
        var x = seed
        func r() -> Double { x = x &* 6364136223846793005 &+ 1442695040888963407; return Double(x >> 11) / Double(1 << 53) }
        return (0..<80).map { i in
            Stress.StillWindow(ts: i * 300, hr: 64 + (r() - 0.5) * 10, rmssd: 45 + (r() - 0.5) * 20)
        }
    }

    func testAnOrdinaryDayReadsLowNotPermanentlyStressed() {
        let day = ordinaryDay()
        let ref = Stress.calmReference(day)
        let scores = Stress.score(day, calmHR: ref.hr!, calmHRV: ref.hrv).map(\.score)
        let mean = scores.reduce(0, +) / Double(scores.count)
        XCTAssertLessThan(mean, 1, "a typical still moment is low stress")
        XCTAssertLessThan(Double(scores.filter { $0 >= 2 }.count) / Double(scores.count), 0.1, "high stress is the exception")
    }

    func testARealStressBoutStandsOut() {
        var day = ordinaryDay()
        let ref = Stress.calmReference(day)
        for i in 30..<36 { day[i].hr += 18; day[i].rmssd = 18 }
        let scores = Stress.score(day, calmHR: ref.hr!, calmHRV: ref.hrv).map(\.score)
        XCTAssertGreaterThan(scores[32], 2)
        XCTAssertLessThan(scores[50], 1.5, "and it comes back down afterwards")
    }

    /// A day minute by minute: `hr(i)`, `motion(i)` and `steps(i)` per minute, beats at that pulse with `rr` jitter.
    private func minutes(_ count: Int, hr: (Int) -> Double, motion: (Int) -> Double = { _ in 0.005 },
                         steps: (Int) -> Int = { _ in 0 }, jitter: Int = 50) -> (samples: [Sample], epochs: [MinuteEpoch]) {
        var samples: [Sample] = []
        var counter = 0
        for m in 0..<count {
            let beat = Int(60000 / hr(m))
            counter += steps(m)
            for s in 0..<60 {
                samples.append(Sample(ts: m * 60 + s, hr: Int(hr(m).rounded()), rr: [beat + (s % 2 == 0 ? jitter : -jitter)],
                                      dyn: motion(m), steps: counter))
            }
        }
        return (samples, Epochs.minutes(samples, from: 0, to: count * 60))
    }

    func testEveryWornMinuteGetsAReading() {
        let d = minutes(60, hr: { _ in 62 }, motion: { $0 % 10 < 5 ? 0.005 : 0.15 }, steps: { $0 % 10 < 5 ? 0 : 90 })
        let w = Stress.everyMinute(samples: d.samples, epochs: d.epochs, calmHR: 62, calmHRV: 70, stillThreshold: 0.02, workouts: [])
        XCTAssertEqual(w.count, 60, "moving or not")
    }

    func testAnOrdinaryWalkIsNotStress() {
        // Still at 62, walking at 88 every afternoon minute: the walk explains the pulse.
        let d = minutes(120, hr: { $0 < 60 ? 62 : 88 }, motion: { $0 < 60 ? 0.005 : 0.15 }, steps: { $0 < 60 ? 0 : 100 })
        let w = Stress.everyMinute(samples: d.samples, epochs: d.epochs, calmHR: 62, calmHRV: 70, stillThreshold: 0.02, workouts: [])
        XCTAssertLessThan(w[90].score, 1)
    }

    func testARacingPulseWhileSittingIsStress() {
        let d = minutes(60, hr: { (30..<40).contains($0) ? 82 : 62 }, jitter: 50)
        let w = Stress.everyMinute(samples: d.samples, epochs: d.epochs, calmHR: 62, calmHRV: 70, stillThreshold: 0.02, workouts: [])
        XCTAssertGreaterThan(w[35].score, 2)
        XCTAssertLessThan(w[10].score, 1)
    }

    func testSleepReadsLowAndAWorkoutReadsAsEffort() {
        let d = minutes(120, hr: { $0 < 60 ? 50 : 140 }, motion: { $0 < 60 ? 0.003 : 0.3 }, jitter: 60)
        let w = Stress.everyMinute(samples: d.samples, epochs: d.epochs, calmHR: 62, calmHRV: 70, stillThreshold: 0.02,
                                   workouts: [3600...7200])
        XCTAssertLessThan(w[30].score, 0.5, "asleep: pulse under calm, HRV high")
        XCTAssertGreaterThan(w[90].score, 2.5, "a logged workout is not discounted")
    }
}

final class MaxHRAnchorTests: XCTestCase {
    func testOneSpuriousPeakDoesNotSetTheMax() {
        let peaks = [150, 162, 171, 168, 214, 158].map(Double.init)
        XCTAssertEqual(HeartRateModel.robustObservedMax(peaks), 171)
        XCTAssertEqual(HeartRateModel.maxHR(override: nil, age: 30, dailyPeaks: peaks), 187, "Tanaka 187 > 171")
        XCTAssertEqual(HeartRateModel.maxHR(override: nil, age: 30, dailyPeaks: [192, 194, 150]), 192)
        XCTAssertEqual(HeartRateModel.maxHR(override: 200, age: 30, dailyPeaks: peaks), 200)
        XCTAssertNil(HeartRateModel.robustObservedMax([190]))
    }
}
