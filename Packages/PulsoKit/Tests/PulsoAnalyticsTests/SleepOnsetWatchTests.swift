import XCTest
@testable import PulsoAnalytics

final class SleepOnsetWatchTests: XCTestCase {
    /// Beats from `start`: each segment is (minutes, bpm); RR wobbles ±20 ms so RMSSD exists and stays put.
    private func beats(_ segments: [(minutes: Double, bpm: Double)], start: Double = 1_000_000, gap: ClosedRange<Double>? = nil) -> [LiveMetrics.Beat] {
        var out: [LiveMetrics.Beat] = []
        var t = start
        var k = 0
        for s in segments {
            let end = t + s.minutes * 60
            while t < end {
                let rr = 60000 / s.bpm + (k % 2 == 0 ? 20 : -20)
                t += rr / 1000
                k += 1
                if let g = gap, g.contains(t - start) { continue }
                out.append(.init(t: t, rr: rr))
            }
        }
        return out
    }

    func testOnsetIsTheStartOfFiveMinutesWithThePulseDown() {
        let start = 1_000_000.0
        // 3 min awake at 66, 4 min barely lower, then down to 61 for good.
        let b = beats([(3, 66), (4, 64.5), (10, 61)], start: start)
        let onset = SleepOnsetWatch.detect(b, from: start)
        XCTAssertNotNil(onset)
        XCTAssertEqual(onset! - start, 7 * 60, accuracy: 30, "onset when the pulse settles 3+ bpm under the baseline")
    }

    func testNoOnsetUntilItHasLastedFiveMinutes() {
        let start = 1_000_000.0
        let b = beats([(3, 66), (4.5, 61)], start: start)
        XCTAssertNil(SleepOnsetWatch.detect(b, from: start), "4.5 minutes down isn't sustained sleep yet")
    }

    func testAGapInTheBeatsRestartsTheCount() {
        let start = 1_000_000.0
        // Down from minute 3, but contact lost from 5:00 to 6:00 (moving): the run starts again after it.
        let b = beats([(3, 66), (12, 61)], start: start, gap: 300...360)
        let onset = SleepOnsetWatch.detect(b, from: start)
        XCTAssertNotNil(onset)
        XCTAssertGreaterThanOrEqual(onset! - start, 360)
    }

    func testATurnInBedBreaksTheRun() {
        let start = 1_000_000.0
        // Down at minute 3, a 30-s jump to 75 at minute 6, then down again.
        let b = beats([(3, 66), (3, 61), (0.5, 75), (8, 61)], start: start)
        let onset = SleepOnsetWatch.detect(b, from: start)
        XCTAssertNotNil(onset)
        XCTAssertGreaterThanOrEqual(onset! - start, 6.5 * 60 - 1)
    }

    func testStaysAwakeWithASteadyPulse() {
        let start = 1_000_000.0
        XCTAssertNil(SleepOnsetWatch.detect(beats([(20, 66)], start: start), from: start))
    }

    func testWhenToLetGoOfTheLiveStream() {
        var t = SleepOnsetWatch.Trial(kind: .breathing, start: 0, end: 0)
        XCTAssertFalse(SleepOnsetWatch.shouldStop(t, now: 20 * 60))
        XCTAssertTrue(SleepOnsetWatch.shouldStop(t, now: 45 * 60), "never more than 45 min after 4-7-8")
        t.liveOnset = 600
        XCTAssertFalse(SleepOnsetWatch.shouldStop(t, now: 1000))
        XCTAssertTrue(SleepOnsetWatch.shouldStop(t, now: 1200), "10 min after falling asleep")
        var nap = SleepOnsetWatch.Trial(kind: .nap, start: 0, end: 0, napMinutes: 20)
        nap.liveOnset = 600
        XCTAssertFalse(SleepOnsetWatch.shouldStop(nap, now: 1200), "a nap waits for its wake time")
        nap.wouldWakeAt = 600 + 20 * 60
        XCTAssertTrue(SleepOnsetWatch.shouldStop(nap, now: 1800))
        XCTAssertTrue(SleepOnsetWatch.shouldStop(SleepOnsetWatch.Trial(kind: .nap, start: 0, end: 0), now: 90 * 60))
    }

    func testALateFinishIsCappedAtWhenItShouldHaveEnded() {
        var t = SleepOnsetWatch.Trial(kind: .breathing, start: 0, end: 0)
        XCTAssertEqual(SleepOnsetWatch.latestEnd(t), 45 * 60)
        t.liveOnset = 600
        XCTAssertEqual(SleepOnsetWatch.latestEnd(t), 1200)
        let nap = SleepOnsetWatch.Trial(kind: .nap, start: 0, end: 0, liveOnset: 300, napMinutes: 20, wouldWakeAt: 1500)
        XCTAssertEqual(SleepOnsetWatch.latestEnd(nap), 1500)
    }

    func testDownloadedOnsetIsTheFirstAsleepMinuteOfTheMatchingSleep() {
        let trial = SleepOnsetWatch.Trial(kind: .breathing, start: 10_000, end: 12_000, liveOnset: 10_900)
        let sleeps: [(start: Int, stages: [Int])] = [
            (start: 1_000, stages: [1, 1, 1]),            // ended long before
            (start: 10_200, stages: [0, 0, 0, 1, 2, 1]),  // the night: asleep from its 4th minute
            (start: 30_000, stages: [1, 1]),
        ]
        let d = SleepOnsetWatch.downloadedOnset(trial, sleeps: sleeps)
        XCTAssertEqual(d, 10_200 + 3 * 60)
        XCTAssertEqual(SleepOnsetWatch.errorMinutes(live: trial.liveOnset, downloaded: d)!, 520.0 / 60, accuracy: 0.01)
        XCTAssertNil(SleepOnsetWatch.downloadedOnset(SleepOnsetWatch.Trial(kind: .nap, start: 50_000, end: 51_000), sleeps: sleeps))
    }
}
