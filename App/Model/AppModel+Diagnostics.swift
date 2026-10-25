import Foundation
import UIKit
import PulsoStore

extension AppModel {
    /// A text file with everything needed to understand a connection problem: app / iOS / iPhone
    /// versions, strap identity and state, handshake mode, frame counters and the connection log.
    /// Contains no health data and no passwords.
    func diagnosticsReport(_ done: @escaping (URL?) -> Void) {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = "\(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))"
        var sys = utsname()
        uname(&sys)
        let machine = withUnsafePointer(to: &sys.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        let header = [
            "Pulso — diagnóstico",
            "Fecha: \(ISO8601DateFormatter().string(from: Date()))",
            "App: \(version)",
            "iOS: \(UIDevice.current.systemVersion) · iPhone: \(machine)",
            "Última sincronización: \(lastSync.map { ISO8601DateFormatter().string(from: $0) } ?? "nunca")",
            "Segundos guardados: \(rawSampleCount)",
            "Batería: \(battery.map { "\(Int($0)) %" } ?? "–") · cargando: \(charging.map { $0 ? "sí" : "no" } ?? "–")",
        ]
        let log = self.log
        strap.diagnostics { strapInfo in
            let text = (header + ["", "— Pulsera —", strapInfo, "", "— Registro de conexión —"] + log).joined(separator: "\n") + "\n"
            let f = DateFormatter()
            f.dateFormat = "yyyyMMdd-HHmm"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("pulso-diagnostico-\(f.string(from: Date())).txt")
            done((try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil)
        }
    }
}
