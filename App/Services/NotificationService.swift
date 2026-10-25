import Foundation
import UserNotifications
import PulsoFeatures

/// Local notifications: delivers / schedules the alert engine's output, the alarm categories with
/// snooze / stop buttons, and the iPhone alarm backup when AlarmKit isn't available.
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    enum Category {
        static let alarm = "PULSO_ALARM"
        static let alert = "PULSO_ALERT"
        static let breathe = "PULSO_BREATHE"
    }

    enum Action {
        static let snooze = "SNOOZE"
        static let stop = "STOP"
        static let breathe = "BREATHE"
    }

    /// (actionIdentifier, categoryIdentifier, request identifier) — called on the main queue.
    var onAction: ((String, String, String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    func setup() {
        center.delegate = self
        let snooze = UNNotificationAction(identifier: Action.snooze, title: "Posponer", options: [])
        let stop = UNNotificationAction(identifier: Action.stop, title: "Apagar", options: [.destructive])
        let breathe = UNNotificationAction(identifier: Action.breathe, title: "Respirar 1 min", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.alarm, actions: [snooze, stop], intentIdentifiers: [], options: [.customDismissAction]),
            UNNotificationCategory(identifier: Category.alert, actions: [], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Category.breathe, actions: [breathe], intentIdentifiers: [], options: []),
        ])
    }

    func requestAuthorization(_ done: ((Bool) -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { done?(granted) }
        }
    }

    // MARK: Alerts

    func deliver(_ alert: PlannedAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        content.threadIdentifier = alert.kind.rawValue
        content.categoryIdentifier = alert.kind == .stress ? Category.breathe : Category.alert
        content.interruptionLevel = alert.timeSensitive ? .timeSensitive : .active
        var trigger: UNNotificationTrigger?
        if let at = alert.fireAt {
            let delay = TimeInterval(at) - Date().timeIntervalSince1970
            if delay > 1 { trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false) }
        }
        center.add(UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger))
    }

    /// Removes pending (not yet shown) requests whose identifier starts with `prefix`.
    func cancelPending(prefix: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map { $0.identifier }.filter { $0.hasPrefix(prefix) }
            self.center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    /// Ids of pending requests (to avoid rescheduling the same thing over and over).
    func pendingIDs(_ done: @escaping (Set<String>) -> Void) {
        center.getPendingNotificationRequests { r in
            let ids = Set(r.map { $0.identifier })
            DispatchQueue.main.async { done(ids) }
        }
    }

    /// Immediate notification (alarm banners, confirmations).
    func now(_ title: String, _ body: String, id: String = UUID().uuidString, category: String = Category.alert,
             timeSensitive: Bool = false, sound: Bool = true) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.interruptionLevel = timeSensitive ? .timeSensitive : .active
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // MARK: Alarm backup (fallback when AlarmKit isn't available)

    /// A burst of loud notifications, one a minute, starting at `date`.
    func scheduleAlarmBurst(at date: Date, title: String, count: Int = 5) {
        cancelPending(prefix: "pulso.backup.")
        for i in 0..<count {
            let fire = date.addingTimeInterval(Double(i) * 60)
            let delay = fire.timeIntervalSinceNow
            guard delay > 1 else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = i == 0 ? "¡Arriba! Toca para apagar o posponer." : "Sigue sonando (\(i + 1)/\(count))"
            content.sound = .default
            content.categoryIdentifier = Category.alarm
            content.interruptionLevel = .timeSensitive
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            center.add(UNNotificationRequest(identifier: "pulso.backup.\(i)", content: content, trigger: trigger))
        }
    }

    func cancelAlarmBurst() {
        cancelPending(prefix: "pulso.backup.")
        center.getDeliveredNotifications { list in
            let ids = list.map { $0.request.identifier }.filter { $0.hasPrefix("pulso.backup.") }
            self.center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    // MARK: Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let category = response.notification.request.content.categoryIdentifier
        let id = response.notification.request.identifier
        DispatchQueue.main.async {
            self.onAction?(action, category, id)
            completionHandler()
        }
    }
}
