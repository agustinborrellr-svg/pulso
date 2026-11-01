import Foundation
import UIKit
import PulsoStore
import PulsoAnalytics
import PulsoFeatures
import PulsoIntelligence
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Behaviours, cycle log, blood pressure and the extra double-tap actions.
extension AppModel {
    // MARK: Behaviours

    func behaviorReport() -> Behaviors.Report {
        let workouts = (try? db.workouts(from: 0, to: Int(Date().timeIntervalSince1970) + 86400)) ?? []
        let journal = (try? db.allJournal()) ?? []
        return Behaviors.analyze(days: days, workouts: workouts, journal: journal, label: { JournalCatalog.label($0) })
    }

    // MARK: Cycle

    var cycleStarts: [String] { db.get([String].self, for: "cycle.starts") ?? [] }

    func addCycleStart(_ day: String) {
        let all = Array(Set(cycleStarts + [day])).sorted()
        try? db.set(all, for: "cycle.starts")
        objectWillChange.send()
    }

    func removeCycleStart(_ day: String) {
        try? db.set(cycleStarts.filter { $0 != day }, for: "cycle.starts")
        objectWillChange.send()
    }

    // MARK: Blood pressure

    var bloodPressure: [BloodPressureReading] { db.get([BloodPressureReading].self, for: "bp.readings") ?? [] }

    func addBloodPressure(_ r: BloodPressureReading) {
        try? db.set(bloodPressure + [r], for: "bp.readings")
        objectWillChange.send()
    }

    func removeBloodPressure(_ r: BloodPressureReading) {
        try? db.set(bloodPressure.filter { $0 != r }, for: "bp.readings")
        objectWillChange.send()
    }

    // MARK: Double tap extras

    /// Recovery, strain and pulse, spoken (works with the screen locked while Pulso keeps the strap link).
    func speakStatus() {
        var parts: [String] = []
        if let d = today ?? days.last {
            if let r = d.recovery { parts.append("Recuperación \(Int(r)) por ciento") }
            if let s = liveDayStrain ?? d.strain { parts.append("esfuerzo \(String(format: "%.1f", s).replacingOccurrences(of: ".", with: ","))") }
        }
        if let hr = liveHR { parts.append("pulso \(hr)") }
        voice.say(parts.isEmpty ? "Aún no tengo datos de hoy" : parts.joined(separator: ", "))
    }

    /// 60 s still check started from the strap; the result is spoken and notified.
    func quickScan() {
        setLive(true, client: "tap-scan")
        strap.buzz(loops: 1)
        voice.say("Escaneando un minuto. Quédate quieto.")
        let start = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            self.setLive(false, client: "tap-scan")
            guard let r = LiveMetrics.scan(self.beats(since: start), baseline: self.liveBaseline) else {
                self.voice.say("No he recibido latidos suficientes")
                NotificationService.shared.now("Escaneo sin datos", "Ajusta la pulsera y repite.", sound: false)
                return
            }
            self.saveLiveTest(LiveTestRecord(date: Date(), kind: .scan, value: Double(r.state ?? 0), hr: r.hr, rmssd: r.rmssd,
                                             resp: r.respRate, stress: r.stress, detail: r.label))
            self.strap.buzz(loops: 2)
            let text = "\(r.label). Pulso \(Int(r.hr)), VFC \(Fmt.int(r.rmssd))"
            self.voice.say(text)
            NotificationService.shared.now("Escaneo: \(r.state.map { "\($0)" } ?? "–")", text, sound: false)
        }
    }

    /// Calls the configured address. One vibration if it worked, three if not.
    func fireTapWebhook() {
        guard let req = DoubleTapWebhook.request(url: settings.tapURL, method: settings.tapMethod, heartRate: liveHR, at: Date()) else {
            NotificationService.shared.now("Doble toque", "Configura la dirección web en Más → Doble toque.", sound: false)
            strap.buzz(loops: 3)
            return
        }
        URLSession.shared.dataTask(with: req) { [weak self] _, response, error in
            let ok = error == nil && ((response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false)
            DispatchQueue.main.async {
                self?.strap.buzz(loops: ok ? 1 : 3)
                self?.appendLog(ok ? "Doble toque: dirección web llamada" : "Doble toque: la dirección web falló \(error?.localizedDescription ?? "")")
                if !ok { NotificationService.shared.now("Doble toque", "No se pudo llamar a la dirección configurada.", sound: false) }
            }
        }.resume()
    }

    /// iOS only runs Shortcuts with Pulso in front: open it now if we are, otherwise a notification does it on tap.
    func runTapShortcut() {
        guard let url = DoubleTapWebhook.shortcutURL(name: settings.tapShortcut) else {
            NotificationService.shared.now("Doble toque", "Elige el atajo en Más → Doble toque.", sound: false)
            return
        }
        if UIApplication.shared.applicationState == .active {
            UIApplication.shared.open(url)
        } else {
            NotificationService.shared.now("Atajo «\(settings.tapShortcut)»", "Toca para ejecutarlo.", sound: true, url: url)
        }
        strap.buzz(loops: 1)
    }
}
