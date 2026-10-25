import Foundation
import PulsoStore

/// Result categories, modelled on the consumer single-lead ECG features (wellness information, not a diagnosis).
public enum Rhythm: String, Codable, CaseIterable, Sendable {
    case sinus
    case lowHeartRate
    case highHeartRate
    case irregular
    case inconclusive

    public var title: String {
        switch self {
        case .sinus: return "Ritmo sinusal"
        case .lowHeartRate: return "Frecuencia baja"
        case .highHeartRate: return "Frecuencia alta"
        case .irregular: return "Ritmo irregular"
        case .inconclusive: return "No concluyente"
        }
    }

    public var explanation: String {
        switch self {
        case .sinus:
            return "El ritmo del corazón es regular y la frecuencia está entre 50 y 100 lpm. Es el patrón habitual de un corazón sano en reposo."
        case .lowHeartRate:
            return "Frecuencia por debajo de 50 lpm con ritmo regular. Es normal en personas entrenadas o durmiendo; si te mareas o te cansas sin motivo, coméntalo con tu médico."
        case .highHeartRate:
            return "Frecuencia por encima de 100 lpm. Pasa tras el ejercicio, con estrés, cafeína o fiebre. Repite la toma en reposo."
        case .irregular:
            return "Los latidos llegan a intervalos irregulares. Puede deberse a extrasístoles o a una arritmia como la fibrilación auricular. Si se repite, enséñale este registro a un médico."
        case .inconclusive:
            return "La señal no permite clasificar el registro: suele ser por moverse, por poco contacto o por una frecuencia fuera de rango. Apoya el brazo, quédate quieto y repite."
        }
    }

    public static let disclaimer = "Pulso no es un dispositivo médico. Este registro no puede detectar infartos ni coágulos. Si tienes dolor en el pecho, falta de aire o te encuentras mal, llama al 112."
}

public struct ECGAnalysis: Equatable, Sendable {
    public var rhythm: Rhythm
    /// Sample indices of the detected R peaks.
    public var rPeaks: [Int]
    public var heartRate: Double?
    /// R-R intervals in milliseconds.
    public var rr: [Double]
    public var rmssd: Double?
    /// RMSSD / mean RR.
    public var normalizedRMSSD: Double?
    /// Turning-point ratio of the RR series (≈ 0.67 for a random sequence, lower for smooth sinus arrhythmia).
    public var turningPointRatio: Double?
    /// 0…1 rough signal quality.
    public var quality: Double
    /// Mean correlation of each beat with the average beat (morphology consistency).
    public var beatCorrelation: Double? = nil
    /// Whether the average beat shows a P wave before the QRS (absent in atrial fibrillation).
    public var pWave: Bool? = nil
}

enum Stats {
    static func medianOf(_ x: [Double]) -> Double {
        guard !x.isEmpty else { return 0 }
        let s = x.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }
}

public enum ECGAnalyzer {
    /// Moving average with a centred window of `n` samples.
    static func movingAverage(_ x: [Double], _ n: Int) -> [Double] {
        guard n > 1, x.count > 0 else { return x }
        var out = [Double](repeating: 0, count: x.count)
        var sum = 0.0
        let half = n / 2
        var lo = 0, hi = -1
        for i in 0..<x.count {
            let a = max(0, i - half), b = min(x.count - 1, i + half)
            while hi < b { hi += 1; sum += x[hi] }
            while lo < a { sum -= x[lo]; lo += 1 }
            out[i] = sum / Double(hi - lo + 1)
        }
        return out
    }

    /// Baseline wander removal (subtract a ~0.6 s moving average) + light smoothing (~20 ms).
    public static func filter(_ samples: [Float], rate: Double) -> [Double] {
        let x = samples.map(Double.init)
        let baseline = movingAverage(movingAverage(x, max(3, Int(rate * 0.6))), max(3, Int(rate * 0.3)))
        let hp = zip(x, baseline).map { $0 - $1 }
        return movingAverage(hp, max(1, Int(rate * 0.02)))
    }

