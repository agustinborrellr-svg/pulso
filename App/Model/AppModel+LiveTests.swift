import Foundation
import PulsoStore
import PulsoAnalytics

/// One heart-rate reading of the live stream (unix seconds).
struct HRSample: Equatable {
    var t: Double
    var hr: Double
}

/// A live test or breathing session in progress. It lives in the model so it keeps running while you move
/// around the app; the screens only draw it.
struct LiveRun: Identifiable {
    enum Kind: String, CaseIterable {
        case scan, orthostatic, recovery, maxHR, breathing

        var title: String {
            switch self {
            case .scan: return "Escaneo"
            case .orthostatic: return "Test ortostático"
            case .recovery: return "Recuperación FC"
            case .maxHR: return "FC máxima"
            case .breathing: return "Respiración"
            }
        }
    }

    enum Phase: String {
        case measuring, prepare, lying, standUp, standing, effort, recovering, breathing

        var title: String {
            switch self {
            case .measuring: return "Midiendo"
            case .prepare: return "Preparación"
            case .lying: return "Tumbado"
            case .standUp: return "Levántate"
            case .standing: return "De pie"
            case .effort: return "Esfuerzo"
            case .recovering: return "Recuperando"
            case .breathing: return "Respirando"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let started: Date
    var phase: Phase
    var phaseStart: Date
    /// Planned length of the phase; nil = until you tap.
    var phaseSeconds: Double?
    var extended = false
    var standAt: Date?
    var stopAt: Date?
    var beats: [LiveMetrics.Beat] = []
    var samples: [HRSample] = []
    /// Best 5-second average so far (max HR test).
    var peak: Double?
    // Breathing
    var pace = 6.0
    var paceAnchor: Date
    var minutes = 5
    var coherence: LiveMetrics.Coherence?
    var scores: [HRSample] = []
    var lastCoherenceAt = Date.distantPast

    func remaining(at now: Date) -> Double? {
        guard let s = phaseSeconds else { return nil }
        return max(0, s - now.timeIntervalSince(phaseStart))
    }

    func beatsInPhase() -> Int {
        let a = phaseStart.timeIntervalSince1970
        return beats.reduce(0) { $0 + ($1.t >= a ? 1 : 0) }
    }

    func samplesInPhase() -> Int {
        let a = phaseStart.timeIntervalSince1970
        return samples.reduce(0) { $0 + ($1.t >= a ? 1 : 0) }
    }

    /// Pulse arriving but no R-R intervals in this phase (the strap sends bpm only).
    var phaseLacksRR: Bool { samplesInPhase() >= 15 && beatsInPhase() == 0 }
}

/// A finished breathing session (kv `live.breathing`).
struct BreathingRecord: Codable, Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var seconds: Double
    var pace: Double
    var rmssdBefore: Double?
    var beforeIsFirstMinute: Bool
    var rmssdAfter: Double?
    var coherenceStart: Double?
    var coherenceEnd: Double?
    var coherenceMean: Double?
    var beats: Int
    var scores: [Double]
}

enum LiveOutcome {
    case scan(LiveMetrics.Scan)
    case orthostatic(LiveMetrics.Orthostatic)
    case recovery(LiveMetrics.Recovery)
    case maxHR(Double)
    case breathing(BreathingRecord)
    case failed(String)
}

struct LiveLab {
    var run: LiveRun?
    var outcomes: [LiveRun.Kind: LiveOutcome] = [:]

    func running(_ kind: LiveRun.Kind) -> LiveRun? { run?.kind == kind ? run : nil }
}

extension AppModel {
    static let orthoPrepare = 15.0, orthoLying = 120.0, orthoStandUp = 5.0, orthoStanding = 180.0
    static let scanSeconds = 60.0, scanMaxSeconds = 90.0, recoverySeconds = 125.0

