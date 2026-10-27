import Foundation

/// Everything «En vivo» computes from the beat-to-beat stream: the 60-second scan, Poincaré plot,
/// coherence for biofeedback, the orthostatic, heart-rate-recovery and max-HR tests, the zone guard and laps.
public enum LiveMetrics {
    /// One beat as it arrives: when (unix seconds, fractional) and its R-R interval in ms.
    public struct Beat: Equatable, Sendable {
        public var t: Double
        public var rr: Double
        public init(t: Double, rr: Double) {
            self.t = t
            self.rr = rr
        }
        public var hr: Double { 60000 / rr }
    }

    // MARK: Scan

    /// What "normal for you" means while awake and still.
    public struct Baseline: Equatable, Sendable {
        public var calmHR: Double?
        public var calmHRV: Double?
        public var restingHR: Double?
        public var nightHRV: Double?
        public init(calmHR: Double? = nil, calmHRV: Double? = nil, restingHR: Double? = nil, nightHRV: Double? = nil) {
            self.calmHR = calmHR
            self.calmHRV = calmHRV
            self.restingHR = restingHR
            self.nightHRV = nightHRV
        }

        /// Daytime still references; derived from night values when no daytime ones exist yet
        /// (awake and sitting: about 8 bpm above resting HR and 80 % of the night's RMSSD).
        var reference: (hr: Double, hrv: Double?)? {
            if let h = calmHR { return (h, calmHRV ?? nightHRV.map { $0 * 0.8 }) }
            if let r = restingHR { return (r + 8, calmHRV ?? nightHRV.map { $0 * 0.8 }) }
            return nil
        }
    }

    public struct Scan: Equatable, Sendable {
        public var hr: Double
        public var rmssd: Double?
        public var sdnn: Double?
        public var respRate: Double?
        /// 0 (calm) … 3 (very activated), same scale as the daily stress monitor.
        public var stress: Double?
        /// 0–100: how close you are to your calm self right now.
        public var state: Int?
        public var hrDelta: Double?
        public var hrvRatio: Double?
        public var beats: Int

        public var label: String {
            guard let s = stress else { return "Sin referencia aún" }
            if s < 1 { return "En calma" }
            if s < 2 { return "Algo activado" }
            return "Muy activado"
        }
    }

    /// A still, seated 60-second check against your own baseline. Needs ≥ 40 clean beats.
    public static func scan(_ beats: [Beat], baseline: Baseline) -> Scan? {
        let runs = HRV.clean(runs(beats))
        let all = runs.flatMap { $0 }
        guard all.count >= 40, let hr = HRV.meanHR(runs) else { return nil }
        let rmssd = HRV.rmssd(runs, minPairs: 30)
        var out = Scan(hr: hr, rmssd: rmssd, sdnn: HRV.sdnn(runs, minBeats: 40),
                       respRate: HRV.respiratoryRate(runs, minSeconds: 45), stress: nil, state: nil, beats: all.count)
        if let ref = baseline.reference {
            var z = (hr - ref.hr) / 6
            out.hrDelta = hr - ref.hr
            if let r = rmssd, let h = ref.hrv, h > 0 {
                z += (log(h) - log(max(r, 3))) / 0.35
                out.hrvRatio = r / h
            } else {
                z *= 1.5
            }
            let stress = 3 * Stats.logistic(z - 1.2)
            out.stress = stress
            out.state = Int((100 * (1 - stress / 3)).rounded())
        }
        return out
    }

    /// Splits the stream where beats are missing (a gap longer than 1.5 × the beat) so HRV never spans a gap.
    public static func runs(_ beats: [Beat]) -> [RRRun] {
        var out: [RRRun] = []
        var cur: RRRun = []
        var lastT: Double?
        for b in beats {
            if let l = lastT, b.t - l > 1.5 * b.rr / 1000 + 0.6 {
                if cur.count > 1 { out.append(cur) }
                cur = []
            }
            cur.append(b.rr)
            lastT = b.t
        }
        if cur.count > 1 { out.append(cur) }
        return out
    }

    // MARK: Poincaré

    public struct Poincare: Equatable, Sendable {
        public var points: [SIMD2<Double>]
        /// Short-term (beat-to-beat) variability, ms.
        public var sd1: Double
        /// Long-term variability, ms.
        public var sd2: Double
    }

    /// RRₙ vs RRₙ₊₁ over clean consecutive beats.
    public static func poincare(_ beats: [Beat]) -> Poincare? {
        let runs = HRV.clean(runs(beats))
        var pts: [SIMD2<Double>] = []
        var diffs: [Double] = []
        for r in runs where r.count > 1 {
            for i in 1..<r.count {
                pts.append(SIMD2(r[i - 1], r[i]))
                diffs.append(r[i] - r[i - 1])
            }
        }
        guard pts.count >= 10, let sdd = Stats.sd(diffs), let sdnn = Stats.sd(runs.flatMap { $0 }) else { return nil }
        let sd1 = sdd / 2.0.squareRoot()
        let sd2 = max(0, 2 * sdnn * sdnn - sd1 * sd1).squareRoot()
        return Poincare(points: pts, sd1: sd1, sd2: sd2)
    }

