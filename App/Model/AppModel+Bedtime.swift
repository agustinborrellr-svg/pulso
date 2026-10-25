import Foundation
import PulsoStore

extension AppModel {
    /// Logs the moment, keeps the strap connected for tonight's alarm and syncs now so the morning
    /// download is short.
    func goToSleep() {
        try? db.insertEvent(StoredEvent(ts: Int(Date().timeIntervalSince1970), kind: EventKind.bedtime, value: nil))
        refreshAlarmSchedule()
        updateNightGuard()
        strap.sync(force: true)
        if let next = nextAlarm {
            NotificationService.shared.now("Buenas noches", "Alarma \(next.isSmart ? "entre las \(Fmt.clock(next.earliest)) y las \(Fmt.clock(next.latest))" : "a las \(Fmt.clock(next.latest))").",
                                           id: "pulso.goodnight", sound: false)
        }
        appendLog("Me voy a dormir")
    }

    /// Show the bedtime card from the evening until well past midnight.
    var isEvening: Bool {
        let h = Calendar.current.component(.hour, from: Date())
        return h >= 20 || h < 3
    }
}
