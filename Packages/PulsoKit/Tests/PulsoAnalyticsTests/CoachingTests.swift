import XCTest
import WhoopProtocol
import PulsoStore
@testable import PulsoAnalytics

final class CoachingTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    /// `n` consecutive days ending 2026-10-20 built by `make(index)`.
    func days(_ n: Int, _ make: (Int, inout DaySummary) -> Void) -> [DaySummary] {
        (0..<n).map { i in
            var d = DaySummary(day: DayKey.shift("2026-10-20", days: i - n + 1, calendar: calendar))
            make(i, &d)
            return d
        }
    }

    func baselineDay(_ i: Int, _ d: inout DaySummary) {
        let wobble = Double(i % 3) - 1
        d.hrv = 70 + wobble * 3
        d.rhr = 52 + wobble
        d.respRate = 14.5 + wobble * 0.2
        d.skinTemp = 34.2 + wobble * 0.05
        d.spo2 = 96 + wobble * 0.5
        d.recovery = 70
        d.strain = 11
        d.sleepMinutes = 450
        d.sleepNeedMinutes = 470
        d.sleepEfficiency = 0.9
        d.sleepStart = Int(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 23))!.timeIntervalSince1970) + i * 86400
        d.sleepEnd = d.sleepStart! + 8 * 3600
    }

    // MARK: Training load

    func testStrainLoadInverse() {
        for s in [0.5, 5.0, 10.0, 14.2, 18.0, 21.0] {
            XCTAssertEqual(Strain.score(load: TrainingLoad.load(fromStrain: s)), s, accuracy: 1e-9)
        }
        XCTAssertEqual(TrainingLoad.load(fromStrain: 0), 0)
    }

    func testTrainingLoadStatus() {
        // Steady weeks → optimal/maintaining; a sudden block of very hard days → risk.
        let normal: [Double] = [30, 20, 10, 2, 0], hard: [Double] = [30, 30, 30, 30, 15]
        var steady = days(42) { i, d in
            d.strain = 11
            d.zoneMinutes = normal
        }
        XCTAssertEqual(TrainingLoad.series(steady, calendar: calendar).count, 42)
        let s1 = TrainingLoad.status(TrainingLoad.series(steady, calendar: calendar))
        XCTAssertTrue([.maintaining, .optimal].contains(s1), "steady load: \(s1)")
        // One hard day after weeks of normal ones is not "too much too fast".
        var single = steady
        single[41].strain = 17
        single[41].zoneMinutes = hard
        let one = TrainingLoad.series(single, calendar: calendar)
        XCTAssertLessThan(one.last!.acwr!, 1.3, "a single hard day: \(one.last!.acwr!)")
        XCTAssertNotEqual(TrainingLoad.status(one), .risk)
        for i in 35..<42 {
            steady[i].strain = 19
            steady[i].zoneMinutes = hard
        }
        let series = TrainingLoad.series(steady, calendar: calendar)
        XCTAssertEqual(TrainingLoad.status(series), .risk)
        XCTAssertGreaterThan(series.last!.acwr!, 1.5)
        XCTAssertLessThan(series.last!.tsb, 0)
        // Missing days decay the load (rest).
        let sparse = [steady[0], steady[41]]
        XCTAssertEqual(TrainingLoad.series(sparse, calendar: calendar).count, 42)
        XCTAssertEqual(TrainingLoad.status(Array(TrainingLoad.series(steady, calendar: calendar).prefix(5))), .calibrating)
    }

    // MARK: Health monitor

    func testIllnessAlertNeedsSeveralSignals() {
        let history = days(20, baselineDay)
        var sick = DaySummary(day: "2026-10-21")
        sick.hrv = 50
        sick.rhr = 61
        sick.respRate = 16.2
        sick.skinTemp = 35.1
        sick.spo2 = 96
        let a = HealthMonitor.assess(sick, history: history)
        XCTAssertEqual(a.level, .alert)
        XCTAssertEqual(Set(a.signals.map { $0.key }), ["temp", "rhr", "resp", "hrv"])
        XCTAssertTrue(a.message.contains("temperatura"))

        var normal = sick
        normal.hrv = 70; normal.rhr = 52; normal.respRate = 14.5; normal.skinTemp = 34.2
        XCTAssertEqual(HealthMonitor.assess(normal, history: history).level, .normal)

        // One elevated sign alone (a hard workout raising RHR a bit) is only a watch at most.
        var oneSign = normal
        oneSign.rhr = 58
        XCTAssertLessThanOrEqual(HealthMonitor.assess(oneSign, history: history).level, .watch)
        // Without baselines nothing is flagged.
        XCTAssertEqual(HealthMonitor.assess(sick, history: []).level, .normal)
    }

    func testTrends() {
        var list = days(20, baselineDay)
        for i in 17..<20 {
            list[i].hrv = 52
            list[i].rhr = 57
            list[i].sleepDebtMinutes = 150
        }
        let keys = Set(HealthMonitor.trends(list).map { $0.key })
        XCTAssertEqual(keys, ["hrv_trend", "rhr_trend", "debt_trend"])
        XCTAssertTrue(HealthMonitor.trends(days(20, baselineDay)).isEmpty)
    }

    // MARK: Coach

    func testCoachTargets() {
        let load = TrainingLoad.series(days(42) { _, d in d.strain = 11 }, calendar: calendar)
        let green = DailyCoach.advice(recovery: 85, load: load, health: nil, sleepDebtMinutes: 0)
        XCTAssertEqual(green.strainTarget, 14...18)
        let red = DailyCoach.advice(recovery: 20, load: load, health: nil, sleepDebtMinutes: 0)
        XCTAssertEqual(red.strainTarget, 4...10)
        let sick = HealthMonitor.Assessment(day: "x", level: .alert, signals: [])
        let ill = DailyCoach.advice(recovery: 85, load: load, health: sick, sleepDebtMinutes: 130)
        XCTAssertEqual(ill.strainTarget, 2...8)
        XCTAssertTrue(ill.notes.contains { $0.contains("acuéstate antes") })
        var spiky = days(42) { _, d in d.strain = 11 }
        for i in 35..<42 { spiky[i].strain = 19 }
        let risky = DailyCoach.advice(recovery: 90, load: TrainingLoad.series(spiky, calendar: calendar), health: nil, sleepDebtMinutes: nil)
        XCTAssertLessThanOrEqual(risky.strainTarget.upperBound, 12)
        XCTAssertLessThanOrEqual(risky.strainTarget.lowerBound, risky.strainTarget.upperBound)
    }

    // MARK: Sleep planner

    func testBedtimePlan() {
        let recent = days(14, baselineDay)
        var p = Profile()
        p.sleepNeedHours = 8
        var today = DaySummary(day: "2026-10-21")
        today.strain = 15 // hard day → more need
        let need = SleepPlanner.tonightNeed(profile: p, today: today, recent: recent)
        XCTAssertGreaterThan(need, 480)
        let wake = calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 7))!
        let plan = SleepPlanner.plan(wake: wake, needMinutes: need, recent: recent)
        XCTAssertEqual(plan.inBedMinutes, need / 0.9 + 15, accuracy: 0.01)
        XCTAssertEqual(plan.caffeineCutoff, plan.bedtime.addingTimeInterval(-8 * 3600))
        XCTAssertLessThan(plan.bedtime, wake)
        let typical = SleepPlanner.typicalWakeMinutes(recent, calendar: calendar)
        XCTAssertEqual(typical ?? 0, 7 * 60, accuracy: 1)
    }

    // MARK: Cycle

    func testCycleTrackerFindsBiphasicShift() {
        // Two 28-day cycles: 14 low nights (34.0) then 14 high nights (34.4).
        let list = days(60) { i, d in
            let dayInCycle = i % 28
            d.skinTemp = (dayInCycle < 14 ? 34.0 : 34.4) + (i % 2 == 0 ? 0.02 : -0.02)
        }
        let e = CycleTracker.estimate(list, calendar: calendar)
        XCTAssertGreaterThanOrEqual(e.ovulations.count, 2)
        XCTAssertGreaterThanOrEqual(e.periodStarts.count, 1)
        // Day 60 → index 59 → day 3 of the third cycle: follicular.
        XCTAssertEqual(e.phase, .follicular)
        XCTAssertNotNil(e.nextPeriod)
        XCTAssertEqual(CycleTracker.estimate(Array(list.prefix(10)), calendar: calendar).phase, .unknown)
        // Flat temperatures never produce a shift.
        let flat = days(60) { _, d in d.skinTemp = 34.1 }
        XCTAssertTrue(CycleTracker.estimate(flat, calendar: calendar).ovulations.isEmpty)
    }

    // MARK: Merge

    func testWorkoutMerge() {
        let auto = Workout(id: 1, start: 1000, end: 4600, sport: "Actividad", source: .auto)
        let live = Workout(id: 2, start: 10_000, end: 13_600, sport: "Carrera", source: .live)
        var linked = Workout(id: 3, start: 20_000, end: 21_000, sport: "Fuerza", source: .health)
        linked.setExternalID("S1", for: "strava")
        let existing = [auto, live, linked]

        var ride = Workout(start: 1100, end: 4500, sport: "Ciclismo", source: .strava, distanceMeters: 25_000)
        ride.setExternalID("S2", for: "strava")
        XCTAssertEqual(WorkoutMerge.decide(ride, service: "strava", existing: existing), .replaceAuto(0))

        var run = Workout(start: 10_300, end: 13_500, sport: "Carrera", source: .strava, distanceMeters: 10_000)
        run.setExternalID("S3", for: "strava")
        XCTAssertEqual(WorkoutMerge.decide(run, service: "strava", existing: existing), .link(1))
        let merged = WorkoutMerge.link(run, into: live, service: "strava")
        XCTAssertEqual(merged.externalID("strava"), "S3")
        XCTAssertEqual(merged.distanceMeters, 10_000)
        XCTAssertEqual(merged.id, 2)
        XCTAssertEqual(merged.source, .live, "the strap's own workout wins")

        var again = Workout(start: 0, end: 10, sport: "Fuerza", source: .strava)
        again.setExternalID("S1", for: "strava")
        XCTAssertEqual(WorkoutMerge.decide(again, service: "strava", existing: existing), .duplicate(2))

        let separate = Workout(start: 50_000, end: 52_000, sport: "Yoga", source: .health)
        XCTAssertEqual(WorkoutMerge.decide(separate, service: "health", existing: existing), .insert)
    }

    // MARK: Weekly

    func testWeeklySummary() {
        let list = days(14) { i, d in
            d.recovery = i < 7 ? 50 : 70
            d.sleepMinutes = i < 7 ? 400 : 440
            d.strain = 10
            d.workoutCount = i % 2
        }
        let s = WeeklySummary.compute(list, endDay: "2026-10-20", calendar: calendar)
        XCTAssertEqual(s.recovery, 70)
        XCTAssertEqual(s.previousRecovery, 50)
        XCTAssertEqual(s.workouts, 4, "odd indices 7, 9, 11, 13")
        XCTAssertTrue(s.text.contains("recuperación media 70 % (+20 pts)"), s.text)
        XCTAssertTrue(s.text.contains("(+40 min)"), s.text)
    }

    // MARK: Smart wake

    /// Seconds from `from` to `to` with a given phase, using the synthetic strap.
    func seconds(_ strap: inout SyntheticStrap, _ from: Int, _ to: Int, _ phase: SyntheticStrap.Phase) -> [Sample] {
        (from..<to).map { t in
            let h = strap.second(t, phase)
            return Sample(ts: t, hr: h.heartRate.map { Int($0) }, rr: h.rr.map { Int($0) }, gx: 0.1, gy: 0.2, gz: 0.97,
                          dyn: h.dynamicAccelG.map(Double.init), temp: 34.5, steps: h.steps.map { Int($0) },
                          activity: 0, sleepState: h.sleepState.map { Int($0) }, poor: false, off: false)
        }
    }

    func testSmartWakeWaitsInDeepSleepAndWakesOnMovement() {
        var strap = SyntheticStrap()
        let t0 = 1_790_000_000
        let latest = t0 + 3600, earliest = latest - 1800
        var samples = seconds(&strap, t0 - 3600, earliest + 300, .sleep(stage: 2, baseHR: 52, rsa: 0.06))
        var now = earliest + 300
        let deep = SmartWake.decide(.init(now: now, earliest: earliest, latest: latest, mode: .window, samples: samples))
        XCTAssertEqual(deep.action, .wait, deep.reason)

        // Three minutes of restless light sleep with movement.
        samples += seconds(&strap, now, now + 180, .awake(hr: 62, motion: 0.15))
        now += 180
        let light = SmartWake.decide(.init(now: now, earliest: earliest, latest: latest, mode: .window, samples: samples))
        XCTAssertEqual(light.action, .wake, light.reason)
        XCTAssertTrue(light.reason.contains("movimiento"), light.reason)

        // Outside the window: wait before, always wake at the end.
        XCTAssertEqual(SmartWake.decide(.init(now: earliest - 60, earliest: earliest, latest: latest, mode: .window, samples: samples)).action, .wait)
        XCTAssertEqual(SmartWake.decide(.init(now: latest, earliest: earliest, latest: latest, mode: .window, samples: [])).action, .wake)
    }

    func testSleepGoalWaitsForNeed() {
        var strap = SyntheticStrap()
        let onset = 1_790_000_000
        let earliest = onset + 6 * 3600, latest = onset + 9 * 3600
        let now = onset + 7 * 3600
        let samples = seconds(&strap, now - 1800, now - 180, .sleep(stage: 1, baseHR: 54, rsa: 0.05))
            + seconds(&strap, now - 180, now, .awake(hr: 64, motion: 0.15))
        let early = SmartWake.decide(.init(now: now, earliest: earliest, latest: latest, mode: .sleepGoal(needMinutes: 480),
                                           samples: samples, sleepOnset: onset))
        XCTAssertEqual(early.action, .wait, "only 7 h of an 8 h need")
        let done = SmartWake.decide(.init(now: now, earliest: earliest, latest: latest, mode: .sleepGoal(needMinutes: 410),
                                          samples: samples, sleepOnset: onset))
        XCTAssertEqual(done.action, .wake, done.reason)
    }
}

extension CoachingTests {
    func testImportedDaysWithoutZonesStillCount() {
        // Strap days with zones teach the ratio; imported WHOOP days only have strain.
        var list = days(28) { i, d in
            d.strain = 11
            d.zoneMinutes = [30, 20, 10, 2, 0]
        }
        for i in 0..<14 {
            list[i].source = "whoop"
            list[i].zoneMinutes = [0, 0, 0, 0, 0]
        }
        let series = TrainingLoad.series(list, calendar: calendar)
        XCTAssertEqual(series[0].load, series[20].load, accuracy: 1e-6, "an imported 11 weighs like a measured 11")
        XCTAssertEqual(series.last!.acwr ?? 0, 1, accuracy: 0.01)
    }
}
