import Foundation
import WhoopProtocol
import PulsoStore
import PulsoECG

extension AppModel {
    /// The connected strap can record ECGs (an MG whose ECG stream layout is known).
    var ecgAvailable: Bool { identity.isMG && mgDecoder.isConfigured }

    /// Starts a 30-second recording. `simulated` runs the full flow with synthetic data (demo / testing).
    func startECG(simulated: Bool) {
        guard ecgSession == nil else { return }
        let rate = simulated ? 512 : mgDecoder.sampleRate
        guard rate > 0 else {
            errorMessage = "Tu pulsera no puede hacer electrocardiogramas. Hace falta una Pulse Band MG (y que se conozca su protocolo de ECG)."
            return
        }
        let session = ECGSessionBuilder(start: Int(Date().timeIntervalSince1970), sampleRate: rate, targetSeconds: 30)
        ecgSession = session
        ecgProgress = 0
        if simulated {
            let sim = ECGSimulator(rate: rate, seconds: 30, heartRate: 66, pattern: .sinus,
                                   seed: UInt64(Date().timeIntervalSince1970))
            ecgSimulatedSamples = sim.generate()
            ecgSimulatedStart = Date()
        } else {
            setLive(true, client: "ecg")
        }
    }

    func cancelECG() {
        ecgSession = nil
        ecgSimulatedSamples = nil
        setLive(false, client: "ecg")
    }

    /// Feeds simulated samples in real time (called from the 1 Hz tick via `ecgTick`).
    func ecgTick(now: Date) {
        guard let s = ecgSession else { return }
        if let all = ecgSimulatedSamples, let start = ecgSimulatedStart {
            let due = min(all.count, Int(now.timeIntervalSince(start) * s.sampleRate))
            let have = s.samples.count
            if due > have { s.append(Array(all[have..<due])) }
        }
        ecgProgress = s.progress
        if s.isComplete { finishECG(source: ecgSimulatedSamples != nil ? .simulated : .whoopMG) }
    }

    func handleECGFrame(_ frame: Frame) {
        guard let s = ecgSession, ecgSimulatedSamples == nil else { return }
        let v = mgDecoder.decode(frame)
        guard !v.isEmpty else { return }
        s.append(v)
        ecgProgress = s.progress
        if s.isComplete { finishECG(source: .whoopMG) }
    }

    @discardableResult
    func finishECG(source: ECGSource) -> ECGRecording? {
        guard let s = ecgSession else { return nil }
        ecgSession = nil
        ecgSimulatedSamples = nil
        setLive(false, client: "ecg")
        var (rec, _) = s.finish(source: source)
        do {
            rec.id = try db.save(rec)
        } catch {
            errorMessage = "No se pudo guardar el ECG"
            return nil
        }
        ecgRecordings = (try? db.ecgRecordings(withSamples: false)) ?? []
        lastFinishedECG = rec.id
        return rec
    }

    func deleteECG(_ rec: ECGRecording) {
        guard let id = rec.id else { return }
        try? db.deleteECG(id: id)
        ecgRecordings = (try? db.ecgRecordings(withSamples: false)) ?? []
    }

    func fullECG(_ rec: ECGRecording) -> ECGRecording? {
        guard let id = rec.id else { return nil }
        return try? db.ecgRecording(id: id)
    }

    /// PDF for the doctor.
    func ecgPDF(_ rec: ECGRecording) -> URL? {
        guard let full = fullECG(rec), full.source != .simulated else { return nil }
        let a = ECGAnalyzer.analyze(full)
        let label: String
        switch full.source {
        case .whoopMG: label = "Pulse Band MG"
        case .appleWatch: label = "Apple Watch"
        case .simulated: label = "Simulación (no es un registro real)"
        }
        let pdf = ECGReport.pdf(full, analysis: a, info: .init(name: profile.name, age: profile.age, deviceLabel: label))
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HHmm"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ECG-\(f.string(from: Date(timeIntervalSince1970: TimeInterval(full.start)))).pdf")
        return (try? Data(pdf).write(to: url)) != nil ? url : nil
    }

    /// Brings Apple Watch ECGs from Apple Health into the same history.
    func importAppleWatchECGs(since: Date = Date().addingTimeInterval(-365 * 86400)) {
        guard profile.healthKitEnabled else { return }
        health.importECGs(since: since) { [weak self] list in
            guard let self else { return }
            var added = 0
            for var rec in list where !(rec.externalID.map { (try? self.db.hasECG(externalID: $0)) ?? false } ?? false) {
                let a = ECGAnalyzer.analyze(rec)
                rec.rhythm = a.rhythm.rawValue
                rec.avgHR = a.heartRate
                if (try? self.db.save(rec)) != nil { added += 1 }
            }
            if added > 0 {
                self.ecgRecordings = (try? self.db.ecgRecordings(withSamples: false)) ?? []
                self.importStatus = "Importados \(added) ECG del Apple Watch"
            }
        }
    }
}
