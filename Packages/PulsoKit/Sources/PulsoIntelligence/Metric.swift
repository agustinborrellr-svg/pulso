import Foundation

/// One derived metric, always with its provenance and reliability. When the data can't support it,
/// `status` says why instead of inventing a number.
public struct MetricResult: Equatable, Identifiable, Sendable {
    public enum Status: Equatable, Sendable {
        case ok
        /// Not enough data: what is missing and how much is needed.
        case insufficient(String)
    }

    public enum Confidence: Int, Comparable, Sendable {
        case low = 0, medium = 1, high = 2
        public static func < (a: Confidence, b: Confidence) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .low: return "baja"
            case .medium: return "media"
            case .high: return "alta"
            }
        }

        static func from(samples n: Int, medium: Int, high: Int) -> Confidence {
            n >= high ? .high : (n >= medium ? .medium : .low)
        }
    }

    public var id: String
    public var name: String
    public var value: Double?
    public var unit: String
    /// Human sentence with the value in context.
    public var summary: String
    public var interval: ClosedRange<Double>?
    public var confidence: Confidence
    public var status: Status
    /// Number of observations behind it.
    public var sampleSize: Int
    public var formula: String
    public var version: String

    public init(id: String, name: String, value: Double?, unit: String, summary: String, interval: ClosedRange<Double>? = nil,
                confidence: Confidence, status: Status = .ok, sampleSize: Int, formula: String, version: String = "1.0") {
        self.id = id
        self.name = name
        self.value = value
        self.unit = unit
        self.summary = summary
        self.interval = interval
        self.confidence = confidence
        self.status = status
        self.sampleSize = sampleSize
        self.formula = formula
        self.version = version
    }

    public static func insufficient(_ id: String, _ name: String, unit: String = "", need: String, have: Int,
                                    formula: String, version: String = "1.0") -> MetricResult {
        MetricResult(id: id, name: name, value: nil, unit: unit, summary: "Datos insuficientes: \(need).", confidence: .low,
                     status: .insufficient(need), sampleSize: have, formula: formula, version: version)
    }

    public var isAvailable: Bool { status == .ok && value != nil }

    /// For a locked metric, how far along it is: what you have vs the first number in what it needs
    /// ("14 noches…" → 14). Nil when the requirement is not a count.
    public var unlock: (have: Int, need: Int)? {
        guard case .insufficient(let need) = status else { return nil }
        let digits = need.drop { !$0.isNumber }.prefix { $0.isNumber }
        guard let n = Int(digits), n > 0 else { return nil }
        return (min(sampleSize, n), n)
    }
}

// MARK: - Statistics toolkit (no dependencies)

enum Num {
    static func mean(_ x: [Double]) -> Double? { x.isEmpty ? nil : x.reduce(0, +) / Double(x.count) }

    static func median(_ x: [Double]) -> Double? {
        guard !x.isEmpty else { return nil }
        let s = x.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// 1.4826 × MAD (≈ σ for normal data).
    static func mad(_ x: [Double]) -> Double? {
        guard let m = median(x) else { return nil }
        return median(x.map { abs($0 - m) }).map { $0 * 1.4826 }
    }

    static func sd(_ x: [Double]) -> Double? {
        guard x.count > 1, let m = mean(x) else { return nil }
        return (x.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(x.count - 1)).squareRoot()
    }

    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }

    /// Two-sided Student t critical value for confidence `level` (0.9 / 0.95) and `df` degrees of freedom.
    static func tCritical(df: Int, level: Double = 0.9) -> Double {
        let z = level >= 0.95 ? 1.959964 : 1.644854
        guard df > 0 else { return z * 3 }
        let d = Double(df)
        // Cornish–Fisher expansion of the t quantile around the normal one (accurate to ~1 % for df ≥ 3).
        let g1 = (pow(z, 3) + z) / 4
        let g2 = (5 * pow(z, 5) + 16 * pow(z, 3) + 3 * z) / 96
        let g3 = (3 * pow(z, 7) + 19 * pow(z, 5) + 17 * pow(z, 3) - 15 * z) / 384
        return z + g1 / d + g2 / (d * d) + g3 / (d * d * d)
    }

