import Foundation
import UserNotifications
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

extension AppModel {
    /// The single alarm of older versions (UserDefaults) becomes a daily fixed AlarmConfig.
    func migrateLegacyAlarm() {
        let d = UserDefaults.standard
        guard alarms.isEmpty, let time = d.object(forKey: "pulso.alarm.time") as? Date else { return }
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        alarms = [AlarmConfig(enabled: d.bool(forKey: "pulso.alarm.enabled"), hour: c.hour ?? 7, minute: c.minute ?? 0,
                              weekdays: [1, 2, 3, 4, 5, 6, 7], mode: .fixed)]
        try? db.set(alarms, for: "alarms")
        d.removeObject(forKey: "pulso.alarm.time")
        d.removeObject(forKey: "pulso.alarm.enabled")
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["pulso.alarm"])
    }

    var nextAlarm: PlannedAlarm? { AlarmPlanner.next(alarms, after: Date()) }

    func saveAlarm(_ a: AlarmConfig) {
        if let i = alarms.firstIndex(where: { $0.id == a.id }) {
            alarms[i] = a
        } else {
            alarms.append(a)
        }
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        persistAlarms()
    }

    func deleteAlarm(id: String) {
        alarms.removeAll { $0.id == id }
        if wakeSession?.planned.alarm.id == id, wakeSession?.isActive != true { wakeSession = nil }
        persistAlarms()
    }

    func toggleAlarm(id: String, on: Bool) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        alarms[i].enabled = on
        persistAlarms()
    }

    /// Skips (or un-skips) the next occurrence of an alarm.
    func skipNext(id: String) {
        guard let i = alarms.firstIndex(where: { $0.id == id }) else { return }
        if alarms[i].skipDay != nil {
            alarms[i].skipDay = nil
        } else if let p = AlarmPlanner.next(alarms[i], after: Date()) {
            alarms[i].skipDay = p.dayKey
        }
        persistAlarms()
    }

    private func persistAlarms() {
        try? db.set(alarms, for: "alarms")
        if alarms.contains(where: { $0.enabled }) {
            alarmBackup.requestAuthorization()
            NotificationService.shared.requestAuthorization()
        }
        if let s = wakeSession, !s.isActive, s.state != .monitoring { wakeSession = nil }
        refreshAlarmSchedule()
        evaluateAlerts(force: true)
        updateWidget()
    }

    /// Plans the next alarm: wake session, strap alarm and iPhone backup. Never disturbs an alarm
    /// that is monitoring, ringing or snoozed.
    func refreshAlarmSchedule() {
        if let s = wakeSession, s.isActive || s.state == .monitoring {
            updateAlarmStatus()
            return
        }
        guard let next = AlarmPlanner.next(alarms, after: Date()) else {
            wakeSession = nil
            if UserDefaults.standard.object(forKey: "pulso.backup.at") != nil {
                alarmBackup.cancel()
                UserDefaults.standard.removeObject(forKey: "pulso.backup.at")
            }
            strap.setAlarm(nil)
            updateAlarmStatus()
            updateNightGuard()
            return
        }
        if wakeSession?.planned != next {
            let need = SleepPlanner.tonightNeed(profile: profile, today: today, recent: days)
            wakeSession = WakeSession(planned: next, needMinutes: need)
        }
        // iPhone backup a little after the latest time (only rescheduled when it changes).
        let backupAt = next.latest.addingTimeInterval(Double(next.alarm.phoneBackupDelay) * 60)
        let stored = UserDefaults.standard.object(forKey: "pulso.backup.at") as? Date
        if next.alarm.phoneBackup {
            if stored != backupAt {
                alarmBackup.schedule(at: backupAt, title: next.alarm.label)
                UserDefaults.standard.set(backupAt, forKey: "pulso.backup.at")
            }
        } else if stored != nil {
            alarmBackup.cancel()
            UserDefaults.standard.removeObject(forKey: "pulso.backup.at")
        }
        armStrapAlarm()
        updateAlarmStatus()
        updateNightGuard()
    }

    /// The strap's own firmware alarm at the latest time: one more backup that works even if the
    /// phone is far away (experimental on 5.0 firmware).
    func armStrapAlarm() {
        guard let s = wakeSession, !s.isActive else { return }
        strap.setAlarm(s.planned.latest)
    }

    /// Smart alarms need the app alive at the start of the window. Keeping the strap's live stream on
    /// overnight makes iOS deliver a Bluetooth notification every second, which keeps Pulso running.
    func updateNightGuard() {
        guard let s = wakeSession, s.planned.isSmart, !(s.state == .finished) else {
            setLive(false, client: "night")
            return
        }
        let untilWindow = s.planned.earliest.timeIntervalSinceNow
        setLive(untilWindow < 10 * 3600 && untilWindow > -3 * 3600, client: "night")
    }

    func alarmTick(now: Date) {
        guard let s = wakeSession else { return }
        let actions = s.tick(now: Int(now.timeIntervalSince1970))
        if !actions.isEmpty { perform(actions, session: s) }
    }

    /// After each sync inside the smart window, decide whether to wake now.
    func alarmSyncFinished() {
        guard let s = wakeSession, s.state == .monitoring else { return }
        let now = Int(Date().timeIntervalSince1970)
        let samples = (try? db.samples(from: now - 12 * 3600, to: now + 60)) ?? []
        perform(s.evaluate(samples: samples, now: now), session: s)
        updateAlarmStatus()
    }

    func perform(_ actions: [WakeSession.Action], session s: WakeSession) {
        for a in actions {
            switch a {
            case .startLiveStream:
                strap.connect()
                setLive(true, client: "alarm")
            case .stopLiveStream:
                setLive(false, client: "alarm")
            case .requestSync:
                strap.sync(force: true)
            case .buzz(let loops):
                strap.buzz(loops: loops)
                alarmRinging = true
            case .alert(let title, let body):
                NotificationService.shared.now(title, body, id: "pulso.alarm.banner", category: NotificationService.Category.alarm,
                                               timeSensitive: true, sound: !s.planned.alarm.phoneBackup)
            case .backup(let at):
                if let at {
                    let date = Date(timeIntervalSince1970: TimeInterval(at))
                    alarmBackup.schedule(at: date, title: s.planned.alarm.label)
                    UserDefaults.standard.set(date, forKey: "pulso.backup.at")
                } else {
                    alarmBackup.cancel()
                    UserDefaults.standard.removeObject(forKey: "pulso.backup.at")
                }
            case .finished(let reason):
                alarmRinging = false
                appendLog("Alarma: \(reason)")
                strap.stopHaptics()
                strap.setAlarm(nil)
                completeAlarm(s, answered: reason == "Apagada")
            }
        }
        updateAlarmStatus()
    }

    private func completeAlarm(_ s: WakeSession, answered: Bool) {
        if let i = alarms.firstIndex(where: { $0.id == s.planned.alarm.id }) {
            alarms[i] = AlarmPlanner.afterFiring(alarms[i], dayKey: s.planned.dayKey)
            try? db.set(alarms, for: "alarms")
        }
        if !s.planned.alarm.morningReport {
            markAlertSent("morning.\(s.planned.dayKey)")
        }
        if let early = s.wokeEarlyBy, early >= 60 {
            appendLog("Despertado \(early / 60) min antes, en sueño ligero")
        }
        wakeSession = nil
        // Pull the night and compute today's recovery for the morning report.
        strap.sync(force: true)
        // If nobody answered, the iPhone backup is about to ring: don't replace it yet.
        let delay: Double = answered ? 2 : 15 * 60
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.refreshAlarmSchedule() }
    }

    func alarmSnooze() {
        guard let s = wakeSession else { return }
        strap.stopHaptics()
        perform(s.snooze(now: Int(Date().timeIntervalSince1970)), session: s)
    }

    func alarmStop() {
        guard let s = wakeSession else {
            alarmBackup.cancel()
            UserDefaults.standard.removeObject(forKey: "pulso.backup.at")
            return
        }
        strap.stopHaptics()
        perform(s.stop(now: Int(Date().timeIntervalSince1970)), session: s)
    }

    func updateAlarmStatus() {
        guard let s = wakeSession else {
            alarmStatus = nil
            alarmRinging = false
            return
        }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        switch s.state {
        case .waiting:
            let day = Fmt.dayTitle(s.planned.dayKey).lowercased()
            if s.planned.isSmart {
                alarmStatus = "\(s.planned.alarm.label): \(day) entre \(f.string(from: s.planned.earliest)) y \(f.string(from: s.planned.latest))"
            } else {
                alarmStatus = "\(s.planned.alarm.label): \(day) a las \(f.string(from: s.planned.latest))"
            }
        case .monitoring:
            alarmStatus = "Vigilando tu sueño hasta las \(f.string(from: s.planned.latest))" + (s.lastDecision.map { " · \($0.reason)" } ?? "")
        case .ringing:
            alarmStatus = "Sonando · doble toque en la pulsera para \(s.planned.alarm.doubleTap == .snooze ? "posponer" : "apagar")"
        case .snoozed(let until):
            alarmStatus = "Pospuesta hasta las \(f.string(from: Date(timeIntervalSince1970: TimeInterval(until))))"
        case .finished:
            alarmStatus = nil
        }
        alarmRinging = s.isActive
    }

    func handleNotificationAction(_ action: String, category: String, id: String) {
        switch (category, action) {
        case (NotificationService.Category.alarm, NotificationService.Action.snooze):
            if wakeSession?.isActive == true {
                alarmSnooze()
            } else if let a = alarms.first(where: { $0.enabled }) {
                // Backup ringing with no session (app was closed): ring again later.
                alarmBackup.schedule(at: Date().addingTimeInterval(Double(a.snoozeMinutes) * 60), title: a.label)
            }
        case (NotificationService.Category.alarm, NotificationService.Action.stop),
             (NotificationService.Category.alarm, UNNotificationDismissActionIdentifier):
            alarmStop()
        case (NotificationService.Category.breathe, NotificationService.Action.breathe):
            startBreathingGuide()
        default:
            break
        }
    }
}
