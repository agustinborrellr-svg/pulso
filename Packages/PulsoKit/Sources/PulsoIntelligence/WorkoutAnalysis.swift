import Foundation
import PulsoStore

/// Per-workout cardiac analysis from 1 Hz strap data (the WHOOP API only exposes coarse summaries;
/// Pulso has every second, so these can be measured instead of guessed).
public enum WorkoutAnalysis {
    public static let version = "1.0"

    public struct Recovery: Equatable, Sendable {
        /// HR at the end of the effort (mean of its last 30 s).
        public var endHR: Double
        /// Drop after 60 / 120 s (bpm).
        public var drop60: Double?
        public var drop120: Double?
        /// Exponential time constant of the first 2 minutes (s): smaller = faster.
        public var tau: Double?
        /// Minutes until HR is back within 10 % of reserve above rest (≤ 30 min observed).
        public var minutesToBaseline: Double?
        /// Curve for charts: (seconds after end, bpm), 5 s steps over 3 minutes.
        public var curve: [(t: Int, hr: Double)]

        public static func == (a: Recovery, b: Recovery) -> Bool {
            a.endHR == b.endHR && a.drop60 == b.drop60 && a.drop120 == b.drop120 && a.tau == b.tau
        }
    }

    public struct Drift: Equatable, Sendable {
        /// CDI = 100 · (HR final − HR inicial) / HR inicial over the steady part.
        public var percent: Double?
        /// Why it couldn't be computed (non-steady intensity, too short…).
        public var note: String
    }

    public struct Reserve: Equatable, Sendable {
        /// Mean and peak (best minute) share of heart-rate reserve used, 0–1.
        public var mean: Double
        public var peak: Double
        public var minutesAbove90: Double
        public var approximate: Bool
    }

    public struct Result: Equatable, Sendable {
        public var recovery: Recovery?
        public var drift: Drift
        public var reserve: Reserve?
    }

    static func meanHR(_ s: [Sample], _ a: Int, _ b: Int) -> (hr: Double, coverage: Double)? {
        let w = s.filter { $0.ts >= a && $0.ts < b }
        let hrs = w.filter { $0.worn && !$0.poor }.compactMap { $0.hr }.map(Double.init)
        guard !hrs.isEmpty else { return nil }
        return (hrs.reduce(0, +) / Double(hrs.count), Double(hrs.count) / Double(max(1, b - a)))
    }