    // MARK: Coherence

    public struct Coherence: Equatable, Sendable {
        /// Peak power / power elsewhere (HeartMath-style ratio).
        public var ratio: Double
        /// 0–100.
        public var score: Int
        /// Breathing rhythm the heart is following, breaths/min.
        public var peakPerMinute: Double

        public var level: String { score >= 70 ? "Alta" : score >= 40 ? "Media" : "Baja" }
    }

    /// Cardiac coherence of the last `seconds` (default 64): how much of the heart-rate variation sits in one
    /// smooth rhythm at 0.04–0.26 Hz (slow breathing makes it a sine wave around 0.1 Hz).
    public static func coherence(_ beats: [Beat], seconds: Double = 64) -> Coherence? {
        guard let last = beats.last else { return nil }
        let window = beats.filter { $0.t >= last.t - seconds }
        let clean = HRV.clean(runs(window)).flatMap { $0 }
        guard clean.count >= 30 else { return nil }
        let series = resample(clean, fs: 4)
        guard series.count >= 160 else { return nil }
        let spectrum = powerSpectrum(series, fs: 4, from: 0.0033, to: 0.4, step: 0.005)
        let band = spectrum.filter { $0.f >= 0.04 && $0.f <= 0.26 }
        guard let peak = band.max(by: { $0.p < $1.p }) else { return nil }
        let peakPower = spectrum.filter { abs($0.f - peak.f) <= 0.015 }.reduce(0) { $0 + $1.p }
        let total = spectrum.reduce(0) { $0 + $1.p }
        guard total > 0 else { return nil }
        let ratio = peakPower / max(total - peakPower, total * 1e-3)
        let score = Int((100 * (1 - exp(-ratio / 1.5))).rounded())
        return Coherence(ratio: ratio, score: score, peakPerMinute: peak.f * 60)
    }

    /// The tachogram (ms) evenly resampled at `fs` Hz with its mean removed.
    static func resample(_ rr: [Double], fs: Double) -> [Double] {
        var t: [Double] = []
        var acc = 0.0
        for v in rr {
            acc += v / 1000
            t.append(acc)
        }
        guard let t0 = t.first, let t1 = t.last, t1 > t0 else { return [] }
        let n = Int((t1 - t0) * fs)
        var out = [Double](repeating: 0, count: max(0, n))
        var j = 0
        for k in 0..<n {
            let tk = t0 + Double(k) / fs
            while j < t.count - 2 && t[j + 1] < tk { j += 1 }
            let a = t[j], b = t[j + 1]
            let f = b > a ? (tk - a) / (b - a) : 0
            out[k] = rr[j] + (rr[j + 1] - rr[j]) * f
        }
        let mean = out.reduce(0, +) / Double(max(out.count, 1))
        return out.map { $0 - mean }
    }

