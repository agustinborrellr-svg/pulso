import Foundation
import PulsoStore

/// A personal baseline for one metric: robust centre and spread of recent nights.
public struct Baseline: Equatable {
    public var center: Double
    public var spread: Double
    public var count: Int

    public var isUsable: Bool { count >= 4 }

    /// Median / scaled MAD of the most recent `window` values, with a floor on the spread so a very
    /// stable history doesn't turn tiny changes into huge z-scores.
    public static func from(_ values: [Double], window: Int = 30, floor: Double) -> Baseline? {
        let recent = Array(values.suffix(window))
        guard !recent.isEmpty, let c = Stats.median(recent) else { return nil }
        let s = max(Stats.robustSpread(recent) ?? floor, floor)
        return Baseline(center: c, spread: s, count: recent.count)
    }

    public func z(_ v: Double) -> Double { Stats.clamp((v - center) / spread, -4, 4) }
}

public struct Baselines: Equatable {
    public var lnHRV: Baseline?
    public var rhr: Baseline?
    public var resp: Baseline?
    public var temp: Baseline?
    public var spo2: Baseline?

    /// Built from days strictly before the day being scored.
    public static func from(history: [DaySummary]) -> Baselines {
        Baselines(
            lnHRV: .from(history.compactMap { $0.hrv }.filter { $0 > 0 }.map { log($0) }, floor: 0.07),
            rhr: .from(history.compactMap { $0.rhr }, floor: 1.5),
            resp: .from(history.compactMap { $0.respRate }, floor: 0.4),
            temp: .from(history.compactMap { $0.skinTemp }, floor: 0.15),
            spo2: .from(history.compactMap { $0.spo2 }, floor: 0.7)
        )
    }

    public var hrvCenter: Double? { lnHRV.map { exp($0.center) } }
}

/// Recovery (0–100 %): a weighted robust z-score composite of last night's physiology against the
/// wearer's own baselines, squashed through a logistic curve. Each factor's signed contribution is
/// returned so the app can explain the score.
public enum Recovery {
    public struct Result: Equatable {
        public var score: Double?
        public var calibrating: Bool
        public var contributors: [Contributor]
        public var skinTempDeviation: Double?
    }

    public static func compute(hrv: Double?, rhr: Double?, resp: Double?, skinTemp: Double?, spo2: Double?,
                               sleepPerformance: Double?, baselines: Baselines) -> Result {
        var terms: [(key: String, label: String, weight: Double, z: Double, value: Double?, base: Double?, unit: String)] = []

        if let hrv, hrv > 0, let b = baselines.lnHRV, b.isUsable {
            terms.append(("hrv", "Variabilidad (VFC)", 0.50, b.z(log(hrv)), hrv, exp(b.center), "ms"))
        }
        if let rhr, let b = baselines.rhr, b.isUsable {
            terms.append(("rhr", "FC en reposo", 0.20, -b.z(rhr), rhr, b.center, "lpm"))
        }
        if let perf = sleepPerformance {
            let z = Stats.clamp((perf - 0.85) / 0.15, -3, 1.5)
            terms.append(("sleep", "Sueño", 0.20, z, perf * 100, 85, "%"))
        }
        if let resp, let b = baselines.resp, b.isUsable {
            // Only an elevated breathing rate counts against you.
            terms.append(("resp", "Respiración", 0.05, -max(0, b.z(resp)), resp, b.center, "rpm"))
        }
        var tempDev: Double?
        if let skinTemp, let b = baselines.temp, b.isUsable {
            let dev = skinTemp - b.center
            tempDev = dev
            let z = -max(0, abs(dev) - 0.3) / 0.3
            terms.append(("temp", "Temperatura piel", 0.05, Stats.clamp(z, -4, 0), dev, 0, "°C"))
        }
        if let spo2, let b = baselines.spo2, b.isUsable, spo2 < b.center - 1.5 {
            terms.append(("spo2", "Oxígeno en sangre", 0.05, Stats.clamp((spo2 - b.center) / b.spread, -4, 0), spo2, b.center, "%"))
        }

        let hasHRV = terms.contains { $0.key == "hrv" }
        let wsum = max(1e-9, terms.reduce(0) { $0 + $1.weight })
        // Impacts are the normalised terms of the composite below, so the "why" adds up to the score.
        let contributors = terms.map {
            Contributor(key: $0.key, label: $0.label, value: $0.value, baseline: $0.base, unit: $0.unit, impact: $0.weight * $0.z / wsum)
        }
        guard hasHRV else {
            return Result(score: nil, calibrating: true, contributors: contributors, skinTempDeviation: tempDev)
        }
        let composite = Stats.clamp(terms.reduce(0) { $0 + $1.weight * $1.z } / wsum, -3, 3)
        // Softer than before: one bad night lands in the 20s–30s, not at 1–2 %.
        let score = curve(composite: composite)
        return Result(score: score.rounded(), calibrating: false, contributors: contributors, skinTempDeviation: tempDev)
    }

