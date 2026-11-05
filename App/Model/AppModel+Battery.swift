import Foundation
import PulsoFeatures

/// The strap's battery over time (kv `battery.log`), to show how long a charge lasts and what the live stream costs.
extension AppModel {
    static let batteryLogKey = "battery.log"

    var batteryLog: [BatteryLog.Point] { db.get([BatteryLog.Point].self, for: Self.batteryLogKey) ?? [] }

    func logBattery(_ pct: Double, live: Bool) {
        guard !AppMode.screenshots else { return }
        let log = batteryLog
        let next = BatteryLog.append(.init(t: Int(Date().timeIntervalSince1970), pct: pct, live: live), to: log)
        if next != log { try? db.set(next, for: Self.batteryLogKey) }
    }

    var batteryDrain: BatteryLog.Drain? { BatteryLog.drain(batteryLog) }
}
