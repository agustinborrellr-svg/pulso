import Foundation
import CoreMotion
import UserNotifications
import PulsoStore
import PulsoAnalytics

/// A finished guided-breathing session, kept next to the activity it was logged as.
struct BreathworkRecord: Codable, Identifiable, Equatable {
    var id: Int { summary.start }
    var summary: Breathwork.Summary
}

/// Live state of the stress alert (lives in `AppModel.stressAlertState`).
final class StressAlertState {
    var readings: [(t: Double, stress: Double, still: Bool)] = []
    var lastAlert: Double?
    var lastCheck: Double = 0
    var lastMovement: Double = 0
    var motionStarted = false
    let motion = CMMotionActivityManager()
}

extension AppModel {
    static let breathworkKey = "breathwork.sessions"
    static let breathworkSettingsKey = "breathwork.settings"
    static let stressAlertKey = "pulso.stressAlert"
    static let stressAlertLastKey = "pulso.stressAlert.last"
    static let stressAlertRunKey = "pulso.stressAlert.run"

    var breathworkRecords: [BreathworkRecord] { db.get([BreathworkRecord].self, for: Self.breathworkKey) ?? [] }

    func breathworkSettings(_ kind: Breathwork.Kind) -> Breathwork.Settings {
        let all = db.get([String: Breathwork.Settings].self, for: Self.breathworkSettingsKey) ?? [:]
        return all[kind.rawValue] ?? (kind == .alert ? .init(breaths: 30, rounds: 3) : .init(minutes: kind == .sleep ? 3 : 5))
    }

    func saveBreathworkSettings(_ s: Breathwork.Settings, for kind: Breathwork.Kind) {
        var all = db.get([String: Breathwork.Settings].self, for: Self.breathworkSettingsKey) ?? [:]
        all[kind.rawValue] = s
        try? db.set(all, for: Self.breathworkSettingsKey)
    }

    /// Keeps the session and logs it as an activity of the day.
    func saveBreathwork(_ summary: Breathwork.Summary) {
        var all = breathworkRecords
        all.append(BreathworkRecord(summary: summary))
        try? db.set(Array(all.suffix(500)), for: Self.breathworkKey)
        saveWorkout(Workout(start: summary.start, end: max(summary.end, summary.start + 60), sport: Breathwork.activityName(summary.kind),
                            source: .manual))
        objectWillChange.send()
    }

    func breathworkRecord(for workout: Workout) -> BreathworkRecord? {
        breathworkRecords.first { abs($0.summary.start - workout.start) <= 5 && Breathwork.activityName($0.summary.kind) == workout.sport }
    }

    /// Sessions of a kind in the 30 days before a time, for the "vs. your range" comparisons.
    func breathworkHistory(_ kind: Breathwork.Kind, before ts: Int) -> [Breathwork.Summary] {
        breathworkRecords.map(\.summary).filter { $0.kind == kind && $0.start < ts && $0.start >= ts - 30 * 86_400 }
    }

    var stressAlertEnabled: Bool { UserDefaults.standard.object(forKey: Self.stressAlertKey) as? Bool ?? true }

    /// Called with every live beat: every 30 s, reads your stress from the last minute of beats; still and high for
    /// five minutes, the strap taps you and a notification offers a short breathing session.
    func checkStressAlert(at date: Date) {
        guard stressAlertEnabled, liveWorkout == nil, !likelyAsleep(date) else { return }
        let s = stressAlertState
        let now = date.timeIntervalSince1970
        startMotionIfNeeded()
        guard now - s.lastCheck >= 30 else { return }
        s.lastCheck = now
        guard let stress = LiveMetrics.scan(beats(since: date.addingTimeInterval(-60)), baseline: liveBaseline)?.stress else { return }
        let still = CMMotionActivityManager.isActivityAvailable() ? now - s.lastMovement > 300 : true
        s.readings.append((now, stress, still))
        s.readings.removeAll { $0.t < now - 600 }
        guard StressAlert.shouldAlert(s.readings, now: now, lastAlert: lastStressAlert) else { return }
        sendStressAlert(at: now, since: nil)
    }