    /// `samples` must cover the workout plus ~30 minutes after it.
    public static func analyze(workout w: Workout, samples: [Sample], restingHR: Double, maxHR: Double,
                               maxHRMeasured: Bool = false) -> Result {
        let s = samples.sorted { $0.ts < $1.ts }
        let reserveSpan = max(30, maxHR - restingHR)

        // Reserve utilisation.
        var reserve: Reserve?
        let inside = s.filter { $0.ts >= w.start && $0.ts < w.end && $0.worn }.compactMap { $0.hr }.map(Double.init)
        if inside.count >= 120 {
            let frac = inside.map { Num.clamp(($0 - restingHR) / reserveSpan, 0, 1.1) }
            var best = 0.0
            var i = 0
            while i + 60 <= frac.count {
                best = max(best, (Num.mean(Array(frac[i..<(i + 60)])) ?? 0))
                i += 15
            }
            reserve = Reserve(mean: Num.mean(frac) ?? 0, peak: best, minutesAbove90: Double(frac.filter { $0 >= 0.9 }.count) / 60,
                              approximate: !maxHRMeasured)
        }

        // Heart-rate recovery.
        var recovery: Recovery?
        if let end = meanHR(s, w.end - 30, w.end), end.coverage > 0.6, (end.hr - restingHR) / reserveSpan >= 0.5 {
            func at(_ t: Int) -> Double? {
                guard let m = meanHR(s, w.end + t - 5, w.end + t + 5), m.coverage > 0.6 else { return nil }
                return m.hr
            }
            let h60 = at(60), h120 = at(120)
            var curve: [(t: Int, hr: Double)] = []
            var logPts: [(Double, Double)] = []
            for t in stride(from: 0, through: 180, by: 5) {
                guard let h = at(t) else { continue }
                curve.append((t, h))
                let excess = h - restingHR
                if t <= 120, excess > 2 { logPts.append((Double(t), log(excess))) }
            }
            var tau: Double?
            if logPts.count >= 10, let fit = Num.ridge(logPts.map { [$0.0] }, logPts.map { $0.1 }), fit.beta[1] < -1e-4 {
                tau = -1 / fit.beta[1]
            }
            var back: Double?
            let target = restingHR + 0.1 * reserveSpan
            var t = 60
            while t <= 30 * 60 {
                if let m = meanHR(s, w.end + t - 30, w.end + t + 30), m.coverage > 0.5, m.hr <= target {
                    back = Double(t) / 60
                    break
                }
                t += 30
            }
            recovery = Recovery(endHR: end.hr, drop60: h60.map { end.hr - $0 }, drop120: h120.map { end.hr - $0 }, tau: tau,
                                minutesToBaseline: back, curve: curve)
        }

        // Cardiac drift over the steady part (after a 10-minute warm-up), only if movement is steady.
        var drift = Drift(percent: nil, note: "")
        let warm = w.start + 600
        let span = w.end - warm
        if span < 20 * 60 {
            drift.note = "Necesita al menos 30 minutos de actividad."
        } else {
            let third = span / 3
            let firstPart = s.filter { $0.ts >= warm && $0.ts < warm + third && $0.worn }
            let lastPart = s.filter { $0.ts >= w.end - third && $0.ts < w.end && $0.worn }
            func cadence(_ p: [Sample]) -> Double? {
                let st = p.compactMap { $0.steps }
                guard st.count >= 2 else { return nil }
                return Double((st.last! - st.first! + 65536) % 65536) / Double(max(1, p.count)) * 60
            }
            let motion1 = Num.mean(firstPart.compactMap { $0.dyn }), motion2 = Num.mean(lastPart.compactMap { $0.dyn })
            let c1 = cadence(firstPart), c2 = cadence(lastPart)
            var steady = true
            if let a = c1, let b = c2, a > 40 { steady = abs(b - a) / a <= 0.06 }
            else if let a = motion1, let b = motion2, a > 0.01 { steady = abs(b - a) / a <= 0.15 }
            let h1 = Num.mean(firstPart.compactMap { $0.hr }.map(Double.init)), h2 = Num.mean(lastPart.compactMap { $0.hr }.map(Double.init))
            if !steady {
                drift.note = "La intensidad cambió durante el entreno: la deriva no es comparable."
            } else if let a = h1, let b = h2, a > 0 {
                drift.percent = 100 * (b - a) / a
                drift.note = "Calculada sobre la parte estable, tras 10 minutos de calentamiento. Influyen calor, hidratación y duración."
            } else {
                drift.note = "Faltan datos de pulso."
            }
        }
        return Result(recovery: recovery, drift: drift, reserve: reserve)
    }

    /// Trend of 60-s recovery across workouts (higher drop = better), latest first in `values`.
    public static func hrrTrendMetric(_ drops: [(day: String, drop: Double)]) -> MetricResult {
        let f = "FCR60 = FC al terminar (media últimos 30 s) − FC 60 s después; mediana de los últimos entrenos válidos"
        guard drops.count >= 3, let med = Num.median(drops.suffix(8).map { $0.drop }) else {
            return .insufficient("hrr60", "Recuperación del pulso a 60 s", unit: "lpm",
                                 need: "3 entrenos intensos con el pulso medido justo al terminar", have: drops.count, formula: f, version: version)
        }
        let older = drops.dropLast(4).suffix(8).map { $0.drop }
        let trend = (older.count >= 3 ? Num.median(older) : nil).map { med - $0 }
        var text = String(format: "Tu pulso baja de media %.0f lpm en el primer minuto tras un esfuerzo intenso.", locale: Num.spanish, med)
        if let t = trend, abs(t) >= 3 { text += t > 0 ? " Está mejorando." : " Últimamente baja más despacio." }
        return MetricResult(id: "hrr60", name: "Recuperación del pulso a 60 s", value: med.rounded(), unit: "lpm", summary: text,
                            confidence: .from(samples: drops.count, medium: 5, high: 10), sampleSize: drops.count, formula: f, version: version)
    }
}
