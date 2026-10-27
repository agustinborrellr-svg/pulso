import Foundation

public enum Stats {
    /// Standard normal cumulative distribution.
    public static func normalCDF(_ z: Double) -> Double { 0.5 * (1 + erf(z / 2.squareRoot())) }

    /// Inverse of the standard normal CDF (Acklam's rational approximation, |error| < 1.2e-9).
    public static func normalQuantile(_ p: Double) -> Double {
        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00]
        let lo = 0.02425, hi = 1 - lo
        if p <= 0 { return -.infinity }
        if p >= 1 { return .infinity }
        if p < lo {
            let q = (-2 * log(p)).squareRoot()
            return (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        if p > hi {
            let q = (-2 * log(1 - p)).squareRoot()
            return -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }
        let q = p - 0.5, r = q * q
        return (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
    }

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