    /// Pan–Tompkins-style QRS detection: derivative → square → 150 ms moving integration → adaptive
    /// threshold. Each contiguous region above the threshold is one QRS; the R peak is the dominant
    /// deflection inside it (taking the whole region avoids locking onto ripples on its rising edge,
    /// which would otherwise pick the Q wave or the previous T wave). 250 ms refractory period.
    public static func detectRPeaks(_ filtered: [Double], rate: Double) -> [Int] {
        let n = filtered.count
        guard n > Int(rate * 2) else { return [] }
        var d = [Double](repeating: 0, count: n)
        for i in 2..<(n - 2) {
            d[i] = (2 * filtered[i + 2] + filtered[i + 1] - filtered[i - 1] - 2 * filtered[i - 2]) * rate / 8
        }
        let integ = movingAverage(d.map { $0 * $0 }, max(3, Int(rate * 0.15)))
        let refractory = Int(rate * 0.25)
        let pad = Int(rate * 0.03)
        let initial = Array(integ.prefix(Int(rate * 2)))
        var spk = (initial.max() ?? 0) * 0.6
        var npk = (initial.reduce(0, +) / Double(max(1, initial.count))) * 0.5
        var threshold = npk + 0.25 * (spk - npk)
        var peaks: [Int] = []
        var i = 0
        while i < n {
            guard integ[i] > threshold else {
                // Track noise level from sub-threshold local maxima.
                if i > 0, i < n - 1, integ[i] > integ[i - 1], integ[i] >= integ[i + 1] {
                    npk = 0.125 * integ[i] + 0.875 * npk
                    threshold = npk + 0.25 * (spk - npk)
                }
                i += 1
                continue
            }
            var j = i
            var regionMax = 0.0
            while j < n, integ[j] > threshold {
                regionMax = max(regionMax, integ[j])
                j += 1
            }
            let a = max(0, i - pad), b = min(n - 1, j + pad)
            var best = a
            for k in a...b where abs(filtered[k]) > abs(filtered[best]) { best = k }
            if let last = peaks.last, best - last <= refractory {
                // Same beat seen twice (or a T wave): keep the larger deflection.
                if abs(filtered[best]) > abs(filtered[last]) * 1.4 { peaks[peaks.count - 1] = best }
            } else {
                peaks.append(best)
                spk = 0.125 * regionMax + 0.875 * spk
            }
            threshold = npk + 0.25 * (spk - npk)
            i = j + 1
        }
        return peaks
    }

    struct Template {
        var beat: [Double]
        /// Index of the R peak inside `beat`.
        var r: Int
        var correlations: [Double]
    }

    static func pearson(_ a: ArraySlice<Double>, _ b: ArraySlice<Double>) -> Double {
        let n = Double(a.count)
        guard n > 2 else { return 0 }
        let ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        var num = 0.0, da = 0.0, db = 0.0
        for (x, y) in zip(a, b) {
            num += (x - ma) * (y - mb)
            da += (x - ma) * (x - ma)
            db += (y - mb) * (y - mb)
        }
        return da > 0 && db > 0 ? num / (da * db).squareRoot() : 0
    }

    /// Average beat (−300 ms…+450 ms around R) and each beat's QRS correlation with it.
    static func template(_ f: [Double], peaks: [Int], rate: Double) -> Template? {
        let pre = Int(rate * 0.30), post = Int(rate * 0.45)
        let segs = peaks.filter { $0 - pre >= 0 && $0 + post < f.count }.map { Array(f[($0 - pre)...($0 + post)]) }
        guard segs.count >= 4 else { return nil }
        let len = pre + post + 1
        var avg = [Double](repeating: 0, count: len)
        for s in segs { for k in 0..<len { avg[k] += s[k] } }
        avg = avg.map { $0 / Double(segs.count) }
        let qa = pre - Int(rate * 0.1), qb = pre + Int(rate * 0.1)
        let corr = segs.map { pearson($0[qa...qb], avg[qa...qb]) }
        return Template(beat: avg, r: pre, correlations: corr)
    }