    /// Regularized upper incomplete gamma Q(a, x) (series / continued fraction, Numerical Recipes).
    static func gammaQ(_ a: Double, _ x: Double) -> Double {
        guard x > 0 else { return 1 }
        let lnGa = lnGamma(a)
        if x < a + 1 {
            var sum = 1 / a, del = sum, ap = a
            for _ in 0..<500 {
                ap += 1
                del *= x / ap
                sum += del
                if abs(del) < abs(sum) * 1e-12 { break }
            }
            return 1 - sum * exp(-x + a * log(x) - lnGa)
        }
        var b = x + 1 - a, c = 1 / 1e-300, d = 1 / b, h = d
        for i in 1...500 {
            let an = -Double(i) * (Double(i) - a)
            b += 2
            d = an * d + b
            if abs(d) < 1e-300 { d = 1e-300 }
            c = b + an / c
            if abs(c) < 1e-300 { c = 1e-300 }
            d = 1 / d
            let del = d * c
            h *= del
            if abs(del - 1) < 1e-12 { break }
        }
        return exp(-x + a * log(x) - lnGa) * h
    }

    /// ln Γ(x), Lanczos approximation (g = 7, n = 9); avoids the platform-ambiguous `lgamma`.
    static func lnGamma(_ x: Double) -> Double {
        let c = [0.99999999999980993, 676.5203681218851, -1259.1392167224028, 771.32342877765313, -176.61502916214059,
                 12.507343278686905, -0.13857109526572012, 9.9843695780195716e-6, 1.5056327351493116e-7]
        if x < 0.5 { return log(Double.pi / abs(sin(Double.pi * x))) - lnGamma(1 - x) }
        let z = x - 1
        var a = c[0]
        let t = z + 7.5
        for i in 1..<9 { a += c[i] / (z + Double(i)) }
        return 0.5 * log(2 * Double.pi) + (z + 0.5) * log(t) - t + log(a)
    }

    /// P(χ²_k ≥ x).
    static func chiSquareSurvival(_ x: Double, k: Int) -> Double { gammaQ(Double(k) / 2, x / 2) }

    /// Inverse of a small symmetric positive-definite matrix (Gauss–Jordan with partial pivoting).
    static func inverse(_ m: [[Double]]) -> [[Double]]? {
        let n = m.count
        var a = m
        var inv = (0..<n).map { i in (0..<n).map { $0 == i ? 1.0 : 0.0 } }
        for col in 0..<n {
            guard let pivot = (col..<n).max(by: { abs(a[$0][col]) < abs(a[$1][col]) }), abs(a[pivot][col]) > 1e-12 else { return nil }
            a.swapAt(col, pivot)
            inv.swapAt(col, pivot)
            let p = a[col][col]
            for j in 0..<n {
                a[col][j] /= p
                inv[col][j] /= p
            }
            for r in 0..<n where r != col {
                let f = a[r][col]
                if f == 0 { continue }
                for j in 0..<n {
                    a[r][j] -= f * a[col][j]
                    inv[r][j] -= f * inv[col][j]
                }
            }
        }
        return inv
    }

    static func matVec(_ m: [[Double]], _ v: [Double]) -> [Double] { m.map { row in zip(row, v).reduce(0) { $0 + $1.0 * $1.1 } } }

    static func dot(_ a: [Double], _ b: [Double]) -> Double { zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } }

    struct Fit {
        /// Coefficients, intercept first.
        var beta: [Double]
        /// Standard errors (same order), nil when the design is singular.
        var se: [Double]?
        var residualSD: Double
        var n: Int

        func predict(_ x: [Double]) -> Double { beta[0] + Num.dot(Array(beta.dropFirst()), x) }
    }

    /// Ridge regression (λ = 0 → OLS) with intercept; `x` rows are observations. The intercept is not penalised.
    static func ridge(_ x: [[Double]], _ y: [Double], lambda: Double = 0) -> Fit? {
        let n = y.count
        guard n == x.count, let p = x.first?.count, n > p + 1 else { return nil }
        let design = x.map { [1.0] + $0 }
        let k = p + 1
        var xtx = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
        var xty = [Double](repeating: 0, count: k)
        for (row, yi) in zip(design, y) {
            for i in 0..<k {
                xty[i] += row[i] * yi
                for j in 0..<k { xtx[i][j] += row[i] * row[j] }
            }
        }
        for i in 1..<k { xtx[i][i] += lambda }
        guard let inv = inverse(xtx) else { return nil }
        let beta = matVec(inv, xty)
        let resid = zip(design, y).map { $1 - dot($0, beta) }
        let dof = max(1, n - k)
        let s2 = resid.reduce(0) { $0 + $1 * $1 } / Double(dof)
        let se = lambda == 0 ? (0..<k).map { (max(0, inv[$0][$0] * s2)).squareRoot() } : nil
        return Fit(beta: beta, se: se, residualSD: s2.squareRoot(), n: n)
    }
}
