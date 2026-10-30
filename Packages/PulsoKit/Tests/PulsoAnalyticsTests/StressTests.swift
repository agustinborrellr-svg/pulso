import XCTest
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
