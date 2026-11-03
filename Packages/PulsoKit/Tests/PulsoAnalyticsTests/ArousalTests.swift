import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class ArousalTests: XCTestCase {
    private func night(_ hr: (Int) -> Double = { _ in 52 }, motion: (Int) -> Double = { _ in 0.008 }) -> [MinuteEpoch] {
        (0..<60).map { i in
            MinuteEpoch(ts: i * 60, hr: hr(i), hrSD: 1, motion: motion(i), posture: 0, wornFraction: 1, poorFraction: 0,
                        strapAsleepFraction: 1, strapWakeFraction: 0, temp: 34, spo2: [], stepsDelta: 0,
                        activityClass: 0, secondsWithData: 60)
        }
    }

    private func stages(awake: Range<Int>) -> [SleepStage] {
        (0..<60).map { awake.contains($0) ? .awake : .light }
    }

    func testStillWakeWithoutAPulseRiseIsLightSleep() {
        let out = SleepStager.absorbArousals(stages(awake: 20..<23), epochs: night(), stillThreshold: 0.02)
        XCTAssertFalse(out.contains(.awake), "same pulse as the half hour around it and no movement: a micro-arousal")
    }

    func testAPulseRiseKeepsTheWake() {
        let e = night({ (20..<23).contains($0) ? 64 : 52 })
        let out = SleepStager.absorbArousals(stages(awake: 20..<23), epochs: e, stillThreshold: 0.02)
        XCTAssertEqual(out.filter { $0 == .awake }.count, 3)
    }

    func testMovementKeepsTheWake() {
        let e = night(motion: { $0 == 21 ? 0.2 : 0.008 })
        let out = SleepStager.absorbArousals(stages(awake: 20..<23), epochs: e, stillThreshold: 0.02)
        XCTAssertEqual(out.filter { $0 == .awake }.count, 3)
    }

    func testNoDeepSleepRightAfterFallingAsleep() {
        // A pulse at its lowest of the night from the first minute would read as deep straight away.
        let e = night({ $0 < 30 ? 44 : 56 })
        let st = SleepStager.stage(e, rmssdPerMinute: e.map { _ in 60 }, stillThreshold: 0.02)
        let onset = st.firstIndex { $0 != .awake } ?? 0
        XCTAssertFalse(st[onset..<onset + SleepStager.deepLatency].contains(.deep))
        XCTAssertTrue(st.contains(.deep), "deep is only held back, not forbidden")
    }

    func testWakeAtTheEdgesIsLeftAlone() {
        let out = SleepStager.absorbArousals(stages(awake: 0..<5), epochs: night(), stillThreshold: 0.02)
        XCTAssertEqual(out.filter { $0 == .awake }.count, 5, "falling asleep is not an arousal")
    }
}
