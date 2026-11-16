import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class WalkStepsTests: XCTestCase {
    /// Counter readings: `ticks[i]` steps added at second `i`.
    private func samples(_ ticks: [Int], from start: Int = 0, counter: Int = 1000) -> [Sample] {
        var c = counter
        return ticks.enumerated().map { i, n in c += n; return Sample(ts: start + i, hr: 80, steps: c) }
    }

    func testAnArmMovementIsNotAWalk() {
        // The strap credits 6 at once and nothing follows: what it does on a lone arm movement.
        let s = samples([0, 0, 0, 6, 0, 0, 0, 0, 0, 0, 6, 1, 0, 0, 0, 0])
        XCTAssertEqual(Epochs.countedSteps(s).reduce(0) { $0 + $1.steps }, 0)
    }

    func testAWalkCountsFromItsFirstStep() {
        let s = samples([0, 6] + Array(repeating: 2, count: 20) + [0, 0, 0, 0, 0])
        XCTAssertEqual(Epochs.countedSteps(s).reduce(0) { $0 + $1.steps }, 46)
        let m = Epochs.minutes(s, from: 0, to: 60)
        XCTAssertEqual(m[0].walkSteps, 46)
        XCTAssertEqual(m[0].stepsDelta, 46, "the raw counter stays as a movement signal")
    }

    func testShortPausesKeepTheWalkTogether() {
        // 5 + 5 + 5, 3 s apart: one walk of 15. 4 s apart: three movements of 5.
        XCTAssertEqual(Epochs.countedSteps(samples([0, 5, 0, 0, 5, 0, 0, 5, 0])).reduce(0) { $0 + $1.steps }, 15)
        XCTAssertEqual(Epochs.countedSteps(samples([0, 5, 0, 0, 0, 5, 0, 0, 0, 5, 0])).reduce(0) { $0 + $1.steps }, 0)
    }

    func testStepsAcrossAGapStillCount() {
        var s = samples([0, 0])
        s.append(Sample(ts: 600, hr: 80, steps: 1000 + 900))
        XCTAssertEqual(Epochs.countedSteps(s).reduce(0) { $0 + $1.steps }, 900, "a 10-minute walk the strap kept counting")
        s.append(Sample(ts: 601, hr: 80, steps: 1000 + 900 + 5000))
        XCTAssertEqual(Epochs.countedSteps(s).reduce(0) { $0 + $1.steps }, 900, "5 000 in a second is a reset")
    }
}
