import Foundation
import PulsoStore
import PulsoAnalytics
import PulsoECG

extension AppModel {
    var demoActive: Bool { DemoData.isActive(db) }

    /// Fills the app with three weeks of realistic simulated data (no strap needed).
    func loadDemo(days: Int = 35, completion: (() -> Void)? = nil) {
        guard !analyzing else { return }
        analyzing = true
        analysisProgress = 0
        let db = self.db
        analysisQueue.async {
            var failure: String?
            do {
                try DemoData.populate(db: db, days: days, progress: { p in
                    Task { @MainActor in self.analysisProgress = p }
                })
                // A simulated ECG and a couple of double-tap markers so those screens aren't empty.
                let ecgStart = Int(Date().addingTimeInterval(-3 * 3600).timeIntervalSince1970)
                var rec = ECGSimulator(heartRate: 62, pattern: .sinus, seed: 11).recording(start: ecgStart)
                let a = ECGAnalyzer.analyze(rec)
                rec.rhythm = a.rhythm.rawValue
                rec.avgHR = a.heartRate
                try db.save(rec)
                let now = Int(Date().timeIntervalSince1970)
                try db.insertEvent(StoredEvent(ts: now - 5 * 3600, kind: EventKind.marker, value: nil))
                try db.insertEvent(StoredEvent(ts: now - 2 * 3600, kind: EventKind.marker, value: nil))
            } catch {
                failure = "\(error)"
            }
            let message = failure
            Task { @MainActor in
                self.analyzing = false
                if let message { self.errorMessage = "No se pudo crear la demo: \(message)" }
                self.ecgRecordings = (try? self.db.ecgRecordings(withSamples: false)) ?? []
                self.followCurrent = true
                self.selectedDay = self.currentDayKey
                self.reload()
                self.refreshIntelligence()
                completion?()
            }
        }
    }

    /// Removes everything (the demo lives in the same database as real data).
    func clearDemo() {
        eraseEverything()
    }
}