    /// After each download, the same alert from the downloaded minutes, so it also works with the live stream off
    /// (phone locked, app in the background).
    func checkStressFromDownload() {
        guard stressAlertEnabled, liveWorkout == nil, let today = day(currentDayKey), let cs = today.cycleStart,
              let newestIndex = today.stressMinutes.lastIndex(where: { $0 != nil }) else { return }
        let origin = today.stressOrigin ?? cs - cs % 60
        let now = Date().timeIntervalSince1970
        guard let start = StressAlert.recentRun(today.stressMinutes, origin: origin, now: Int(now)),
              start > UserDefaults.standard.integer(forKey: Self.stressAlertRunKey),
              now - (lastStressAlert ?? 0) >= StressAlert.quietHours * 3600 else { return }
        let newest = origin + newestIndex * 60
        guard !likelyAsleep(Date(timeIntervalSince1970: TimeInterval(newest))) else { return }
        // A pulse raised by a workout (or the 90 min after it) isn't the stress this is about.
        guard !workouts(for: today).contains(where: { $0.start <= newest && $0.end + 90 * 60 >= start }) else { return }
        UserDefaults.standard.set(start, forKey: Self.stressAlertRunKey)
        sendStressAlert(at: now, since: start)
    }

    /// Last alert from either path, kept across launches so a relaunch in the background doesn't tap you twice.
    private var lastStressAlert: Double? {
        let saved = UserDefaults.standard.double(forKey: Self.stressAlertLastKey)
        return max(stressAlertState.lastAlert ?? 0, saved) > 0 ? max(stressAlertState.lastAlert ?? 0, saved) : nil
    }

    private func sendStressAlert(at now: Double, since: Int?) {
        stressAlertState.lastAlert = now
        UserDefaults.standard.set(now, forKey: Self.stressAlertLastKey)
        strap.buzz(loops: 2)
        let content = UNMutableNotificationContent()
        content.title = "Llevas un rato con el estrés alto"
        content.body = (since.map { "Desde las \(Fmt.time($0)). " } ?? "") + "¿2 minutos de suspiro fisiológico? Abre Live y la pulsera te marca el ritmo."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stress-alert-\(Int(now))", content: content, trigger: nil))
    }

    /// Inside your usual sleep window (from your recent nights, 23:00–07:30 until there are three), never tap you.
    func likelyAsleep(_ date: Date) -> Bool {
        let recent = days.suffix(14)
        let window = StressSummary.sleepWindow(starts: recent.compactMap(\.sleepStart), ends: recent.compactMap(\.sleepEnd))
            ?? (23 * 60, 7 * 60 + 30)
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return StressSummary.contains(window, clock: (c.hour ?? 0) * 60 + (c.minute ?? 0))
    }

    /// The day's high-stress minutes split by what was going on.
    func stressSplit(for day: DaySummary) -> StressSummary.Split? {
        guard let cs = day.cycleStart, !day.stressMinutes.isEmpty else { return nil }
        return StressSummary.split(minutes: day.stressMinutes, origin: day.stressOrigin ?? cs - cs % 60, wake: cs,
                                   workouts: workouts(for: day).filter { !Breathwork.activityNames.contains($0.sport) }.map { $0.start...$0.end },
                                   naps: daytimeSleeps(on: day.day).map { $0.start...$0.end })
    }

    static func stressSummaryText(_ s: StressSummary.Split) -> String {
        guard s.total > 0 else { return "Hoy no has tenido ratos de estrés alto." }
        var parts: [String] = []
        if s.activity > 0 { parts.append("\(Fmt.hm(Double(s.activity))) en entrenos o justo después") }
        if s.sleep > 0 { parts.append("\(Fmt.hm(Double(s.sleep))) al despertar o alrededor de una siesta") }
        if s.other > 0 { parts.append("\(Fmt.hm(Double(s.other))) sin relación con tu actividad ni tu sueño") }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " y " + parts.last! : parts[0]
        return "Hoy estuviste \(Fmt.hm(Double(s.total))) en estrés alto: \(list)."
    }

    /// The evening summary at 21:00, refreshed with every analysis so it carries the day's latest numbers.
    func scheduleStressSummary() {
        guard stressAlertEnabled, let today = day(currentDayKey), let s = stressSplit(for: today) else { return }
        var at = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        at.hour = 21
        guard let fire = Calendar.current.date(from: at), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Tu estrés de hoy"
        content.body = Self.stressSummaryText(s)
        let trigger = UNCalendarNotificationTrigger(dateMatching: at, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stress-summary-\(currentDayKey)", content: content, trigger: trigger))
    }

    private func startMotionIfNeeded() {
        let s = stressAlertState
        guard !s.motionStarted, CMMotionActivityManager.isActivityAvailable() else { return }
        s.motionStarted = true
        s.motion.startActivityUpdates(to: .main) { activity in
            guard let a = activity, a.walking || a.running || a.cycling || a.automotive else { return }
            s.lastMovement = Date().timeIntervalSince1970
        }
    }
}