    /// P wave present: a positive bump 80–250 ms before R, clearly above the flat segment before it.
    static func hasPWave(_ t: Template, rate: Double) -> Bool {
        let base = Stats.medianOf(Array(t.beat[0..<max(1, Int(rate * 0.04))]))
        let a = t.r - Int(rate * 0.25), b = t.r - Int(rate * 0.08)
        guard a >= 0, b > a else { return false }
        let pAmp = (t.beat[a...b].max() ?? base) - base
        let rAmp = abs(t.beat[t.r] - base)
        return pAmp >= 0.03 && pAmp >= 0.06 * rAmp
    }

    static func turningPointRatio(_ x: [Double]) -> Double? {
        guard x.count >= 6 else { return nil }
        var tp = 0
        for i in 1..<(x.count - 1) where (x[i] > x[i - 1] && x[i] > x[i + 1]) || (x[i] < x[i - 1] && x[i] < x[i + 1]) {
            tp += 1
        }
        return Double(tp) / Double(x.count - 2)
    }

    public static func analyze(samples: [Float], rate: Double) -> ECGAnalysis {
        guard rate > 50, samples.count > Int(rate * 5) else {
            return ECGAnalysis(rhythm: .inconclusive, rPeaks: [], heartRate: nil, rr: [], rmssd: nil, normalizedRMSSD: nil,
                               turningPointRatio: nil, quality: 0)
        }
        let f = filter(samples, rate: rate)
        let peaks = detectRPeaks(f, rate: rate)
        let rr = zip(peaks.dropFirst(), peaks).map { Double($0 - $1) / rate * 1000 }
        let duration = Double(samples.count) / rate
        guard rr.count >= 5 else {
            return ECGAnalysis(rhythm: .inconclusive, rPeaks: peaks, heartRate: nil, rr: rr, rmssd: nil, normalizedRMSSD: nil,
                               turningPointRatio: nil, quality: 0.1)
        }
        let meanRR = rr.reduce(0, +) / Double(rr.count)
        let hr = 60000 / meanRR
        var ss = 0.0
        for k in 1..<rr.count { ss += (rr[k] - rr[k - 1]) * (rr[k] - rr[k - 1]) }
        let rmssd = (ss / Double(rr.count - 1)).squareRoot()
        let nrmssd = rmssd / meanRR
        let tpr = turningPointRatio(rr)

        // Quality: beat-shape consistency, implausible intervals, beat count vs. rate, amplitude.
        let tmpl = template(f, peaks: peaks, rate: rate)
        let corr = tmpl.map { $0.correlations.reduce(0, +) / Double($0.correlations.count) }
        let amps = peaks.map { abs(f[$0]) }
        let ampMean = amps.reduce(0, +) / Double(amps.count)
        let implausible = rr.filter { $0 < 270 || $0 > 2200 }.count
        var quality = corr.map { min(1, max(0, ($0 - 0.5) / 0.4)) } ?? 0
        quality -= Double(implausible) / Double(rr.count)
        let expectedBeats = duration * hr / 60
        if abs(Double(peaks.count) - expectedBeats) > expectedBeats * 0.2 { quality -= 0.2 }
        if ampMean < 0.05 { quality -= 0.5 } // < 50 µV: no contact
        quality = max(0, min(1, quality))
        let pWave = tmpl.map { hasPWave($0, rate: rate) }

        // Irregular: beat-to-beat chaos (high normalised RMSSD with a random-looking sequence) and no
        // P wave; very chaotic rhythms are flagged even if a P-like bump survives the averaging.
        let chaotic = nrmssd >= 0.10 && (tpr ?? 0) >= 0.45
        let veryChaotic = nrmssd >= 0.20 && (tpr ?? 0) >= 0.55
        let rhythm: Rhythm
        if quality < 0.45 || hr < 35 || hr > 160 {
            rhythm = .inconclusive
        } else if (chaotic && pWave == false) || veryChaotic {
            rhythm = .irregular
        } else if hr < 50 {
            rhythm = .lowHeartRate
        } else if hr > 100 {
            rhythm = .highHeartRate
        } else {
            rhythm = .sinus
        }
        return ECGAnalysis(rhythm: rhythm, rPeaks: peaks, heartRate: hr, rr: rr, rmssd: rmssd, normalizedRMSSD: nrmssd,
                           turningPointRatio: tpr, quality: quality, beatCorrelation: corr, pWave: pWave)
    }

