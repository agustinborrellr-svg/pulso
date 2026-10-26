import Foundation
import PulsoAnalytics

/// One block of a structured workout.
public struct IntervalStep: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case warmup, work, recover, cooldown

        public var label: String {
            switch self {
            case .warmup: return "Calentamiento"
            case .work: return "Trabajo"
            case .recover: return "Recuperación"
            case .cooldown: return "Vuelta a la calma"
            }
        }
    }

    public var kind: Kind
    public var seconds: Int
    /// Target heart-rate zone range (1…5); nil = no zone alerts.
    public var zoneLow: Int?
    public var zoneHigh: Int?

    public init(_ kind: Kind, seconds: Int, zones: ClosedRange<Int>? = nil) {
        self.kind = kind
        self.seconds = seconds
        self.zoneLow = zones?.lowerBound
        self.zoneHigh = zones?.upperBound
    }

    public var zoneText: String? {
        guard let lo = zoneLow, let hi = zoneHigh else { return nil }
        return lo == hi ? "Zona \(lo)" : "Zonas \(lo)–\(hi)"
    }
}

public struct IntervalPlan: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var detail: String
    public var steps: [IntervalStep]

    public init(id: String, name: String, detail: String, steps: [IntervalStep]) {
        self.id = id
        self.name = name
        self.detail = detail
        self.steps = steps
    }

    public var totalSeconds: Int { steps.reduce(0) { $0 + $1.seconds } }

    static func repeated(_ n: Int, _ block: [IntervalStep]) -> [IntervalStep] {
        (0..<n).flatMap { _ in block }
    }

    public static let presets: [IntervalPlan] = [
        IntervalPlan(id: "norwegian4x4", name: "4×4 noruego", detail: "4 series de 4 min fuertes con 3 min suaves. Clásico para subir el VO₂máx.",
                     steps: [IntervalStep(.warmup, seconds: 600, zones: 1...2)]
                        + repeated(4, [IntervalStep(.work, seconds: 240, zones: 4...5), IntervalStep(.recover, seconds: 180, zones: 1...2)])
                        + [IntervalStep(.cooldown, seconds: 300, zones: 1...2)]),
        IntervalPlan(id: "30-30", name: "30/30", detail: "10 × (30 s rápido + 30 s suave).",
                     steps: [IntervalStep(.warmup, seconds: 480, zones: 1...2)]
                        + repeated(10, [IntervalStep(.work, seconds: 30, zones: 4...5), IntervalStep(.recover, seconds: 30)])
                        + [IntervalStep(.cooldown, seconds: 300, zones: 1...2)]),
        IntervalPlan(id: "tabata", name: "Tabata", detail: "8 × (20 s a tope + 10 s descanso).",
                     steps: [IntervalStep(.warmup, seconds: 300, zones: 1...2)]
                        + repeated(8, [IntervalStep(.work, seconds: 20), IntervalStep(.recover, seconds: 10)])
                        + [IntervalStep(.cooldown, seconds: 240)]),
        IntervalPlan(id: "pyramid", name: "Pirámide", detail: "1-2-3-2-1 min fuertes con la mitad de recuperación.",
                     steps: [IntervalStep(.warmup, seconds: 600, zones: 1...2)]
                        + [60, 120, 180, 120, 60].flatMap { [IntervalStep(.work, seconds: $0, zones: 4...5), IntervalStep(.recover, seconds: $0 / 2, zones: 1...2)] }
                        + [IntervalStep(.cooldown, seconds: 300, zones: 1...2)]),
        IntervalPlan(id: "zone2", name: "Zona 2 · 45 min", detail: "Rodaje aeróbico: la pulsera avisa si te sales de la zona 2.",
                     steps: [IntervalStep(.warmup, seconds: 300, zones: 1...2), IntervalStep(.work, seconds: 2700, zones: 2...2),
                             IntervalStep(.cooldown, seconds: 300, zones: 1...2)]),
        IntervalPlan(id: "tempo", name: "Tempo 3 × 8", detail: "3 × 8 min en zona 3–4 con 2 min suaves.",
                     steps: [IntervalStep(.warmup, seconds: 600, zones: 1...2)]
                        + repeated(3, [IntervalStep(.work, seconds: 480, zones: 3...4), IntervalStep(.recover, seconds: 120, zones: 1...2)])
                        + [IntervalStep(.cooldown, seconds: 300, zones: 1...2)]),
    ]
}