    func startLiveTest(_ kind: LiveRun.Kind, pace: Double = 6, minutes: Int = 5) {
        guard liveLab.run == nil else { return }
        let now = Date()
        var run = LiveRun(kind: kind, started: now, phase: .measuring, phaseStart: now, paceAnchor: now)
        switch kind {
        case .scan: run.phaseSeconds = Self.scanSeconds
        case .orthostatic:
            run.phase = .prepare
            run.phaseSeconds = Self.orthoPrepare
        case .recovery, .maxHR: run.phase = .effort
        case .breathing:
            run.phase = .breathing
            run.pace = pace
            run.minutes = minutes
            run.phaseSeconds = Double(minutes * 60)
            // The minute and a half before starting is the "before" of the session.
            run.beats = beats(since: now.addingTimeInterval(-90))
        }
        liveLab.outcomes[kind] = nil
        liveLab.run = run
        setLive(true, client: "live-test")
        let id = run.id
        Task { [weak self] in
            while let self, self.liveLab.run?.id == id {
                self.liveRunStep(Date())
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    func cancelLiveTest() {
        liveLab.run = nil
        setLive(false, client: "live-test")
    }

    /// Recovery test: "He parado".
    func markLiveStop() {
        guard var r = liveLab.run, r.kind == .recovery, r.phase == .effort else { return }
        let now = Date()
        r.stopAt = now
        r.phase = .recovering
        r.phaseStart = now
        r.phaseSeconds = Self.recoverySeconds
        liveLab.run = r
    }

    /// Max HR test "Terminar" and breathing "Terminar ya".
    func finishLiveTestNow() {
        guard let r = liveLab.run else { return }
        switch r.kind {
        case .maxHR, .breathing: finish(r, at: Date())
        default: break
        }
    }

    func setBreathingPace(_ pace: Double) {
        guard var r = liveLab.run, r.kind == .breathing else { return }
        r.pace = min(8, max(4.5, pace))
        r.paceAnchor = Date()
        liveLab.run = r
    }

    var breathingSessions: [BreathingRecord] { db.get([BreathingRecord].self, for: "live.breathing") ?? [] }

    // MARK: Engine

    func liveRunStep(_ now: Date) {
        guard var r = liveLab.run else { return }
        collect(into: &r)
        let el = now.timeIntervalSince(r.phaseStart)
        switch r.kind {
        case .scan:
            guard el >= Self.scanSeconds else { break }
            if el >= Self.scanMaxSeconds || LiveMetrics.scan(r.beats, baseline: liveBaseline) != nil {
                return finish(r, at: now)
            }
            // Not enough clean beats yet: up to 30 s more instead of failing at a fixed minute.
            r.extended = true
            r.phaseSeconds = Self.scanMaxSeconds
        case .orthostatic:
            guard let len = r.phaseSeconds, el >= len else { break }
            switch r.phase {
            case .prepare:
                r.phase = .lying
                r.phaseStart = now
                r.phaseSeconds = Self.orthoLying
                strap.buzz(loops: 1)
            case .lying:
                r.phase = .standUp
                r.phaseStart = now
                r.standAt = now
                r.phaseSeconds = Self.orthoStandUp
                strap.buzz(loops: 2)
                if settings.voiceCues { voice.say("Levántate") }
            case .standUp:
                r.phase = .standing
                r.phaseStart = now
                r.phaseSeconds = Self.orthoStanding - Self.orthoStandUp
            default:
                return finish(r, at: now)
            }
        case .recovery:
            if r.phase == .recovering, el >= Self.recoverySeconds { return finish(r, at: now) }
        case .breathing:
            if now.timeIntervalSince(r.lastCoherenceAt) >= 5 {
                r.lastCoherenceAt = now
                r.coherence = LiveMetrics.coherence(r.beats.filter { $0.t >= r.started.timeIntervalSince1970 })
                if let c = r.coherence { r.scores.append(HRSample(t: now.timeIntervalSince1970, hr: Double(c.score))) }
            }
            if el >= (r.phaseSeconds ?? 0) { return finish(r, at: now) }
        case .maxHR:
            break
        }
        liveLab.run = r
    }

    /// Every beat and every heart-rate reading since the last step (not only when the number on screen changes).
    private func collect(into r: inout LiveRun) {
        let lastBeat = r.beats.last?.t ?? r.started.timeIntervalSince1970
        r.beats += liveBeats.filter { $0.t > lastBeat }
        let lastSample = r.samples.last?.t ?? r.started.timeIntervalSince1970
        for p in livePoints where p.date.timeIntervalSince1970 > lastSample {
            r.samples.append(HRSample(t: p.date.timeIntervalSince1970, hr: Double(p.hr)))
            if r.kind == .maxHR, let p5 = LiveMetrics.peakHR(r.samples.suffix(5).map { (t: $0.t, hr: $0.hr) }) {
                r.peak = max(r.peak ?? 0, p5)
            }
        }
        let keep = Date().timeIntervalSince1970 - 2 * 3600
        if let f = r.beats.first, f.t < keep { r.beats.removeAll { $0.t < keep } }
        if let f = r.samples.first, f.t < keep { r.samples.removeAll { $0.t < keep } }
    }

    private func finish(_ r: LiveRun, at now: Date) {
        liveLab.run = nil
        setLive(false, client: "live-test")
        let outcome = outcome(of: r, at: now)
        liveLab.outcomes[r.kind] = outcome
        if case .failed = outcome {} else { strap.buzz(loops: 1) }
    }

    private func outcome(of r: LiveRun, at now: Date) -> LiveOutcome {
        switch r.kind {
        case .scan:
            guard let s = LiveMetrics.scan(r.beats, baseline: liveBaseline) else {
                if r.beats.isEmpty && !r.samples.isEmpty {
                    return .failed("Tu pulsera está enviando pulso sin intervalos R-R: sin ellos no se puede medir la VFC ni el estrés.")
                }
                return .failed("En \(Int(now.timeIntervalSince(r.started))) s llegaron \(r.beats.count) latidos con intervalo R-R (hacen falta 40 limpios). Ajusta la pulsera un dedo por encima del hueso de la muñeca y repite.")
            }
            saveLiveTest(LiveTestRecord(date: now, kind: .scan, value: Double(s.state ?? 0), hr: s.hr, rmssd: s.rmssd,
                                        resp: s.respRate, stress: s.stress, detail: s.label))
            return .scan(s)
        case .orthostatic:
            guard let at = r.standAt?.timeIntervalSince1970 else { return .failed("El test no llegó a la fase de pie.") }
            guard let o = LiveMetrics.orthostatic(r.beats, standAt: at) else {
                return .failed(LiveMetrics.orthostaticCoverage(r.beats, standAt: at).problem
                               ?? "No se pudo calcular con los latidos recibidos.")
            }
            saveLiveTest(LiveTestRecord(date: now, kind: .orthostatic, value: o.rise.rounded(), hr: o.standingHR,
                                        rmssd: o.standingRMSSD, detail: "\(Int(o.lyingHR))→\(Int(o.standingHR)) lpm"))
            return .orthostatic(o)
        case .recovery:
            guard let stop = r.stopAt?.timeIntervalSince1970 else { return .failed("No marcaste cuándo paraste.") }
            let s = r.samples.map { (t: $0.t, hr: $0.hr) }
            guard let rec = LiveMetrics.recovery(s, stopAt: stop) else {
                return .failed(LiveMetrics.recoveryProblem(s, stopAt: stop) ?? "No se pudo calcular con el pulso recibido.")
            }
            saveLiveTest(LiveTestRecord(date: now, kind: .recovery, value: rec.drop60.rounded(), hr: rec.peakHR, detail: rec.level))
            return .recovery(rec)
        case .maxHR:
            guard let p = r.peak else { return .failed("No llegó pulso durante el test.") }
            saveLiveTest(LiveTestRecord(date: now, kind: .maxHR, value: p.rounded(), hr: p, detail: "test"))
            return .maxHR(p)
        case .breathing:
            let start = r.started.timeIntervalSince1970, end = now.timeIntervalSince1970
            let b = LiveMetrics.breathing(r.beats, start: start, end: end, scores: r.scores.map { (t: $0.t, score: $0.hr) })
            let rec = BreathingRecord(date: now, seconds: end - start, pace: r.pace, rmssdBefore: b.rmssdBefore,
                                      beforeIsFirstMinute: b.beforeIsFirstMinute, rmssdAfter: b.rmssdAfter,
                                      coherenceStart: b.coherenceStart, coherenceEnd: b.coherenceEnd,
                                      coherenceMean: b.coherenceMean, beats: b.beats, scores: r.scores.map(\.hr))
            if end - start >= 30 {
                try? db.set(Array((breathingSessions + [rec]).suffix(300)), for: "live.breathing")
            }
            return .breathing(rec)
        }
    }
}
