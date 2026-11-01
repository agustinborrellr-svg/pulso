import Foundation

/// Beat-to-beat artefact detection and correction (Lipponen & Tarvainen 2019, J Med Eng Technol 43(3):173–181,
/// the method used by Kubios HRV; constants as in NeuroKit2's implementation).
///
/// Two normalised series drive the decision: dRR (difference between consecutive intervals) and mRR (deviation
/// from the 11-beat median, negative deviations doubled), each divided by a time-varying threshold
/// 5.2 × quartile deviation over 91 beats. Beats are then classified as ectopic, missed, extra or long/short and
/// corrected: an extra beat is merged into its neighbour, a missed one is split in two, and ectopic / long /
/// short beats get their R peak re-placed between its neighbours (linear interpolation of the peak time, which
/// keeps the total time). A beat must be corrected, not deleted, or the series loses its timing.
public enum RRCorrection {
    public static let alpha = 5.2
    public static let window = 91
    public static let medianOrder = 11
    public static let c1 = 0.13
    public static let c2 = 0.17

    public enum Kind: Equatable, Sendable { case ectopic, missed, extra, longShort }

    public struct Result: Equatable, Sendable {
        public var rr: [Double]
        public var artifacts: [(index: Int, kind: Kind)]

        public static func == (a: Result, b: Result) -> Bool {
            a.rr == b.rr && a.artifacts.map(\.index) == b.artifacts.map(\.index)
        }
    }

    /// Centred rolling quantiles (min_periods = 1), with a sorted window that slides one value at a time.
    static func rollingQuantiles(_ x: [Double], width: Int, qs: [Double]) -> [[Double]] {
        let half = width / 2, n = x.count
        var window: [Double] = []
        func insert(_ v: Double) {
            var lo = 0, hi = window.count
            while lo < hi { let m = (lo + hi) / 2; if window[m] < v { lo = m + 1 } else { hi = m } }
            window.insert(v, at: lo)
        }
        func remove(_ v: Double) {
            var lo = 0, hi = window.count
            while lo < hi { let m = (lo + hi) / 2; if window[m] < v { lo = m + 1 } else { hi = m } }
            if lo < window.count { window.remove(at: lo) }
        }
        var out = qs.map { _ in [Double](repeating: 0, count: n) }
        var left = 0, right = -1
        for i in 0..<n {
            let l = max(0, i - half), r = min(n - 1, i + half)
            while right < r { right += 1; insert(x[right]) }
            while left < l { remove(x[left]); left += 1 }
            for (k, q) in qs.enumerated() {
                let pos = q * Double(window.count - 1)
                let lo = Int(pos.rounded(.down)), hi = Int(pos.rounded(.up))
                out[k][i] = window[lo] + (window[hi] - window[lo]) * (pos - Double(lo))
            }
        }
        return out
    }

    static func rollingQuantile(_ x: [Double], width: Int, q: Double) -> [Double] {
        rollingQuantiles(x, width: width, qs: [q])[0]
    }

    static func threshold(_ x: [Double]) -> [Double] {
        let q = rollingQuantiles(x.map(abs), width: window, qs: [0.25, 0.75])
        return zip(q[0], q[1]).map { alpha * ($1 - $0) / 2 }
    }