    /// Composite z (sum of the contributors' impacts) → recovery %.
    public static func curve(composite: Double) -> Double {
        Stats.clamp(100 * Stats.logistic(1.15 * (Stats.clamp(composite, -3, 3) + 0.35)), 3, 99)
    }

    public enum Band: String { case red, yellow, green }

    public static func band(_ score: Double) -> Band {
        score >= 67 ? .green : (score >= 34 ? .yellow : .red)
    }
}

/// Sleep need, performance, consistency and debt.
public enum SleepCoach {
    /// Tonight's need in minutes: personal baseline + extra for today's strain + part of recent debt − naps.
    public static func need(baseHours: Double, previousStrain: Double?, recentShortfalls: [Double], napMinutes: Double) -> Double {
        let base = baseHours * 60
        let strainExtra = min(45, max(0, (previousStrain ?? 10) - 10) * 3)
        let debtExtra = min(40, max(0, (Stats.mean(Array(recentShortfalls.suffix(3))) ?? 0)) * 0.33)
        return max(base * 0.8, base + strainExtra + debtExtra - napMinutes)
    }

    public static func performance(asleepMinutes: Double, needMinutes: Double) -> Double {
        guard needMinutes > 0 else { return 0 }
        return Stats.clamp(asleepMinutes / needMinutes, 0, 1)
    }

    /// 0–100: how close tonight's bed and wake times were to the previous four nights.
    public static func consistency(onsetMinutes: Double, wakeMinutes: Double, previous: [(onset: Double, wake: Double)]) -> Double? {
        let prev = Array(previous.suffix(4))
        guard prev.count >= 2,
              let mo = Stats.circularMeanMinutes(prev.map { $0.onset }),
              let mw = Stats.circularMeanMinutes(prev.map { $0.wake }) else { return nil }
        let d = (Stats.circularDistanceMinutes(onsetMinutes, mo) + Stats.circularDistanceMinutes(wakeMinutes, mw)) / 2
        return Stats.clamp(100 - d * 0.6, 0, 100)
    }

    public static func minutesAfterMidnight(ts: Int, calendar: Calendar = .current) -> Double {
        let d = Date(timeIntervalSince1970: TimeInterval(ts))
        let c = calendar.dateComponents([.hour, .minute], from: d)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
    }
}

/// Daytime stress (0–3) from heart rate and HRV while still and awake, relative to your own calm
/// daytime baseline (the calmer quartile of still windows over the last two weeks).
public enum Stress {
    public struct Window: Equatable {
        public var ts: Int
        public var score: Double
    }

    public struct StillWindow: Equatable {
        public var ts: Int
        public var hr: Double
        public var rmssd: Double?
    }

    /// 5-minute windows where the wearer was awake, on-wrist and not moving, outside `excluding`.
    public static func stillWindows(samples: [Sample], epochs: [MinuteEpoch], from: Int, to: Int,
                                    excluding: [ClosedRange<Int>], stillThreshold: Double) -> [StillWindow] {
        var out: [StillWindow] = []
        guard let first = epochs.first else { return out }
        var t = from - from % 300
        while t + 300 <= to {
            defer { t += 300 }
            if excluding.contains(where: { $0.overlaps(t...(t + 299)) }) { continue }
            let i0 = max(0, (t - first.ts) / 60), i1 = min(epochs.count, i0 + 5)
            guard i0 < i1 else { continue }
            let es = epochs[i0..<i1].filter { $0.worn }
            guard es.count >= 4 else { continue }
            let calm = es.filter { ($0.motion ?? 0) < max(stillThreshold * 4, 0.1) && $0.stepsDelta < 15 }
            guard calm.count >= 4,
                  let hr = Stats.mean(es.compactMap { $0.hr }) else { continue }
            let runs = HRV.clean(Epochs.rrRuns(Epochs.slice(samples, from: t, to: t + 300), from: t, to: t + 300))
            out.append(StillWindow(ts: t, hr: hr, rmssd: HRV.rmssd(runs, minPairs: 40)))
        }
        return out
    }

    /// Calm reference of one day: 25th-percentile HR and 75th-percentile RMSSD of its still windows.
    public static func calmReference(_ w: [StillWindow]) -> (hr: Double?, hrv: Double?) {
        guard w.count >= 6 else { return (nil, nil) }
        return (Stats.percentile(w.map { $0.hr }, 25), Stats.percentile(w.compactMap { $0.rmssd }, 75))
    }

    public static func score(_ windows: [StillWindow], calmHR: Double, calmHRV: Double?) -> [Window] {
        windows.map { w in
            var z = (w.hr - calmHR) / 6
            if let r = w.rmssd, let ref = calmHRV, ref > 0 {
                z += (log(ref) - log(max(r, 3))) / 0.35
            } else {
                z *= 1.5
            }
            return Window(ts: w.ts, score: 3 * Stats.logistic(z - 1.2))
        }
    }
}
