import XCTest
@testable import PulsoAnalytics

final class BreathworkTests: XCTestCase {
    func testAlertRoundsCountDownAndEndInAHold() {
        let steps = Breathwork.steps(.alert, .init(breaths: 30, rounds: 3))
        let round1 = steps.filter { $0.round == 1 }
        XCTAssertEqual(round1.first?.count, 30, "counts down from the chosen breaths")
        XCTAssertEqual(round1.filter { $0.phase == .inhale && $0.count != nil }.count, 30)
        XCTAssertEqual(steps.filter { $0.phase == .retention }.count, 3, "one hold on empty lungs per round")
        XCTAssertTrue(steps.filter { $0.phase == .retention }.allSatisfy { $0.seconds == nil }, "you end the hold yourself")
        XCTAssertEqual(steps.filter { $0.phase == .holdIn }.first?.seconds, Breathwork.recoveryHold)
    }

    func testTimedSessionsLastTheChosenMinutes() {
        for kind in [Breathwork.Kind.sigh, .coherence, .box] {
            let total = Breathwork.steps(kind, .init(minutes: 5)).compactMap(\.seconds).reduce(0, +)
            XCTAssertEqual(total, 300, accuracy: 12, "\(kind)")
        }
        let coherence = Breathwork.steps(.coherence, .init(minutes: 5, pace: 6))
        XCTAssertEqual(coherence.first?.seconds ?? 0, 4, accuracy: 1e-9, "6 a minute: 4 s in, 6 s out")
        XCTAssertEqual(Breathwork.steps(.sleep, .init(minutes: 1)).filter { $0.phase == .holdIn }.count, 4, "4-7-8: at least four cycles")
    }

    func testSummaryOfASession() {
        let done: [(phase: Breathwork.Phase, seconds: Double)] = [(.inhale, 50), (.exhale, 40), (.retention, 62), (.holdIn, 15), (.retention, 90)]
        let hr = (0..<300).map { (t: Double(1000 + $0), hr: 60 + Double($0 % 20)) }
        let s = Breathwork.summarize(kind: .alert, start: 1000, end: 1300, done: done, hr: hr, beats: [], baseline: .init())
        XCTAssertEqual(s.retentions, [62, 90])
        XCTAssertEqual(s.holdSeconds, 167)
        XCTAssertEqual(s.hrMin, 60)
        XCTAssertEqual(s.hrMax, 79)
        XCTAssertEqual(s.duration, 300)
        XCTAssertEqual(s.hrSeries.count, 60, "one point every 5 s")
        XCTAssertNil(s.stressChange, "no beats, no stress")
    }

    func testActivityNamesAreTheBreathingActivities() {
        XCTAssertEqual(Breathwork.activityNames.count, Breathwork.Kind.allCases.count)
        XCTAssertTrue(Breathwork.activityNames.contains("Aumentar el estado de alerta"))
    }

    func testStressAlertNeedsFiveStillHighMinutesAndAQuietHour() {
        let now = 10_000.0
        let high = (0..<11).map { (t: now - 300 + Double($0) * 30, stress: 2.4, still: true) }
        XCTAssertTrue(StressAlert.shouldAlert(high, now: now, lastAlert: nil))
        XCTAssertFalse(StressAlert.shouldAlert(high, now: now, lastAlert: now - 1200), "at most once an hour")
        var moving = high
        moving[5].still = false
        XCTAssertFalse(StressAlert.shouldAlert(moving, now: now, lastAlert: nil), "a walk raises the pulse, not stress")
        XCTAssertFalse(StressAlert.shouldAlert(Array(high.suffix(4)), now: now, lastAlert: nil), "two minutes are not a while")
    }

    func testStressAlertFromDownloadedMinutes() {
        let origin = 1_000_000
        // 10 calm minutes, then 6 high ones up to the newest data.
        let mins: [Double?] = Array(repeating: 0.8, count: 10) + Array(repeating: 2.3, count: 6)
        let newest = origin + 15 * 60
        XCTAssertEqual(StressAlert.recentRun(mins, origin: origin, now: newest + 300), origin + 10 * 60)
        XCTAssertNil(StressAlert.recentRun(mins, origin: origin, now: newest + 30 * 60), "too old to tap you now")
        XCTAssertNil(StressAlert.recentRun(Array(mins.dropLast(2)), origin: origin, now: newest), "four minutes are not a while")
        var gap = mins
        gap[12] = nil
        XCTAssertNil(StressAlert.recentRun(gap, origin: origin, now: newest), "a gap breaks the stretch")
        XCTAssertNil(StressAlert.recentRun(mins + [1.0], origin: origin, now: newest), "it has to run up to the newest minute")
        XCTAssertNil(StressAlert.recentRun([], origin: origin, now: newest))
    }
}