    static func powerSpectrum(_ x: [Double], fs: Double, from: Double, to: Double, step: Double) -> [(f: Double, p: Double)] {
        let n = x.count
        let windowed = x.enumerated().map { k, v in v * (0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(n - 1))) }
        var out: [(Double, Double)] = []
        var f = from
        while f <= to + 1e-9 {
            var re = 0.0, im = 0.0
            for k in 0..<n {
                let a = 2 * Double.pi * f * Double(k) / fs
                re += windowed[k] * cos(a)
                im -= windowed[k] * sin(a)
            }
            out.append((f, (re * re + im * im) / Double(n)))
            f += step
        }
        return out
    }

    // MARK: Orthostatic test

    public struct Orthostatic: Equatable, Sendable {
        public var lyingHR: Double
        public var lyingRMSSD: Double?
        public var peakHR: Double
        public var standingHR: Double
        public var standingRMSSD: Double?
        /// Ewing's 30:15 ratio (longest R-R around beat 30 / shortest around beat 15 after standing).
        public var ratio3015: Double?

        public var rise: Double { standingHR - lyingHR }
        public var verdict: String {
            if rise >= 30 { return "Subida muy grande al ponerte de pie. Si además te mareas a menudo, coméntaselo a tu médico." }
            if let r = ratio3015, r < 1.0 { return "Tu pulso tarda en reajustarse al levantarte: típico de fatiga o poco descanso." }
            if rise > 20 { return "Subida algo alta: puede ser cansancio, poco líquido o una noche corta." }
            return "Respuesta normal: tu sistema nervioso se adapta bien al cambio de postura."
        }
    }

    /// Lying still until `standAt`, then standing for ≥ 2 minutes. Uses the last 60 s lying, the first 30 s
    /// standing for the peak and minutes 2–3 standing for the settled value.
    public static func orthostatic(_ beats: [Beat], standAt: Double) -> Orthostatic? {
        let lying = beats.filter { $0.t >= standAt - 60 && $0.t < standAt }
        let after = beats.filter { $0.t >= standAt }
        let settled = after.filter { $0.t >= standAt + 120 && $0.t < standAt + 180 }
        let lyingRuns = HRV.clean(runs(lying))
        let settledRuns = HRV.clean(runs(settled))
        guard let lHR = HRV.meanHR(lyingRuns), let sHR = HRV.meanHR(settledRuns) else { return nil }
        let early = after.filter { $0.t < standAt + 30 }.map(\.hr)
        guard early.count >= 5 else { return nil }
        var smoothed: [Double] = []
        for i in 2..<early.count {
            let sum: Double = early[i - 2] + early[i - 1] + early[i]
            smoothed.append(sum / 3)
        }
        var r3015: Double?
        if after.count >= 40 {
            let rr = after.map(\.rr)
            if let longest = rr[20..<min(40, rr.count)].max(), let shortest = rr[5..<25].min(), shortest > 0 {
                r3015 = longest / shortest
            }
        }
        return Orthostatic(lyingHR: lHR, lyingRMSSD: HRV.rmssd(lyingRuns, minPairs: 20), peakHR: smoothed.max() ?? sHR,
                           standingHR: sHR, standingRMSSD: HRV.rmssd(settledRuns, minPairs: 20), ratio3015: r3015)
    }

    // MARK: Heart-rate recovery

    public struct Recovery: Equatable, Sendable {
        public var peakHR: Double
        public var hr60: Double
        public var hr120: Double?
        public var drop60: Double { peakHR - hr60 }
        public var drop120: Double? { hr120.map { peakHR - $0 } }
        public var level: String {
            switch drop60 {
            case ..<12: return "Baja"
            case ..<20: return "Normal"
            case ..<30: return "Buena"
            default: return "Excelente"
            }
        }
    }

    /// Peak in the 30 s before stopping and the HR one and two minutes later (5-second averages).
    /// A drop under 12 bpm in the first minute is the classic warning sign (Cole 1999).
    public static func recovery(_ samples: [(t: Double, hr: Double)], stopAt: Double) -> Recovery? {
        let before = samples.filter { $0.t >= stopAt - 30 && $0.t <= stopAt }.map(\.hr)
        func around(_ s: Double) -> Double? {
            Stats.mean(samples.filter { abs($0.t - (stopAt + s)) <= 5 }.map(\.hr))
        }
        guard let peak = rolling(before, 5).max(), let h60 = around(60) else { return nil }
        return Recovery(peakHR: peak, hr60: h60, hr120: around(120))
    }

    /// Highest 5-second average, the honest "max HR" of a test (no single-beat spikes).
    public static func peakHR(_ samples: [(t: Double, hr: Double)]) -> Double? {
        rolling(samples.map(\.hr), 5).max()
    }

    static func rolling(_ x: [Double], _ n: Int) -> [Double] {
        guard x.count >= n else { return x.isEmpty ? [] : [x.reduce(0, +) / Double(x.count)] }
        return (n...x.count).map { i in x[(i - n)..<i].reduce(0, +) / Double(n) }
    }

    // MARK: Zone guard

    public enum ZoneCue: Equatable, Sendable { case tooLow, tooHigh, backIn }

    /// Vibrates when you leave the target band for more than `grace` seconds, at most every `every` seconds,
    /// and once more when you are back in.
    public struct ZoneGuard: Equatable, Sendable {
        public var low: Double
        public var high: Double
        public var grace: Double = 10
        public var every: Double = 45
        var outsideSince: Double?
        var lastCue: Double?
        var warned = false

        public init(low: Double, high: Double) {
            self.low = low
            self.high = high
        }

        public mutating func update(hr: Double, at t: Double) -> ZoneCue? {
            let inside = hr >= low && hr <= high
            if inside {
                outsideSince = nil
                if warned {
                    warned = false
                    return .backIn
                }
                return nil
            }
            if outsideSince == nil { outsideSince = t }
            guard t - outsideSince! >= grace, t - (lastCue ?? -.infinity) >= every else { return nil }
            lastCue = t
            warned = true
            return hr < low ? .tooLow : .tooHigh
        }
    }

    // MARK: Laps

    public struct Lap: Equatable, Sendable {
        public var start: Double
        public var end: Double
        public var avgHR: Double?
        public var maxHR: Double?
        public var duration: Double { end - start }

        public init(start: Double, end: Double, avgHR: Double?, maxHR: Double?) {
            self.start = start
            self.end = end
            self.avgHR = avgHR
            self.maxHR = maxHR
        }
    }

    /// Splits a workout at the lap marks.
    public static func laps(_ samples: [(t: Double, hr: Double)], marks: [Double], start: Double, end: Double) -> [Lap] {
        let bounds = [start] + marks.filter { $0 > start && $0 < end }.sorted() + [end]
        return (1..<bounds.count).map { i in
            let hr = samples.filter { $0.t >= bounds[i - 1] && $0.t < bounds[i] }.map(\.hr)
            return Lap(start: bounds[i - 1], end: bounds[i], avgHR: Stats.mean(hr), maxHR: hr.max())
        }
    }
}

extension Strain {
    /// Inverse of `score(load:)`: the load behind a strain value (to keep adding live minutes to it).
    public static func load(score: Double) -> Double {
        guard score > 0 else { return 0 }
        return exp(score * log(1 + ceilingLoad) / 21) - 1
    }
}
