import Foundation
import PulsoStore

/// Decides, minute by minute inside a wake window, whether now is a good moment to wake the wearer.
///
/// During the window the app pulls the latest seconds off the strap every couple of minutes (the
/// offload runs ~200× real time) and asks this engine. It wakes on the signs of light sleep or a
/// natural arousal — body movement, the strap's own "awake" flag, heart rate climbing above the
/// night's floor with more beat-to-beat variability (REM / transition) — and always by the end
/// of the window.
public enum SmartWake {
    public enum Mode: Equatable, Sendable {
        /// Any time in [earliest, latest] when sleep looks light.
        case window
        /// As soon as `needMinutes` of sleep are done (and sleep looks light), within [earliest, latest].
        case sleepGoal(needMinutes: Double)
    }

    public enum Action: Equatable { case wait, wake }

    public struct Decision: Equatable {
        public var action: Action
        public var reason: String
        /// 0…1: how light sleep looks right now.
        public var lightness: Double
    }

    public struct Input {
        public var now: Int
        public var earliest: Int
        public var latest: Int
        public var mode: Mode
        /// Seconds from at least the last ~15 minutes (more is better: the night's floor is learnt from them).
        public var samples: [Sample]
        /// Detected sleep onset tonight, if known.
        public var sleepOnset: Int?

        public init(now: Int, earliest: Int, latest: Int, mode: Mode, samples: [Sample], sleepOnset: Int? = nil) {
            self.now = now
            self.earliest = earliest
            self.latest = latest
            self.mode = mode
            self.samples = samples
            self.sleepOnset = sleepOnset
        }
    }

    /// How light sleep looks over the last few minutes, with the reasons.
    public static func lightness(samples: [Sample], now: Int) -> (score: Double, reasons: [String]) {
        let epochs = Epochs.minutes(Epochs.slice(samples, from: now - 3600, to: now), from: now - 3600, to: now)
        let worn = epochs.filter { $0.worn }
        guard worn.count >= 5 else { return (0, []) }
        let recent = Array(epochs.suffix(4)).filter { $0.worn }
        guard !recent.isEmpty else { return (0, []) }
        let thr = SleepDetector.stillThreshold(worn)
        var score = 0.0
        var reasons: [String] = []

        // One restless minute is a normal toss; it should not reach the wake threshold on its own.
        let moving = recent.filter { ($0.motion ?? 0) > thr * 3 || $0.posture > 0.3 }.count
        if moving >= 1 {
            score += moving >= 2 ? 0.6 : 0.2
            reasons.append("movimiento")
        }
        if let wakeFrac = Stats.mean(recent.map { $0.strapWakeFraction }), wakeFrac >= 0.5 {
            score += 0.5
            reasons.append("la pulsera te detecta despierto")
        }
        // Heart rate vs. the night's floor (10th percentile of the last hour's minutes).
        let hrs = worn.compactMap { $0.hr }
        if let floor = Stats.percentile(hrs, 10), let current = Stats.mean(recent.compactMap { $0.hr }), floor > 0 {
            let rise = current / floor - 1
            if rise >= 0.12 {
                score += 0.35
                reasons.append("pulso subiendo")
            } else if rise >= 0.07 {
                score += 0.2
                reasons.append("pulso algo más alto")
            }
        }
        // Irregular HR (REM / transitions) vs. the hour's typical minute-SD.
        let sds = worn.compactMap { $0.hrSD }
        if let typical = Stats.median(sds), let cur = Stats.mean(recent.compactMap { $0.hrSD }), typical > 0, cur >= typical * 1.6 {
            score += 0.2
            reasons.append("ritmo irregular (sueño REM o ligero)")
        }
        return (min(1, score), reasons)
    }

    public static func decide(_ input: Input) -> Decision {
        if input.now >= input.latest {
            return Decision(action: .wake, reason: "Final de la ventana de despertar", lightness: 0)
        }
        if input.now < input.earliest {
            return Decision(action: .wait, reason: "Aún no ha empezado la ventana", lightness: 0)
        }
        let (light, reasons) = lightness(samples: input.samples, now: input.now)
        let why = reasons.isEmpty ? "" : ": " + reasons.joined(separator: ", ")
        switch input.mode {
        case .window:
            if light >= 0.45 {
                return Decision(action: .wake, reason: "Sueño ligero detectado" + why, lightness: light)
            }
            return Decision(action: .wait, reason: "Sueño profundo; espero un momento mejor", lightness: light)
        case .sleepGoal(let need):
            guard let onset = input.sleepOnset else {
                // Unknown onset: behave like a plain smart window.
                return light >= 0.45
                    ? Decision(action: .wake, reason: "Sueño ligero detectado" + why, lightness: light)
                    : Decision(action: .wait, reason: "Esperando sueño ligero", lightness: light)
            }
            let slept = Double(input.now - onset) / 60
            if slept < need {
                return Decision(action: .wait, reason: "Llevas \(Int(slept / 60)) h \(Int(slept.truncatingRemainder(dividingBy: 60))) min; necesitas \(Int(need / 60)) h \(Int(need.truncatingRemainder(dividingBy: 60))) min", lightness: light)
            }
            // Goal reached: wake on light sleep, or anyway 20 minutes after the goal.
            if light >= 0.45 || slept >= need + 20 {
                return Decision(action: .wake, reason: "Has dormido lo que necesitabas" + why, lightness: light)
            }
            return Decision(action: .wait, reason: "Objetivo cumplido; espero sueño ligero", lightness: light)
        }
    }

    /// Sleep onset tonight from the seconds available (first sustained still + low-HR block in the
    /// last 14 hours), or nil.
    public static func onset(samples: [Sample], now: Int) -> Int? {
        let from = now - 14 * 3600
        let epochs = Epochs.minutes(Epochs.slice(samples, from: from, to: now), from: from, to: now)
        guard epochs.filter({ $0.worn }).count >= 60 else { return nil }
        let blocks = SleepDetector.blocks(epochs).filter { $0.length >= 30 }
        guard let first = blocks.first(where: { epochs[$0.endIndex].ts >= now - 3 * 3600 }) ?? blocks.last else { return nil }
        return epochs[first.startIndex].ts
    }
}
