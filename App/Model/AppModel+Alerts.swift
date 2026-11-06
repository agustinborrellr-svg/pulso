import Foundation
import PulsoStore
import PulsoAnalytics
import PulsoFeatures

extension AppModel {
    private var sentKey: String { "alerts.sent" }
    private var scheduledKey: String { "alerts.scheduled" }

    var sentAlerts: Set<String> { Set(db.get([String].self, for: sentKey) ?? []) }

    func markAlertSent(_ id: String) {
        var list = db.get([String].self, for: sentKey) ?? []
        guard !list.contains(id) else { return }
        list.append(id)
        if list.count > 800 { list.removeFirst(list.count - 800) }
        try? db.set(list, for: sentKey)
    }

    /// Runs the alert rules and delivers / schedules the result. Throttled unless `force`.
    func evaluateAlerts(force: Bool) {
        if !force, let last = lastAlertEvaluation, Date().timeIntervalSince(last) < 120 { return }
        lastAlertEvaluation = Date()
        let now = Int(Date().timeIntervalSince1970)
        let recent = alertPrefs.isOn(.inactivity) ? ((try? db.samples(from: now - 2 * 3600, to: now)) ?? []) : []
        let ctx = AlertContext(now: now, days: Array(days.suffix(60)), profile: profile, battery: battery, charging: charging,
                               lastSync: lastSync.map { Int($0.timeIntervalSince1970) },
                               offWristSince: offWristSince.map { Int($0.timeIntervalSince1970) },
                               nextWake: nextWakeDate.map { Int($0.timeIntervalSince1970) }, recentSamples: recent)
        var scheduled = db.get([String: Int].self, for: scheduledKey) ?? [:]
        let planned = AlertEngine.evaluate(ctx, prefs: alertPrefs, sent: sentAlerts)
        for a in planned {
            let due = (a.fireAt ?? now) <= now + 1
            if due {
                // Already handed to iOS for this time: it has (or is about to) show it.
                if let at = scheduled[a.id], at <= now + 1 {
                    markAlertSent(a.id)
                    scheduled[a.id] = nil
                    continue
                }
                // The hourly stress notice and Live's stress alert share one quiet hour: whichever fires first
                // silences the other, so the strap never taps twice for the same stretch of stress.
                if a.kind == .stress {
                    if let last = lastStressAlert, Double(now) - last < StressAlert.quietHours * 3600 {
                        markAlertSent(a.id)
                        continue
                    }
                    noteStressAlert(at: Double(now))
                }
                NotificationService.shared.deliver(PlannedAlert(id: a.id, kind: a.kind, title: a.title, body: a.body, fireAt: nil,
                                                                buzzStrap: a.buzzStrap, timeSensitive: a.timeSensitive))
                markAlertSent(a.id)
                scheduled[a.id] = nil
                if a.buzzStrap { strap.buzz(loops: 1) }
            } else if scheduled[a.id] != a.fireAt {
                NotificationService.shared.deliver(a) // same id replaces the pending request
                scheduled[a.id] = a.fireAt
            }
        }
        // Forget old schedule entries.
        scheduled = scheduled.filter { $0.value > now - 86400 }
        try? db.set(scheduled, for: scheduledKey)
    }
}