/// Plays an interval plan against live heart rate and says when to buzz / speak.
public final class IntervalRunner {
    public enum Cue: Equatable {
        case stepStarted(index: Int, step: IntervalStep)
        case countdown(secondsLeft: Int)
        case tooHigh(zone: Int)
        case tooLow(zone: Int)
        case finished

        /// Strap vibration for this cue (nil = none).
        public var buzzLoops: UInt8? {
            switch self {
            case .stepStarted(_, let s): return s.kind == .work ? 3 : 2
            case .countdown: return nil
            case .tooHigh: return 2
            case .tooLow: return 1
            case .finished: return 4
            }
        }

        /// Spoken phrase.
        public var phrase: String {
            switch self {
            case .stepStarted(_, let s):
                let mins = s.seconds / 60, secs = s.seconds % 60
                let dur = mins > 0 ? "\(mins) minuto\(mins == 1 ? "" : "s")" + (secs > 0 ? " y \(secs) segundos" : "") : "\(secs) segundos"
                return "\(s.kind.label), \(dur)" + (s.zoneText.map { ", \($0.lowercased())" } ?? "")
            case .countdown(let n): return "\(n)"
            case .tooHigh: return "Baja el ritmo"
            case .tooLow: return "Sube el ritmo"
            case .finished: return "Entreno completado"
            }
        }
    }

    public let plan: IntervalPlan
    public let start: Int
    public private(set) var index = -1
    public private(set) var done = false
    private var lastZoneCue = 0
    private var outOfZoneSince: Int?
    private var lastCountdown: Int?
    /// Seconds out of zone before warning, and minimum gap between warnings.
    public var zoneGrace = 15
    public var zoneCueGap = 45

    public init(plan: IntervalPlan, start: Int) {
        self.plan = plan
        self.start = start
    }

    /// (step index, seconds into it) at `now`; index == steps.count when finished.
    public func position(at now: Int) -> (index: Int, elapsed: Int, remaining: Int) {
        var t = max(0, now - start)
        for (i, s) in plan.steps.enumerated() {
            if t < s.seconds { return (i, t, s.seconds - t) }
            t -= s.seconds
        }
        return (plan.steps.count, 0, 0)
    }

    public func tick(now: Int, heartRate: Double?, model: HeartRateModel) -> [Cue] {
        guard !done else { return [] }
        var cues: [Cue] = []
        let pos = position(at: now)
        if pos.index >= plan.steps.count {
            done = true
            return [.finished]
        }
        if pos.index != index {
            index = pos.index
            outOfZoneSince = nil
            lastCountdown = nil
            cues.append(.stepStarted(index: index, step: plan.steps[index]))
        }
        let step = plan.steps[index]
        if step.seconds >= 20, pos.remaining <= 3, pos.remaining >= 1, lastCountdown != pos.remaining {
            lastCountdown = pos.remaining
            cues.append(.countdown(secondsLeft: pos.remaining))
        }
        // Zone guidance, skipping the start of a step because HR lags: 30 s on long steps, a third of
        // the step on short ones so 30/30 and Tabata work steps can still get a cue.
        let zoneLag = min(30, max(5, step.seconds / 3))
        if let lo = step.zoneLow, let hi = step.zoneHigh, let hr = heartRate, pos.elapsed >= zoneLag {
            let z = model.zone(hr)
            if z > hi || z < lo {
                let since = outOfZoneSince ?? now
                outOfZoneSince = since
                if now - since >= zoneGrace, now - lastZoneCue >= zoneCueGap {
                    lastZoneCue = now
                    cues.append(z > hi ? .tooHigh(zone: z) : .tooLow(zone: z))
                }
            } else {
                outOfZoneSince = nil
            }
        }
        return cues
    }
}