    public static func analyze(_ recording: ECGRecording) -> ECGAnalysis {
        analyze(samples: recording.samples, rate: recording.sampleRate)
    }
}

/// Synthetic single-lead ECG (sum of Gaussian P-Q-R-S-T waves per beat, McSharry-style), used to
/// test the analysis and to try the whole ECG flow before owning an MG.
public struct ECGSimulator {
    public struct LCG {
        var state: UInt64
        public init(seed: UInt64) { state = seed }
        mutating func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(1 << 53)
        }
        mutating func normal() -> Double {
            let u1 = max(next(), 1e-12), u2 = next()
            return (-2 * log(u1)).squareRoot() * cos(2 * Double.pi * u2)
        }
    }

    public enum Pattern: Sendable { case sinus, atrialFibrillation }

    public var rate: Double = 512
    public var seconds: Double = 30
    public var heartRate: Double = 64
    /// Breathing-linked RR modulation (fraction).
    public var sinusArrhythmia: Double = 0.04
    public var pattern: Pattern = .sinus
    /// Gaussian noise (mV) and baseline wander amplitude (mV).
    public var noise: Double = 0.02
    public var wander: Double = 0.08
    public var seed: UInt64 = 7

    public init(rate: Double = 512, seconds: Double = 30, heartRate: Double = 64, pattern: Pattern = .sinus, seed: UInt64 = 7) {
        self.rate = rate
        self.seconds = seconds
        self.heartRate = heartRate
        self.pattern = pattern
        self.seed = seed
    }

    /// (offset s relative to R, width s, amplitude mV) for P, Q, R, S, T.
    static let waves: [(Double, Double, Double)] = [(-0.20, 0.025, 0.12), (-0.03, 0.010, -0.12), (0, 0.011, 1.1),
                                                     (0.03, 0.010, -0.25), (0.28, 0.045, 0.30)]

    public func generate() -> [Float] {
        var rng = LCG(seed: seed)
        let n = Int(rate * seconds)
        var beats: [Double] = []
        var t = 0.3
        let base = 60 / heartRate
        while t < seconds + 1 {
            beats.append(t)
            switch pattern {
            case .sinus:
                t += base * (1 + sinusArrhythmia * sin(2 * Double.pi * 0.25 * t)) + rng.normal() * 0.006
            case .atrialFibrillation:
                t += base * (0.65 + 0.7 * rng.next())
            }
        }
        var x = [Double](repeating: 0, count: n)
        for b in beats {
            for (k, w) in Self.waves.enumerated() {
                if pattern == .atrialFibrillation && k == 0 { continue } // no P wave in AF
                let centre = b + w.0
                let lo = max(0, Int((centre - 4 * w.1) * rate)), hi = min(n - 1, Int((centre + 4 * w.1) * rate))
                guard lo < hi else { continue }
                for i in lo...hi {
                    let dt = Double(i) / rate - centre
                    x[i] += w.2 * exp(-dt * dt / (2 * w.1 * w.1))
                }
            }
        }
        for i in 0..<n {
            let ts = Double(i) / rate
            x[i] += wander * sin(2 * Double.pi * 0.3 * ts) + noise * rng.normal()
            if pattern == .atrialFibrillation { x[i] += 0.04 * sin(2 * Double.pi * 6 * ts + rng.next() * 0.3) }
        }
        return x.map { Float($0) }
    }

    public func recording(start: Int) -> ECGRecording {
        ECGRecording(start: start, sampleRate: rate, samples: generate(), source: .simulated)
    }
}