    /// Classifies the artefacts of one contiguous run of intervals (ms).
    public static func detect(_ rr: [Double]) -> [(index: Int, kind: Kind)] {
        let n = rr.count
        guard n >= 5 else { return [] }
        var drrs = [0.0] + (1..<n).map { rr[$0] - rr[$0 - 1] }
        drrs[0] = drrs[1...].reduce(0, +) / Double(n - 1)
        let th1 = threshold(drrs)
        for i in 0..<n { drrs[i] = th1[i] > 0 ? drrs[i] / th1[i] : 0 }
        // Reflect-pad by 2 (numpy "reflect").
        func padded(_ k: Int) -> Double {
            var j = k
            if j < 0 { j = -j }
            if j >= n { j = 2 * (n - 1) - j }
            return drrs[max(0, min(n - 1, j))]
        }
        var s12 = [Double](repeating: 0, count: n), s22 = [Double](repeating: 0, count: n)
        for d in 0..<n {
            if drrs[d] > 0 { s12[d] = max(padded(d - 1), padded(d + 1)) } else if drrs[d] < 0 { s12[d] = min(padded(d - 1), padded(d + 1)) }
            if drrs[d] >= 0 { s22[d] = min(padded(d + 1), padded(d + 2)) } else { s22[d] = max(padded(d + 1), padded(d + 2)) }
        }
        let medrr = rollingQuantile(rr, width: medianOrder, q: 0.5)
        var mrrs = zip(rr, medrr).map { $0 - $1 }.map { $0 < 0 ? $0 * 2 : $0 }
        let th2 = threshold(mrrs)
        for i in 0..<n { mrrs[i] = th2[i] > 0 ? mrrs[i] / th2[i] : 0 }

        var out: [(Int, Kind)] = []
        var i = 0
        while i < n - 2 {
            if abs(drrs[i]) <= 1 { i += 1; continue }
            let eq1 = drrs[i] > 1 && s12[i] < (-c1 * drrs[i] - c2)
            let eq2 = drrs[i] < -1 && s12[i] > (-c1 * drrs[i] + c2)
            if eq1 || eq2 { out.append((i, .ectopic)); i += 1; continue }
            if !(abs(drrs[i]) > 1 || abs(mrrs[i]) > 3) { i += 1; continue }
            var candidates = [i]
            if abs(drrs[i + 1]) < abs(drrs[i + 2]) { candidates.append(i + 1) }
            for j in candidates {
                let eq3 = drrs[j] > 1 && s22[j] < -1
                let eq4 = abs(mrrs[j]) > 3
                let eq5 = drrs[j] < -1 && s22[j] > 1
                guard eq3 || eq4 || eq5 else { continue }
                let eq6 = abs(rr[j] / 2 - medrr[j]) < th2[j]
                let eq7 = j + 1 < n && abs(rr[j] + rr[j + 1] - medrr[j]) < th2[j]
                if eq5 && eq7 { out.append((j, .extra)); continue }
                if eq3 && eq6 { out.append((j, .missed)); continue }
                out.append((j, .longShort))
            }
            i += 1
        }
        // One label per beat, in order.
        var seen = Set<Int>()
        return out.filter { seen.insert($0.0).inserted }.sorted { $0.0 < $1.0 }.map { (index: $0.0, kind: $0.1) }
    }

    /// Corrected intervals. The detector only runs on runs with a jump of more than 15 % between consecutive
    /// intervals (premature, missed and extra beats change the interval by far more); smaller changes are normal
    /// beat-to-beat variability and the run is returned as it is.
    public static func correct(_ rr: [Double]) -> Result {
        if rr.count < 5 || !zip(rr, rr.dropFirst()).contains(where: { abs($1 - $0) > 0.15 * min($0, $1) }) {
            return Result(rr: rr, artifacts: [])
        }
        let artifacts = detect(rr)
        guard !artifacts.isEmpty else { return Result(rr: rr, artifacts: []) }
        var x = rr
        var removed = Set<Int>()
        var splits: [Int: Int] = [:]
        for a in artifacts {
            let j = a.index
            switch a.kind {
            case .extra where j + 1 < x.count:
                // The detected peak between j and j+1 is false: one interval.
                x[j + 1] = x[j] + x[j + 1]
                removed.insert(j)
            case .missed:
                splits[j] = 2
            case .ectopic, .longShort:
                // Move the peak that ends interval j halfway between its neighbours.
                if j + 1 < x.count, !removed.contains(j + 1) {
                    let total = x[j] + x[j + 1]
                    x[j] = total / 2
                    x[j + 1] = total / 2
                }
            default:
                break
            }
        }
        var out: [Double] = []
        for (k, v) in x.enumerated() where !removed.contains(k) {
            if let parts = splits[k] {
                out += Array(repeating: v / Double(parts), count: parts)
            } else {
                out.append(v)
            }
        }
        return Result(rr: out, artifacts: artifacts)
    }
}
