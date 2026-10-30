import XCTest
import PulsoStore
@testable import PulsoAnalytics

final class StepsTests: XCTestCase {
    private func total(_ samples: [Sample]) -> Int {
        Epochs.minutes(samples, from: 0, to: 3600).reduce(0) { $0 + $1.stepsDelta }
    }

    func testStepsAcrossADataGapAreKept() {
        let s = [Sample(ts: 0, hr: 80, steps: 100), Sample(ts: 1, hr: 80, steps: 101), Sample(ts: 601, hr: 90, steps: 801)]
        XCTAssertEqual(total(s), 701, "10 minutes without data, 700 steps walked meanwhile")
    }

    func testACounterResetIsNotSteps() {
        let s = [Sample(ts: 0, hr: 80, steps: 60000), Sample(ts: 60, hr: 80, steps: 100), Sample(ts: 61, hr: 80, steps: 102)]
        XCTAssertEqual(total(s), 2)
    }
}

final class RejectedWorkoutTests: XCTestCase {
    func testADeletedAutoWorkoutStaysDeleted() throws {
        let db = try PulsoDatabase(path: NSTemporaryDirectory() + "pulso-rej-\(UUID().uuidString).sqlite")
        try db.rejectWorkout(start: 1000, end: 4600)
        XCTAssertTrue(db.isRejectedWorkout(start: 1100, end: 4500), "re-detection moves the edges a little")
        XCTAssertFalse(db.isRejectedWorkout(start: 9000, end: 12000))
    }

    func testLowMotionWithHighHRIsNotCalledCycling() {
        let w = (0..<20).map { i in
            MinuteEpoch(ts: i * 60, hr: 130, hrSD: 2, motion: 0.02, posture: 0, wornFraction: 1, poorFraction: 0,
                        strapAsleepFraction: 0, strapWakeFraction: 1, temp: nil, spo2: [], stepsDelta: 0,
                        activityClass: 0, secondsWithData: 60)
        }
        XCTAssertEqual(WorkoutDetector.guessSport(w), "Actividad")
    }
}
