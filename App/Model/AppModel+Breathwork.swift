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
        guard stressAlertEnabled, liveWorkout == nil else { return }
        let s = stressAlertState
        let now = date.timeIntervalSince1970
        startMotionIfNeeded()
        guard now - s.lastCheck >= 30 else { return }
        s.lastCheck = now
        guard let stress = LiveMetrics.scan(beats(since: date.addingTimeInterval(-60)), baseline: liveBaseline)?.stress else { return }
        let still = CMMotionActivityManager.isActivityAvailable() ? now - s.lastMovement > 300 : true
        s.readings.append((now, stress, still))
        s.readings.removeAll { $0.t < now - 600 }
        guard StressAlert.shouldAlert(s.readings, now: now, lastAlert: s.lastAlert) else { return }
        s.lastAlert = now
        strap.buzz(loops: 2)
        let content = UNMutableNotificationContent()
        content.title = "Llevas un rato con el estrés alto"
        content.body = "¿2 minutos de suspiro fisiológico? Abre Live y la pulsera te marca el ritmo."
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "stress-alert-\(Int(now))", content: content, trigger: nil))
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
