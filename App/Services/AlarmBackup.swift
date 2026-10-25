import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
#endif

/// The iPhone side of the alarm: if the strap's vibration doesn't wake you, the phone rings.
/// On iOS 26+ it is a real system alarm (AlarmKit: rings in silent mode and on the lock screen);
/// on older systems a burst of time-sensitive notifications.
final class AlarmBackup {
    private static let idKey = "pulso.alarmkit.id"

    var usesSystemAlarm: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        #endif
        return false
    }

    func requestAuthorization() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task { _ = await SystemAlarm.authorize() }
            return
        }
        #endif
        NotificationService.shared.requestAuthorization()
    }

    /// Replaces any previous backup with one at `date`.
    func schedule(at date: Date, title: String) {
        cancel()
        guard date > Date() else { return }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let id = UUID()
            UserDefaults.standard.set(id.uuidString, forKey: Self.idKey)
            Task {
                guard await SystemAlarm.authorize() else {
                    NotificationService.shared.scheduleAlarmBurst(at: date, title: title)
                    return
                }
                do {
                    try await SystemAlarm.schedule(id: id, at: date, title: title)
                } catch {
                    NotificationService.shared.scheduleAlarmBurst(at: date, title: title)
                }
            }
            return
        }
        #endif
        NotificationService.shared.scheduleAlarmBurst(at: date, title: title)
    }

    func cancel() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *), let s = UserDefaults.standard.string(forKey: Self.idKey), let id = UUID(uuidString: s) {
            SystemAlarm.cancel(id: id)
            UserDefaults.standard.removeObject(forKey: Self.idKey)
        }
        #endif
        NotificationService.shared.cancelAlarmBurst()
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct PulsoAlarmMetadata: AlarmMetadata {}

@available(iOS 26.0, *)
enum SystemAlarm {
    static func authorize() async -> Bool {
        switch AlarmManager.shared.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await AlarmManager.shared.requestAuthorization()) == .authorized
        @unknown default:
            return false
        }
    }

    static func schedule(id: UUID, at date: Date, title: String) async throws {
        let stop = AlarmButton(text: "Apagar", textColor: .white, systemImageName: "stop.circle")
        let alert = AlarmPresentation.Alert(title: LocalizedStringResource(stringLiteral: title), stopButton: stop)
        let attributes = AlarmAttributes<PulsoAlarmMetadata>(presentation: AlarmPresentation(alert: alert), tintColor: .green)
        let configuration = AlarmManager.AlarmConfiguration<PulsoAlarmMetadata>(schedule: .fixed(date), attributes: attributes)
        _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
    }

    static func cancel(id: UUID) {
        try? AlarmManager.shared.cancel(id: id)
    }
}
#endif
