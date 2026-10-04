import Foundation

/// Time- and frequency-domain HRV from beat-to-beat runs (Task Force 1996).
public enum HRV {
    /// Range filter (300–2000 ms) and Malik ectopic rejection (|beat − local median of 5| > 20 %).
    /// A rejected beat splits the run so no successive difference spans it.
    public static func clean(_ runs: [RRRun]) -> [RRRun] {
        var out: [RRRun] = []
        for run in runs {
            var cur: RRRun = []
            for i in 0..<run.count {
                let v = run[i]
                var ok = v >= 300 && v <= 2000
                if ok {
                    let lo = max(0, i - 2), hi = min(run.count - 1, i + 2)
                    let neighbours = Array(run[lo...hi])
                    if neighbours.count >= 3, let med = Stats.median(neighbours) {
                        ok = abs(v - med) <= 0.2 * med
                    }
                }
                if ok {
                    cur.append(v)
                } else {
                    if cur.count > 1 { out.append(cur) }
                    cur = []
                }
            }
            if cur.count > 1 { out.append(cur) }
        }
        return out
    }

    /// Number of successive-difference pairs available.
    public static func pairCount(_ runs: [RRRun]) -> Int {
        runs.reduce(0) { $0 + max(0, $1.count - 1) }
    }

    /// RMSSD over contiguous pairs only; nil below `minPairs`.
    public static func rmssd(_ runs: [RRRun], minPairs: Int = 20) -> Double? {
        var sum = 0.0
        var n = 0
        for r in runs where r.count > 1 {
            for i in 1..<r.count {
                let d = r[i] - r[i - 1]
                sum += d * d
                n += 1
            }
        }
        guard n >= minPairs else { return nil }
        return (sum / Double(n)).squareRoot()
    }

    public static func sdnn(_ runs: [RRRun], minBeats: Int = 30) -> Double? {
        let all = runs.flatMap { $0 }
        guard all.count >= minBeats else { return nil }
        return Stats.sd(all)
    }

    public static func meanHR(_ runs: [RRRun]) -> Double? {
        let all = runs.flatMap { $0 }
        guard let m = Stats.mean(all), m > 0 else { return nil }
        return 60000 / m
    }

    /// Respiratory rate from respiratory sinus arrhythmia: resample the tachogram at 4 Hz, remove the
    /// slow trend, and find the dominant frequency in 0.1–0.5 Hz (6–30 breaths/min).
    /// Returns breaths/min for one window of runs, or nil if there is not enough clean signal.
    public static func respiratoryRate(_ runs: [RRRun], minSeconds: Double = 90) -> Double? {
        var estimates: [(rate: Double, weight: Double)] = []
        // Split long runs into ≤ 5-minute segments so each spectrum is local and cheap.
        var segments: [RRRun] = []
        for run in runs {
            var cur: RRRun = []
            var dur = 0.0
            for rr in run {
                cur.append(rr)
                dur += rr / 1000
                if dur >= 300 {
                    segments.append(cur)
                    cur = []
                    dur = 0
                }
            }
            if cur.count > 1 { segments.append(cur) }
        }
        for run in segments {
            let totalSec = run.reduce(0, +) / 1000
            guard totalSec >= minSeconds, run.count >= 60 else { continue }
            // Beat times (s) and instantaneous intervals.
            var t: [Double] = []
            var acc = 0.0
            for rr in run {
                acc += rr / 1000
                t.append(acc)
            }
            let fs = 4.0
            let n = Int((t.last! - t.first!) * fs)
            guard n > 240 else { continue }
            var series = [Double](repeating: 0, count: n)
            var j = 0
            for k in 0..<n {
                let tk = t.first! + Double(k) / fs
                while j < t.count - 2 && t[j + 1] < tk { j += 1 }
                let t0 = t[j], t1 = t[j + 1]
                let f = t1 > t0 ? (tk - t0) / (t1 - t0) : 0
                series[k] = run[j] + (run[j + 1] - run[j]) * f
            }
            // Detrend with an 8 s moving average.
            let w = Int(8 * fs)
            var detr = [Double](repeating: 0, count: n)
            var prefix = [Double](repeating: 0, count: n + 1)
            for k in 0..<n { prefix[k + 1] = prefix[k] + series[k] }
            for k in 0..<n {
                let lo = max(0, k - w / 2), hi = min(n, k + w / 2 + 1)
                detr[k] = series[k] - (prefix[hi] - prefix[lo]) / Double(hi - lo)
            }
            // Hann window + DFT scan.
            var bestF = 0.0, bestP = 0.0, totalP = 0.0
            var f = 0.1
            while f <= 0.5 + 1e-9 {
                var re = 0.0, im = 0.0
                for k in 0..<n {
                    let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(n - 1))
                    let a = 2 * Double.pi * f * Double(k) / fs
                    re += detr[k] * hann * cos(a)
                    im -= detr[k] * hann * sin(a)
                }
                let p = re * re + im * im
                totalP += p
                if p > bestP { bestP = p; bestF = f }
                f += 0.005
            }
            guard totalP > 0, bestF > 0 else { continue }
            let peakiness = bestP / totalP
            if peakiness > 0.03 {
                estimates.append((bestF * 60, peakiness * totalSec))
            }
        }
        guard !estimates.isEmpty else { return nil }
        let wsum = estimates.reduce(0) { $0 + $1.weight }
        let rate = estimates.reduce(0) { $0 + $1.rate * $1.weight } / wsum
        return (8...30).contains(rate) ? rate : nil
    }
}
