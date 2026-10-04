import Foundation

public enum Stats {
    public static func mean(_ x: [Double]) -> Double? {
        x.isEmpty ? nil : x.reduce(0, +) / Double(x.count)
    }

    public static func median(_ x: [Double]) -> Double? {
        percentile(x, 50)
    }

    /// Linear-interpolated percentile, p in 0…100.
    public static func percentile(_ x: [Double], _ p: Double) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        if s.count == 1 { return s[0] }
        let rank = min(max(p, 0), 100) / 100 * Double(s.count - 1)
        let lo = Int(rank.rounded(.down))
        let hi = min(lo + 1, s.count - 1)
        let frac = rank - Double(lo)
        return s[lo] + (s[hi] - s[lo]) * frac
    }

    /// Sample standard deviation (n-1).
    public static func sd(_ x: [Double]) -> Double? {
        guard x.count > 1, let m = mean(x) else { return nil }
        let v = x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)
        return v.squareRoot()
    }

    /// Median absolute deviation scaled to be consistent with σ for normal data.
    public static func robustSpread(_ x: [Double]) -> Double? {
        guard let med = median(x) else { return nil }
        guard let mad = median(x.map { abs($0 - med) }) else { return nil }
        return 1.4826 * mad
    }

    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    public static func logistic(_ x: Double) -> Double {
        1 / (1 + exp(-x))
    }

    /// Pearson correlation.
    public static func pearson(_ a: [Double], _ b: [Double]) -> Double? {
        guard a.count == b.count, a.count > 2, let ma = mean(a), let mb = mean(b) else { return nil }
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<a.count {
            num += (a[i] - ma) * (b[i] - mb)
            da += (a[i] - ma) * (a[i] - ma)
            db += (b[i] - mb) * (b[i] - mb)
        }
        guard da > 0, db > 0 else { return nil }
        return num / (da * db).squareRoot()
    }

    /// Circular mean of clock times expressed as minutes after midnight (handles the 23:50 / 00:10 wrap).
    public static func circularMeanMinutes(_ minutes: [Double]) -> Double? {
        guard !minutes.isEmpty else { return nil }
        var sx = 0.0, sy = 0.0
        for m in minutes {
            let a = m / 1440 * 2 * Double.pi
            sx += cos(a); sy += sin(a)
        }
        var ang = atan2(sy, sx)
        if ang < 0 { ang += 2 * Double.pi }
        return ang / (2 * Double.pi) * 1440
    }

    /// Smallest distance between two clock times in minutes (0…720).
    public static func circularDistanceMinutes(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 1440)
        return min(d, 1440 - d)
    }
}
