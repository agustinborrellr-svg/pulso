import XCTest
import WhoopProtocol
import PulsoStore
import PulsoAnalytics
@testable import PulsoFeatures

final class FeaturesTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Alarm planning

    func testNextOccurrenceRespectsWeekdaysAndSkip() {
        // 2026-10-23 is a Friday.
        var a = AlarmConfig(hour: 7, minute: 30, weekdays: [2, 3, 4, 5, 6], mode: .smart, windowMinutes: 30)
        let fridayNight = date(2026, 10, 23, 22)
        let next = AlarmPlanner.next(a, after: fridayNight, calendar: calendar)!
        XCTAssertEqual(next.dayKey, "2026-10-26", "weekend skipped → Monday")
        XCTAssertEqual(next.latest, date(2026, 10, 26, 7, 30))
        XCTAssertEqual(next.earliest, date(2026, 10, 26, 7, 0))
        a.skipDay = "2026-10-26"
        XCTAssertEqual(AlarmPlanner.next(a, after: fridayNight, calendar: calendar)!.dayKey, "2026-10-27")
        a.enabled = false
        XCTAssertNil(AlarmPlanner.next(a, after: fridayNight, calendar: calendar))

        let once = AlarmConfig(hour: 6, minute: 0, weekdays: [], mode: .fixed)
        let p = AlarmPlanner.next(once, after: fridayNight, calendar: calendar)!
        XCTAssertEqual(p.latest, p.earliest, "fixed alarms have no window")
        XCTAssertEqual(p.dayKey, "2026-10-24")
        XCTAssertFalse(AlarmPlanner.afterFiring(once, dayKey: p.dayKey).enabled, "one-off switches off")
        var weekly = AlarmConfig(weekdays: [2])
        weekly.skipDay = "2026-10-26"
        let after = AlarmPlanner.afterFiring(weekly, dayKey: "2026-10-26")
        XCTAssertTrue(after.enabled)
        XCTAssertNil(after.skipDay)
    }

    func testUpcomingAndEarliestAmongMany() {
        let weekday = AlarmConfig(id: "w", hour: 7, minute: 0, weekdays: [2, 3, 4, 5, 6], mode: .fixed)
        let weekend = AlarmConfig(id: "e", hour: 9, minute: 30, weekdays: [1, 7], mode: .smart, windowMinutes: 45)
        let now = date(2026, 10, 23, 12) // Friday noon
        let next = AlarmPlanner.next([weekday, weekend], after: now, calendar: calendar)!
        XCTAssertEqual(next.alarm.id, "e")
        XCTAssertEqual(next.earliest, date(2026, 10, 24, 8, 45))
        let week = AlarmPlanner.upcoming([weekday, weekend], after: now, days: 7, calendar: calendar)
        XCTAssertEqual(week.count, 7, "5 weekdays + 2 weekend days in the next 7 days")
        XCTAssertEqual(week.map { $0.latest }, week.map { $0.latest }.sorted())
    }

    func testDaysText() {
        XCTAssertEqual(AlarmConfig(weekdays: [2, 3, 4, 5, 6]).daysText, "Entre semana")
        XCTAssertEqual(AlarmConfig(weekdays: [1, 7]).daysText, "Fines de semana")
        XCTAssertEqual(AlarmConfig(weekdays: [1, 2, 3, 4, 5, 6, 7]).daysText, "Todos los días")
        XCTAssertEqual(AlarmConfig(weekdays: []).daysText, "Una vez")
        XCTAssertEqual(AlarmConfig(weekdays: [2, 4, 1]).daysText, "L X D")
    }

    func testAlarmDecodingIsTolerant() throws {
        let old = #"{"id":"a1","enabled":true,"hour":6,"minute":45,"weekdays":[2,3]}"#
        let a = try JSONDecoder().decode(AlarmConfig.self, from: Data(old.utf8))
        XCTAssertEqual(a.id, "a1")
        XCTAssertEqual(a.hour, 6)
        XCTAssertEqual(a.mode, .smart)
        XCTAssertEqual(a.vibration, .progressive)
        XCTAssertEqual(try JSONDecoder().decode(AlarmConfig.self, from: JSONEncoder().encode(a)), a)
    }

    // MARK: Haptics

    func testHapticPlans() {
        let p = HapticPlan.ring(.progressive, duration: 180)
        XCTAssertEqual(p.first, HapticStep(at: 0, loops: 1))
        XCTAssertEqual(p.last?.loops, 6, "progressive ends strongest")
        XCTAssertEqual(p.map { $0.at }, p.map { $0.at }.sorted())
        XCTAssertTrue(p.allSatisfy { $0.at < 180 })
        XCTAssertTrue(HapticPlan.ring(.gentle).allSatisfy { $0.loops == 1 })
        let b = HapticPlan.breathing(cycles: 3)
        XCTAssertEqual(b.count, 6)
        XCTAssertEqual(b[1], HapticStep(at: 4, loops: 2))
        XCTAssertEqual(b[2].at, 10)
    }

    func testCustomHapticFrameMatchesKnownBuzz() {
        let a = CommandBuilder(family: .gen5, startSeq: 9)
        let b = CommandBuilder(family: .gen5, startSeq: 9)
        XCTAssertEqual(a.haptic(effects: [47, 152], loops: 2)?.bytes, b.buzz(loops: 2)?.bytes)
        XCTAssertNil(a.haptic(effects: [0, 0]))
        XCTAssertNotNil(a.stopHaptics())
    }

    // MARK: Wake session

    func planned(_ mode: WakeMode, snoozes: Int = 2, doubleTap: AlarmDoubleTap = .snooze) -> PlannedAlarm {
        let a = AlarmConfig(hour: 7, minute: 30, weekdays: [], mode: mode, windowMinutes: 30, vibration: .normal,
                            phoneBackup: true, phoneBackupDelay: 2, snoozeMinutes: 9, maxSnoozes: snoozes, doubleTap: doubleTap)
        return AlarmPlanner.next(a, after: date(2026, 10, 25, 22), calendar: calendar)!
    }

    func testFixedSessionRingsAtTimeAndBuzzesOnSchedule() {
        let p = planned(.fixed)
        let s = WakeSession(planned: p)
        let latest = Int(p.latest.timeIntervalSince1970)
        XCTAssertTrue(s.tick(now: latest - 3600).isEmpty, "fixed: no live stream needed beforehand")
        let ring = s.tick(now: latest)
        XCTAssertEqual(ring.first, .buzz(loops: 2))
        XCTAssertTrue(ring.contains(.backup(at: latest + 180 + 120)))
        XCTAssertTrue(ring.contains { if case .alert = $0 { return true }; return false })
        XCTAssertEqual(s.state, .ringing(since: latest))
        XCTAssertTrue(s.tick(now: latest + 1).isEmpty, "next step is 4 s later")
        XCTAssertEqual(s.tick(now: latest + 4), [.buzz(loops: 2)])
        // A late tick (app was busy for 30 s) plays one buzz, not a burst.
        XCTAssertEqual(s.tick(now: latest + 34).count, 1)
    }

    func testSmartSessionMonitorsSyncsAndWakesEarly() {
        let p = planned(.smart)
        let s = WakeSession(planned: p)
        let earliest = Int(p.earliest.timeIntervalSince1970)
        XCTAssertEqual(s.tick(now: earliest - 15 * 60), [.startLiveStream])
        XCTAssertTrue(s.tick(now: earliest - 60).isEmpty)
        XCTAssertEqual(s.tick(now: earliest), [.requestSync])
        XCTAssertEqual(s.state, .monitoring)
        XCTAssertTrue(s.tick(now: earliest + 60).isEmpty)
        XCTAssertEqual(s.tick(now: earliest + 150), [.requestSync])

        // Synced data shows movement → rings before the set time.
        var samples: [Sample] = []
        for t in (earliest - 3600)..<(earliest + 200) {
            samples.append(Sample(ts: t, hr: 52, rr: [], dyn: 0.006, sleepState: 2))
        }
        XCTAssertTrue(s.evaluate(samples: samples, now: earliest + 200, sleepOnset: earliest - 6 * 3600).isEmpty, "deep & still")
        for t in (earliest + 200)..<(earliest + 400) {
            samples.append(Sample(ts: t, hr: 63, rr: [], dyn: 0.2, sleepState: 1))
        }
        let actions = s.evaluate(samples: samples, now: earliest + 400, sleepOnset: earliest - 6 * 3600)
        XCTAssertEqual(actions.first, .buzz(loops: 2))
        XCTAssertEqual(s.wokeEarlyBy, 1800 - 400)
        if case .ringing = s.state {} else { XCTFail("should ring") }
    }

    func testSnoozeAndStopFlow() {
        let p = planned(.fixed, snoozes: 1)
        let s = WakeSession(planned: p)
        let t = Int(p.latest.timeIntervalSince1970)
        _ = s.tick(now: t)
        let snooze = s.doubleTap(now: t + 10)
        XCTAssertEqual(s.state, .snoozed(until: t + 10 + 540))
        XCTAssertTrue(snooze.contains(.backup(at: t + 10 + 540 + 180 + 120)))
        XCTAssertTrue(s.tick(now: t + 300).isEmpty)
        XCTAssertEqual(s.tick(now: t + 550).first, .buzz(loops: 2))
        // No snoozes left: double tap stops and cancels the iPhone backup.
        let stop = s.doubleTap(now: t + 560)
        XCTAssertEqual(stop, [.stopLiveStream, .backup(at: nil), .finished(reason: "Apagada")])
        XCTAssertEqual(s.state, .finished)
        XCTAssertTrue(s.tick(now: t + 9999).isEmpty)
    }

    func testRingingWithoutAnswerAutoSnoozesThenHandsOverToPhone() {
        let p = planned(.fixed, snoozes: 1)
        let s = WakeSession(planned: p)
        let t = Int(p.latest.timeIntervalSince1970)
        _ = s.tick(now: t)
        let auto = s.tick(now: t + 180)
        XCTAssertTrue(auto.contains { if case .alert(let title, _) = $0 { return title == "Repetición automática" }; return false })
        _ = s.tick(now: t + 180 + 540)
        let end = s.tick(now: t + 180 + 540 + 180)
        XCTAssertTrue(end.contains(.finished(reason: "Sin respuesta: suena el iPhone")))
        let stopTap = WakeSession(planned: planned(.fixed, doubleTap: .stop))
        _ = stopTap.tick(now: t)
        XCTAssertEqual(stopTap.doubleTap(now: t + 5).last, .finished(reason: "Apagada"))
    }

    // MARK: Alerts

    func baseDays(_ n: Int = 20) -> [DaySummary] {
        (0..<n).map { i in
            var d = DaySummary(day: DayKey.shift("2026-10-25", days: i - n, calendar: calendar))
            let w = Double(i % 3) - 1
            d.hrv = 70 + w * 3; d.rhr = 52 + w; d.respRate = 14.5 + w * 0.2; d.skinTemp = 34.2 + w * 0.05; d.spo2 = 96
            d.recovery = 70; d.strain = 11; d.sleepMinutes = 450; d.sleepNeedMinutes = 470; d.sleepEfficiency = 0.9
            return d
        }
    }

    func testMorningReportAndIllness() {
        var days = baseDays()
        var today = DaySummary(day: "2026-10-25")
        today.recovery = 31
        today.sleepMinutes = 402
        today.sleepPerformance = 0.82
        today.sleepEnd = Int(date(2026, 10, 25, 7, 10).timeIntervalSince1970)
        today.hrv = 49; today.rhr = 61; today.respRate = 16.3; today.skinTemp = 35.0; today.spo2 = 96
        days.append(today)
        let ctx = AlertContext(now: Int(date(2026, 10, 25, 7, 40).timeIntervalSince1970), calendar: calendar, days: days, profile: Profile())
        let out = AlertEngine.evaluate(ctx, prefs: AlertPreferences(), sent: [])
        let morning = out.first { $0.kind == .morningReport }
        XCTAssertNotNil(morning)
        XCTAssertTrue(morning!.body.contains("Recuperación 31 %"), morning!.body)
        XCTAssertTrue(morning!.body.contains("dormiste 6 h 42 min (82 %)"), morning!.body)
        XCTAssertNil(morning!.fireAt)
        let ill = out.first { $0.kind == .illness }
        XCTAssertNotNil(ill)
        XCTAssertTrue(ill!.timeSensitive)
        // Already sent → not again.
        let again = AlertEngine.evaluate(ctx, prefs: AlertPreferences(), sent: Set(out.map { $0.id }))
        XCTAssertFalse(again.contains { $0.kind == .morningReport || $0.kind == .illness })
        // Disabled kind → nothing.
        var prefs = AlertPreferences()
        prefs.enabled[.morningReport] = false
        XCTAssertFalse(AlertEngine.evaluate(ctx, prefs: prefs, sent: []).contains { $0.kind == .morningReport })
    }

    func testBedtimeScheduledAndQuietHoursDeferral() {
        let days = baseDays()
        let now = Int(date(2026, 10, 25, 15).timeIntervalSince1970)
        let wake = Int(date(2026, 10, 26, 7).timeIntervalSince1970)
        let ctx = AlertContext(now: now, calendar: calendar, days: days, profile: Profile(), battery: 30, charging: false,
                               lastSync: now - 600, nextWake: wake)
        let out = AlertEngine.evaluate(ctx, prefs: AlertPreferences(), sent: [])
        let bed = out.first { $0.kind == .bedtime }!
        XCTAssertNotNil(bed.fireAt)
        XCTAssertGreaterThan(bed.fireAt!, now)
        XCTAssertLessThan(bed.fireAt!, wake - 8 * 3600)
        XCTAssertTrue(bed.body.contains("despertar a las 07:00"), bed.body)
        XCTAssertTrue(bed.body.contains("Carga antes la pulsera (30 %)"), bed.body)
        XCTAssertTrue(bed.buzzStrap)
        // Sync-stale is scheduled 24 h after the last sync.
        let stale = out.first { $0.kind == .syncStale }!
        XCTAssertEqual(stale.fireAt, now - 600 + 86400)

        // Battery low at 02:00 waits until 07:00 (quiet hours 23–7).
        let night = Int(date(2026, 10, 26, 2).timeIntervalSince1970)
        let ctx2 = AlertContext(now: night, calendar: calendar, days: days, profile: Profile(), battery: 12, charging: false)
        let batt = AlertEngine.evaluate(ctx2, prefs: AlertPreferences(), sent: []).first { $0.kind == .batteryLow }!
        XCTAssertEqual(batt.fireAt, Int(date(2026, 10, 26, 7).timeIntervalSince1970))
        // Charging → no battery alert.
        let ctx3 = AlertContext(now: night, calendar: calendar, days: days, profile: Profile(), battery: 12, charging: true)
        XCTAssertFalse(AlertEngine.evaluate(ctx3, prefs: AlertPreferences(), sent: []).contains { $0.kind == .batteryLow })
    }

    func testStrainTargetAndOffWristAndInactivity() {
        var days = baseDays()
        var today = DaySummary(day: "2026-10-25")
        today.recovery = 80
        today.strain = 14.6
        days.append(today)
        let now = Int(date(2026, 10, 25, 18).timeIntervalSince1970)
        // Still for 70 min, worn, awake, steps not moving.
        var samples: [Sample] = []
        for t in (now - 70 * 60)..<now { samples.append(Sample(ts: t, hr: 72, rr: [], dyn: 0.02, steps: 500, sleepState: 1)) }
        let ctx = AlertContext(now: now, calendar: calendar, days: days, profile: Profile(), offWristSince: now - 600,
                               recentSamples: samples)
        var prefs = AlertPreferences()
        prefs.enabled[.inactivity] = true
        let out = AlertEngine.evaluate(ctx, prefs: prefs, sent: [])
        XCTAssertTrue(out.contains { $0.kind == .strainReached })
        let off = out.first { $0.kind == .offWrist }!
        XCTAssertEqual(off.fireAt, now - 600 + 3600)
        let inactive = out.first { $0.kind == .inactivity }
        XCTAssertNotNil(inactive)
        XCTAssertTrue(inactive!.buzzStrap)
        // Walking → no inactivity alert.
        let walking = samples.enumerated().map { i, s -> Sample in
            var x = s
            x.steps = 500 + i / 2
            x.dyn = 0.2
            return x
        }
        let ctx2 = AlertContext(now: now, calendar: calendar, days: days, profile: Profile(), recentSamples: walking)
        XCTAssertFalse(AlertEngine.evaluate(ctx2, prefs: prefs, sent: []).contains { $0.kind == .inactivity })
    }

    func testAlertPreferencesCodable() throws {
        var p = AlertPreferences()
        p.enabled[.weekly] = false
        p.strapBuzz[.illness] = true
        p.quietStart = 22 * 60
        let back = try JSONDecoder().decode(AlertPreferences.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        let partial = try JSONDecoder().decode(AlertPreferences.self, from: Data(#"{"enabled":{"weekly":false,"nope":true}}"#.utf8))
        XCTAssertFalse(partial.isOn(.weekly))
        XCTAssertTrue(partial.isOn(.morningReport), "missing kinds fall back to defaults")
        XCTAssertTrue(p.isQuiet(minuteOfDay: 23 * 60))
        XCTAssertTrue(p.isQuiet(minuteOfDay: 6 * 60))
        XCTAssertFalse(p.isQuiet(minuteOfDay: 12 * 60))
    }

    // MARK: Intervals

    func testIntervalRunnerCues() {
        let plan = IntervalPlan(id: "t", name: "t", detail: "", steps: [
            IntervalStep(.warmup, seconds: 60, zones: 1...2),
            IntervalStep(.work, seconds: 120, zones: 4...5),
        ])
        let model = HeartRateModel(restingHR: 50, maxHR: 190)
        let r = IntervalRunner(plan: plan, start: 0)
        XCTAssertEqual(r.tick(now: 0, heartRate: 100, model: model), [.stepStarted(index: 0, step: plan.steps[0])])
        XCTAssertEqual(r.tick(now: 57, heartRate: 100, model: model), [.countdown(secondsLeft: 3)])
        let work = r.tick(now: 60, heartRate: 110, model: model)
        XCTAssertEqual(work.first, .stepStarted(index: 1, step: plan.steps[1]))
        XCTAssertEqual(work.first?.buzzLoops, 3)
        // Too slow for zone 4 after the 30 s lag + 15 s grace.
        XCTAssertTrue(r.tick(now: 95, heartRate: 110, model: model).isEmpty)
        XCTAssertEqual(r.tick(now: 110, heartRate: 110, model: model), [.tooLow(zone: model.zone(110))])
        XCTAssertTrue(r.tick(now: 120, heartRate: 110, model: model).isEmpty, "rate-limited")
        XCTAssertTrue(r.tick(now: 130, heartRate: 170, model: model).isEmpty, "back in zone")
        XCTAssertEqual(r.tick(now: 180, heartRate: 170, model: model), [.finished])
        XCTAssertTrue(r.tick(now: 181, heartRate: 170, model: model).isEmpty)
        XCTAssertTrue(IntervalPlan.presets.allSatisfy { $0.totalSeconds > 0 && !$0.steps.isEmpty })
        XCTAssertEqual(IntervalPlan.presets.first { $0.id == "norwegian4x4" }?.totalSeconds, 600 + 4 * 420 + 300)
        XCTAssertTrue(IntervalRunner.Cue.stepStarted(index: 0, step: IntervalStep(.work, seconds: 90, zones: 4...5)).phrase
            .contains("1 minuto y 30 segundos"))
    }

    // MARK: Gestures & settings

    func testGestureRouting() {
        XCTAssertEqual(GestureRouter.route(action: .marker, alarmActive: true, workoutActive: false), .alarm)
        XCTAssertEqual(GestureRouter.route(action: .toggleWorkout, alarmActive: false, workoutActive: false), .startWorkout)
        XCTAssertEqual(GestureRouter.route(action: .toggleWorkout, alarmActive: false, workoutActive: true), .stopWorkout)
        XCTAssertEqual(GestureRouter.route(action: .lap, alarmActive: false, workoutActive: false), .marker)
        XCTAssertEqual(GestureRouter.route(action: .none, alarmActive: false, workoutActive: true), .ignored)
        let s = try? JSONDecoder().decode(FeatureSettings.self, from: Data(#"{"doubleTap":"lap"}"#.utf8))
        XCTAssertEqual(s?.doubleTap, .lap)
        XCTAssertEqual(s?.stravaAutoUpload, true)
    }
}
