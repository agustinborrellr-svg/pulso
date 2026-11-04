import Foundation
import PulsoStore

/// A personal baseline for one metric: robust centre and spread of recent nights.
public struct Baseline: Equatable {
    public var center: Double
    public var spread: Double
    public var count: Int

    public var isUsable: Bool { count >= 4 }

    /// Recency weighting of the centre: a value `halfLife` nights old weighs half as much as last night's.
    public static let halfLife = 14.0

    /// Weighted median (recent nights weigh more) / scaled MAD of the most recent `window` values, with a floor
    /// on the spread so a very stable history doesn't turn tiny changes into huge z-scores. WHOOP describes its
    /// baseline as a weighted ~28-day average with more emphasis on recent trends.
    public static func from(_ values: [Double], window: Int = 28, floor: Double) -> Baseline? {
        let recent = Array(values.suffix(window))
        let n = recent.count
        let weighted = recent.enumerated().map { (value: $0.element, weight: pow(0.5, Double(n - 1 - $0.offset) / halfLife)) }
        guard !recent.isEmpty, let c = Stats.weightedMedian(weighted) else { return nil }
        let s = max(Stats.robustSpread(recent) ?? floor, floor)
        return Baseline(center: c, spread: s, count: n)
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

/// Recovery (0–100 %): a logistic model of last night's HRV and resting HR against the wearer's own baselines and of
/// how much of the night's sleep need was met. Each factor's signed contribution (on the logit scale) is returned so
/// the app can explain the score.
///
/// Coefficients fitted to 142 nights of WHOOP's own recovery from the user's export (2026-11-02), with WHOOP's HRV,
/// RHR and sleep as inputs: logit(rec) = −2.166 + 0.504·zHRV − 0.049·zRHR + 4.096·sufficiency. On the last 30 % of
/// the nights (not used to fit) it is off by 7.9 points on average; the previous weighted-z model was off by ~11 and
/// read 9 points low. In those nights breathing rate, skin temperature and SpO₂ added nothing, so they stay out of the
/// score (the health monitor watches them).
public enum Recovery {
    public struct Result: Equatable {
        public var score: Double?
        public var calibrating: Bool
        public var contributors: [Contributor]
        public var skinTempDeviation: Double?
    }

    public static let intercept = -2.166
    public static let hrvWeight = 0.504
    public static let rhrWeight = -0.049
    public static let sleepWeight = 4.096
    /// Sleep sufficiency of a normal night: the sleep factor is measured from here so a day at your baselines is the
    /// neutral of the waterfall.
    public static let usualSufficiency = 0.85

    /// `sleepSufficiency`: time asleep / sleep need, 0–1.
    public static func compute(hrv: Double?, rhr: Double?, resp: Double?, skinTemp: Double?, spo2: Double?,
                               sleepSufficiency: Double?, baselines: Baselines) -> Result {
        var contributors: [Contributor] = []
        var hasHRV = false
        if let hrv, hrv > 0, let b = baselines.lnHRV, b.isUsable {
            hasHRV = true
            contributors.append(Contributor(key: "hrv", label: "Variabilidad (VFC)", value: hrv, baseline: exp(b.center), unit: "ms",
                                            impact: hrvWeight * b.z(log(hrv))))
        }
        if let rhr, let b = baselines.rhr, b.isUsable {
            contributors.append(Contributor(key: "rhr", label: "FC en reposo", value: rhr, baseline: b.center, unit: "lpm",
                                            impact: rhrWeight * b.z(rhr)))
        }
        if let suff = sleepSufficiency {
            let s = Stats.clamp(suff, 0, 1)
            contributors.append(Contributor(key: "sleep", label: "Sueño", value: s * 100, baseline: usualSufficiency * 100, unit: "%",
                                            impact: sleepWeight * (s - usualSufficiency)))
        }
        var tempDev: Double?
        if let skinTemp, let b = baselines.temp, b.isUsable { tempDev = skinTemp - b.center }
        guard hasHRV else {
            return Result(score: nil, calibrating: true, contributors: contributors, skinTempDeviation: tempDev)
        }
        let score = curve(composite: contributors.reduce(0) { $0 + $1.impact })
        return Result(score: score.rounded(), calibrating: false, contributors: contributors, skinTempDeviation: tempDev)
    }

    /// Sum of the contributors' impacts (logit scale, 0 = a night at your baselines with a usual sleep) → recovery %.
    public static func curve(composite: Double) -> Double {
        Stats.clamp(100 * Stats.logistic(intercept + sleepWeight * usualSufficiency + composite), 1, 99)
    }

    public enum Band: String { case red, yellow, green }

    public static func band(_ score: Double) -> Band {
        score >= 67 ? .green : (score >= 34 ? .yellow : .red)
    }
}

/// Sleep need, performance, consistency and debt.
public enum SleepCoach {
    /// Tonight's need in minutes: personal baseline + extra for the previous cycle's strain + sleep debt − naps
    /// (the structure of WHOOP's sleep-need patent; in the user's WHOOP export need ≈ base + 0.97·debt + 0.99·strain
    /// term, off by 2 min on average).
    public static func need(baseHours: Double, previousStrain: Double?, debtMinutes: Double, napMinutes: Double) -> Double {
        let base = baseHours * 60
        return max(base * 0.8, base + strainMinutes(previousStrain) + max(0, debtMinutes) - napMinutes)
    }

    /// Debt carried into tonight's need, from last night's debt and last night's shortfall against its need without
    /// debt (positive = slept less). Fitted to the user's WHOOP export (sleep debt column, 145 nights; 12.8 min off on
    /// the held-out nights): 70 % of the debt stays, 29 % of a shortfall is added, and 90 % of a surplus pays it back.
    /// WHOOP caps it at an unpublished maximum; 180 min here.
    public static func debt(previousDebt: Double, previousShortfall: Double) -> Double {
        Stats.clamp(0.703 * previousDebt + 0.289 * max(0, previousShortfall) + 0.896 * min(0, previousShortfall), 0, maxDebt)
    }

    public static let maxDebt = 180.0

    /// Extra sleep for the previous cycle's strain: f(i) = 1.7 / (1 + e^((17 − i) / 3.5)) hours (WHOOP sleep-need
    /// patent US12318226B2, claim 8; hours, because it reproduces the example of WHOOP's API to the millisecond).
    /// ≈ 3 min at strain 5, 12 at 10, 30 at 14, 51 at 17, 77 at 21.
    public static func strainMinutes(_ strain: Double?) -> Double {
        guard let i = strain else { return 0 }
        return 60 * 1.7 / (1 + exp((17 - Stats.clamp(i, 0, 21)) / 3.5))
    }

    /// Time asleep / sleep need, 0–1 (WHOOP's API definition of sleep performance; what recovery uses).
    public static func sufficiency(asleepMinutes: Double, needMinutes: Double) -> Double {
        guard needMinutes > 0 else { return 0 }
        return Stats.clamp(asleepMinutes / needMinutes, 0, 1)
    }

    /// Sleep score, 0–1. Since 2025 WHOOP blends sufficiency, consistency and efficiency (and sleep stress) with
    /// unpublished weights; fitted to the user's WHOOP export (144 nights, 5.8 points off on held-out nights vs 9.2
    /// for sufficiency alone): −28.5 + 0.864·sufficiency + 0.357·consistency + 0.197·efficiency, all in %.
    /// Without a consistency it is the sufficiency.
    public static func performance(sufficiency: Double, consistency: Double?, efficiency: Double?) -> Double {
        guard let c = consistency else { return Stats.clamp(sufficiency, 0, 1) }
        let e = (efficiency ?? 0.9) * 100
        return Stats.clamp((-28.5 + 0.864 * sufficiency * 100 + 0.357 * c + 0.197 * e) / 100, 0, 1)
    }

    /// 0–100 as WHOOP defines it: the likelihood that you are in the same state (asleep or awake) at the same clock
    /// time, scored like the Sleep Regularity Index (200 × P(match) − 100, floored at 0). The 24 h ending at this
    /// wake-up (window 0) is compared with each of the four days before it (window k ends k days earlier): against the
    /// user's WHOOP export this is 7 points off on average (r 0.92), comparing consecutive day pairs was 16.5 off.
    /// `sessions` are every sleep (night and naps) in the last five days; wake minutes inside a sleep count as awake.
    /// Needs today and two of the previous days.
    public static func consistency(sessions: [SleepSession], wake: Int) -> Double? {
        func window(_ k: Int) -> ClosedRange<Int> { (wake - (k + 1) * 86400 + 1)...(wake - k * 86400) }
        // A day has data when a night overlaps its window (a night that ended later than today's wake straddles two).
        let present = (0...4).map { k in sessions.contains { !$0.isNap && window(k).overlaps($0.start...$0.end) } }
        let pairs = (1...4).filter { present[$0] }
        guard present[0], pairs.count >= 2 else { return nil }
        var asleep = Set<Int>()
        for s in sessions {
            let minutes = max(0, (s.end - s.start) / 60)
            for i in 0..<minutes where s.stages.isEmpty || (i < s.stages.count && s.stages[i] != .awake) {
                let t = s.start + i * 60
                asleep.insert(t - t % 60)
            }
        }
        var same = 0, total = 0
        for k in pairs {
            var t = window(0).lowerBound - window(0).lowerBound % 60
            while t <= window(0).upperBound {
                same += asleep.contains(t) == asleep.contains(t - k * 86400) ? 1 : 0
                total += 1
                t += 60
            }
        }
        guard total > 0 else { return nil }
        return Stats.clamp(200 * Double(same) / Double(total) - 100, 0, 100)
    }

    /// Fallback when the past nights have no hypnogram (imported days): how close tonight's bed and wake times
    /// were to the previous four nights.
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
                                    excluding: [ClosedRange<Int>], stillThreshold: Double, step: Int = 300) -> [StillWindow] {
        var out: [StillWindow] = []
        guard let first = epochs.first else { return out }
        var t = from - from % step
        while t + 300 <= to {
            defer { t += step }
            if excluding.contains(where: { $0.overlaps(t...(t + 299)) }) { continue }
            let i0 = max(0, (t - first.ts) / 60), i1 = min(epochs.count, i0 + 5)
            guard i0 < i1 else { continue }
            let es = epochs[i0..<i1].filter { $0.worn }
            guard es.count >= 4 else { continue }
            let calm = es.filter { ($0.motion ?? 0) < max(stillThreshold * 4, 0.1) && $0.stepsDelta < 15 }
            // Heart rate stays up for minutes after walking: a window right after movement is recovery from
            // activity, not stress (real data: evenings of short walks read as "high stress").
            let before = epochs[max(0, i0 - 10)..<i0]
            let recentSteps = before.reduce(0) { $0 + $1.stepsDelta } + es.reduce(0) { $0 + $1.stepsDelta }
            guard calm.count >= 4, recentSteps < 40,
                  let hr = Stats.mean(es.compactMap { $0.hr }) else { continue }
            let runs = HRV.clean(Epochs.rrRuns(Epochs.slice(samples, from: t, to: t + 300), from: t, to: t + 300))
            out.append(StillWindow(ts: t, hr: hr, rmssd: HRV.rmssd(runs, minPairs: 40)))
        }
        return out
    }

    /// The same 5-minute windows slid one minute at a time, each stamped with its middle minute: one reading per
    /// minute for the curve, with as many beats behind it as the 5-minute windows.
    public static func minuteWindows(samples: [Sample], epochs: [MinuteEpoch], from: Int, to: Int,
                                     excluding: [ClosedRange<Int>], stillThreshold: Double) -> [StillWindow] {
        stillWindows(samples: samples, epochs: epochs, from: from, to: to, excluding: excluding,
                     stillThreshold: stillThreshold, step: 60).map { StillWindow(ts: $0.ts + 120, hr: $0.hr, rmssd: $0.rmssd) }
    }

    /// Reference of one day: median HR and median RMSSD of its still windows. A typical still moment of
    /// yours scores low; against the calmest quartile (the old reference) almost every window read as stress.
    public static func calmReference(_ w: [StillWindow]) -> (hr: Double?, hrv: Double?) {
        guard w.count >= 6 else { return (nil, nil) }
        return (Stats.median(w.map { $0.hr }), Stats.median(w.compactMap { $0.rmssd }))
    }

    /// After a workout HR stays up and HRV down for a while: that is recovery from exercise, not stress.
    public static let postWorkoutMinutes = 90
    /// Previous strap days with a calm reference needed before stress is scored.
    public static let minBaselineDays = 3

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
