import Foundation
import UserNotifications
import UIKit
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
            updateAlarmStream()
            return
        }
        if wakeSession?.planned != next {
            let need = SleepPlanner.tonightNeed(profile: profile, today: today, recent: days)
            wakeSession = WakeSession(planned: next, needMinutes: need)
        }
        // iPhone backup a little after the latest time (only rescheduled when it changes).
        let backupAt = next.latest.addingTimeInterval(Double(next.alarm.phoneBackupDelay) * 60)
        let stored = UserDefaults.standard.object(forKey: "pulso.backup.at") as? Date
        // A backup about to ring belongs to an alarm nobody answered: leave it alone.
        if let st = stored, st != backupAt, st > Date(), st.timeIntervalSinceNow < 20 * 60 {
            updateAlarmStatus()
            updateAlarmStream()
            return
        }
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
        updateAlarmStream()
    }

    /// How long before the window (or the set time) the strap's silent alarm wakes the app.
    static let wakeCallLead: TimeInterval = 60

    /// The alarm needs the app alive when its time comes: the strap can only be told to vibrate by a running app,
    /// and iOS suspends Pulso soon after the screen locks. Nothing keeps it awake overnight: the strap's own alarm,
    /// armed silent a minute before the window (or the set time), sends a Bluetooth event that wakes the app.
    func armStrapAlarm() {
        guard let s = wakeSession, s.state == .waiting else { return }
        let at = s.planned.earliest.addingTimeInterval(-Self.wakeCallLead)
        guard at > Date() else { return }
        strap.setAlarm(at, silent: true)
    }

    /// Once awake, the live stream keeps Pulso running, only from the wake-up call through the window, the
    /// ringing and the snoozes.
    func updateAlarmStream() {
        var on = false
        if let s = wakeSession {
            switch s.state {
            case .monitoring, .ringing, .snoozed: on = true
            case .waiting: on = Date() >= s.planned.earliest.addingTimeInterval(-Self.wakeCallLead - 60)
            case .finished: on = false
            }
        }
        setLive(on, client: "alarm")
    }

    func alarmTick(now: Date) {
        guard let s = wakeSession else { return }
        let actions = s.tick(now: Int(now.timeIntervalSince1970))
        if !actions.isEmpty { perform(actions, session: s) }
        updateAlarmStream()
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
            case .requestSync:
                strap.connect()
                strap.sync(force: true)
            case .buzz(let loops):
                strap.buzz(loops: loops)
                alarmRinging = true
            case .alert(let title, let body):
                // The first banner (ringing) carries the stop/snooze actions and its dismissal stops the alarm;
                // snooze confirmations use a category whose dismissal is harmless.
                let ringing: Bool = { if case .ringing = s.state { return true } else { return false } }()
                NotificationService.shared.now(title, body, id: ringing ? "pulso.alarm.banner" : "pulso.alarm.info",
                                               category: ringing ? NotificationService.Category.alarm : NotificationService.Category.alarmInfo,
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
        // The "ringing" banner stops the alarm when dismissed: once snoozed it must not linger in the
        // notification centre, or clearing it later would cancel the snooze.
        NotificationService.shared.remove(["pulso.alarm.banner"])
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
        case (NotificationService.Category.alarm, NotificationService.Action.snooze),
             (NotificationService.Category.alarmInfo, NotificationService.Action.snooze):
            if wakeSession?.isActive == true {
                alarmSnooze()
            } else if let a = alarms.first(where: { $0.enabled }) {
                // Backup ringing with no session (app was closed): ring again later.
                alarmBackup.schedule(at: Date().addingTimeInterval(Double(a.snoozeMinutes) * 60), title: a.label)
            }
        case (NotificationService.Category.alarm, NotificationService.Action.stop),
             (NotificationService.Category.alarmInfo, NotificationService.Action.stop),
             (NotificationService.Category.alarm, UNNotificationDismissActionIdentifier):
            alarmStop()
        case (NotificationService.Category.breathe, NotificationService.Action.breathe):
            startBreathingGuide()
        case (NotificationService.Category.sleepQuestion, _):
            handleSleepQuestionAction(action, id: id)
        default:
            break
        }
    }
}

// MARK: - Closed app

extension AppModel {
    /// Swiping Pulso away stops everything in the background (iOS never relaunches an app the user closed), so say
    /// so, above all with an alarm coming. iOS only tells an app that is running at that moment (alarm night, live
    /// stream, a download), not one already suspended.
    func watchForTermination() {
        NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.notifyClosed() }
        }
    }

    private func notifyClosed() {
        guard !AppMode.screenshots else { return }
        let alarmSoon = wakeSession.map { $0.state != .finished && $0.planned.latest.timeIntervalSinceNow < 14 * 3600 } ?? false
        let content = UNMutableNotificationContent()
        content.title = "Pulso se ha cerrado"
        content.body = alarmSoon
            ? "La alarma no podrá hacer vibrar la pulsera. Ábrela otra vez y déjala en segundo plano, sin cerrarla."
            : "Ábrela otra vez para que siga descargando los datos de la pulsera."
        content.sound = .default
        content.interruptionLevel = alarmSoon ? .timeSensitive : .active
        // The process is about to end: give the request a moment to reach the notification centre.
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pulso.closed", content: content, trigger: nil)) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 1.5)
    }
}

// MARK: - Wake-up call test

/// The "despertador de la pulsera" test on the Alarmas screen: a silent strap alarm one minute ahead.
enum WakeCallTest: Equatable {
    /// Sent; waiting for the strap to confirm it.
    case armed(Date)
    /// The strap said the alarm is set.
    case confirmed(Date)
    /// The strap ran it and its event reached the app.
    case worked(Date)
    case failed(String)
}

extension AppModel {
    static let wakeCallVerifiedKey = "alarm.wakeCall.verified"

    /// Whether a strap alarm has ever reached the app (test or real night).
    var wakeCallVerified: Bool { UserDefaults.standard.bool(forKey: Self.wakeCallVerifiedKey) }

    func startWakeCallTest() {
        guard strapState.isConnected else {
            wakeCallTest = .failed("Conecta la pulsera y vuelve a probar.")
            return
        }
        let at = Date().addingTimeInterval(60)
        strap.setAlarm(at, silent: true)
        wakeCallTest = .armed(at)
        // Runs late if the app was suspended and nothing woke it, which is itself the answer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 240) { [weak self] in self?.endWakeCallTestIfPending() }
    }

    private func endWakeCallTestIfPending() {
        switch wakeCallTest {
        case .armed: wakeCallTest = .failed("La pulsera no confirmó la alarma.")
        case .confirmed: wakeCallTest = .failed("La pulsera aceptó la alarma, pero no avisó a Pulso a su hora.")
        default: return
        }
        armStrapAlarm()
    }

    /// Strap events ALARM_SET (`executed` false) and STRAP_ALARM_EXECUTED (true).
    func wakeCallTestEvent(executed: Bool) {
        if executed { UserDefaults.standard.set(true, forKey: Self.wakeCallVerifiedKey) }
        switch (wakeCallTest, executed) {
        case (.armed(let at), false):
            wakeCallTest = .confirmed(at)
        case (.armed, true), (.confirmed, true):
            wakeCallTest = .worked(Date())
            NotificationService.shared.now("La pulsera ha despertado a Pulso",
                                           "Funciona: las alarmas ya no necesitan el pulso en directo de noche.", id: "pulso.wakecall.test")
            armStrapAlarm()
        default:
            break
        }
    }
}
