import Foundation
import PulsoStore

/// Night-by-night physiological deviation from the wearer's own recent pattern.
///
/// For each night the vector (ln VFC, FC reposo, respiración, temperatura) is standardised against a
/// rolling 28-night window (median / MAD, at least 14 nights). Two distances come out of it:
/// - `mahalanobis` (D): joint distance that accounts for how the signals normally move together
///   (covariance shrunk 30 % towards the identity so it stays stable with few nights). It feeds the
///   "coherencia" score = P(χ²ₖ ≥ D²), i.e. the share of normal nights at least this unusual.
/// - `strain` (D⁺): only the "bad" directions (low VFC, high FC / respiración / temperatura), weighted.
///   It feeds recovery tracking after load and the accumulated physiological debt.
public enum Deviation {
    public static let version = "1.0"

    struct Var {
        let key: String
        let label: String
        let value: (DaySummary) -> Double?
        let floor: Double
        /// +1: higher is worse, −1: lower is worse.
        let badSign: Double
        let weight: Double
    }

    static let vars: [Var] = [
        Var(key: "hrv", label: "VFC", value: { $0.hrv.flatMap { $0 > 0 ? log($0) : nil } }, floor: 0.05, badSign: -1, weight: 0.4),
        Var(key: "rhr", label: "FC en reposo", value: { $0.rhr }, floor: 1.0, badSign: 1, weight: 0.3),
        Var(key: "resp", label: "Respiración", value: { $0.respRate }, floor: 0.3, badSign: 1, weight: 0.15),
        Var(key: "temp", label: "Temperatura", value: { $0.skinTemp }, floor: 0.1, badSign: 1, weight: 0.15),
    ]

    public struct Contributor: Equatable, Sendable {
        public var key: String
        public var label: String
        /// Standardised deviation (σ units, sign as measured).
        public var z: Double
        /// Share of D² explained (can be negative when a signal compensates another).
        public var share: Double
        /// True when this deviation goes in the unhealthy direction.
        public var adverse: Bool
    }

    public struct Point: Equatable, Sendable {
        public var day: String
        public var mahalanobis: Double
        public var strain: Double
        /// 0–100: how usual tonight's combination is for you (100 = completely typical).
        public var coherence: Double
        public var contributors: [Contributor]
        /// Accumulated physiological debt up to this night.
        public var debt: Double
        public var baselineNights: Int
    }

    public static let minBaseline = 14
    public static let window = 28
    public static let debtDecay = 0.6
    public static let debtThreshold = 1.0

    static func vector(_ d: DaySummary) -> [Double]? {
        var out: [Double] = []
        for v in vars {
            guard let x = v.value(d) else { return nil }
            out.append(x)
        }
        return out
    }

    /// One point per night that has all signals and enough history before it.
    public static func series(_ days: [DaySummary]) -> [Point] {
        let sorted = days.sorted { $0.day < $1.day }
        let rows: [(day: String, x: [Double])] = sorted.compactMap { d in vector(d).map { (d.day, $0) } }
        var out: [Point] = []
        var debt = 0.0
        var lastDay: String?
        let k = vars.count
        for (i, row) in rows.enumerated() {
            let past = Array(rows[max(0, i - window)..<i])
            guard past.count >= minBaseline else { continue }
            // Robust centre / scale per variable.
            var center = [Double](repeating: 0, count: k), scale = [Double](repeating: 1, count: k)
            for j in 0..<k {
                let col = past.map { $0.x[j] }
                center[j] = Num.median(col) ?? 0
                scale[j] = max(Num.mad(col) ?? vars[j].floor, vars[j].floor)
            }
            func standardise(_ x: [Double]) -> [Double] { (0..<k).map { Num.clamp((x[$0] - center[$0]) / scale[$0], -6, 6) } }
            let zPast = past.map { standardise($0.x) }
            // Correlation-like covariance of the standardised history, shrunk towards I.
            var cov = [[Double]](repeating: [Double](repeating: 0, count: k), count: k)
            let means = (0..<k).map { j in Num.mean(zPast.map { $0[j] }) ?? 0 }
            for a in 0..<k {
                for b in 0..<k {
                    var s = 0.0
                    for z in zPast { s += (z[a] - means[a]) * (z[b] - means[b]) }
                    cov[a][b] = s / Double(max(1, zPast.count - 1))
                }
            }
            let alpha = 0.3
            for a in 0..<k {
                for b in 0..<k { cov[a][b] = (1 - alpha) * cov[a][b] + (a == b ? alpha * max(1, cov[a][a]) : 0) }
            }
            let z = standardise(row.x)
            guard let inv = Num.inverse(cov) else { continue }
            let w = Num.matVec(inv, z)
            let d2 = max(0, Num.dot(z, w))
            let contributors = (0..<k).map { j in
                Contributor(key: vars[j].key, label: vars[j].label, z: z[j], share: d2 > 1e-9 ? z[j] * w[j] / d2 : 0,
                            adverse: z[j] * vars[j].badSign > 0)
            }.sorted { abs($0.share) > abs($1.share) }
            let wsum = vars.reduce(0) { $0 + $1.weight }
            let dPlus = ((0..<k).reduce(0.0) { acc, j in
                let bad = max(0, z[j] * vars[j].badSign)
                return acc + vars[j].weight * bad * bad
            } / wsum).squareRoot()
            // Debt decays on missing nights too.
            if let last = lastDay {
                let gap = max(1, daysBetween(last, row.day))
                debt *= pow(debtDecay, Double(gap - 1))
            }
            debt = debtDecay * debt + max(0, dPlus - debtThreshold)
            lastDay = row.day
            out.append(Point(day: row.day, mahalanobis: d2.squareRoot(), strain: dPlus,
                             coherence: 100 * Num.chiSquareSurvival(d2, k: k), contributors: contributors, debt: debt,
                             baselineNights: past.count))
        }
        return out
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let da = f.date(from: a), let db = f.date(from: b) else { return 1 }
        return Int((db.timeIntervalSince(da) / 86400).rounded())
    }

    // MARK: - Metrics

    static let coherenceFormula = "D² = zᵀ Σ⁻¹ z sobre (ln VFC, FC reposo, respiración, temperatura) frente a tus 28 noches previas (mediana/MAD, Σ con contracción 30 %); coherencia = 100 · P(χ²₄ ≥ D²)"
    static let debtFormula = "PD_d = 0,6 · PD_(d−1) + max(0, D⁺_d − 1); D⁺ = desviación ponderada solo en la dirección desfavorable"

    public static func coherenceMetric(_ series: [Point]) -> MetricResult {
        guard let p = series.last else {
            return .insufficient("coherence", "Coherencia fisiológica", unit: "/100",
                                 need: "\(minBaseline) noches con VFC, FC en reposo, respiración y temperatura", have: 0,
                                 formula: coherenceFormula, version: version)
        }
        let top = p.contributors.first { abs($0.share) > 0.25 && abs($0.z) >= 1 }
        let text: String
        switch p.coherence {
        case 50...: text = "Tus constantes de anoche encajan con tu patrón habitual."
        case 10..<50: text = "Combinación algo inusual para ti" + (top.map { ", sobre todo por \($0.label.lowercased()) \(arrow($0))" } ?? "") + "."
        default: text = "Combinación muy poco habitual para ti" + (top.map { ": destaca \($0.label.lowercased()) \(arrow($0))" } ?? "") + ". Pasa con enfermedad, alcohol, viajes o mucho estrés."
        }
        return MetricResult(id: "coherence", name: "Coherencia fisiológica", value: p.coherence.rounded(), unit: "/100", summary: text,
                            confidence: .from(samples: p.baselineNights, medium: 20, high: 28), sampleSize: p.baselineNights,
                            formula: coherenceFormula, version: version)
    }

    static func arrow(_ c: Contributor) -> String {
        let dir = c.z > 0 ? "más alta" : "más baja"
        return String(format: "(%@ de lo normal, %.1f σ)", dir, abs(c.z))
    }

    public static func debtMetric(_ series: [Point]) -> MetricResult {
        guard let p = series.last else {
            return .insufficient("physDebt", "Deuda fisiológica", need: "\(minBaseline) noches completas", have: 0,
                                 formula: debtFormula, version: version)
        }
        let week = series.suffix(7).map { $0.debt }
        let trend = week.count >= 2 ? week.last! - week.first! : 0
        let level: String
        switch p.debt {
        case ..<0.3: level = "Sin alteración acumulada."
        case ..<1.5: level = "Algo de alteración acumulada estos días."
        default: level = "Llevas varios días con tus constantes fuera de lo habitual: tu cuerpo está acumulando carga."
        }
        let t = abs(trend) < 0.2 ? "" : (trend > 0 ? " Subiendo esta semana." : " Bajando esta semana.")
        return MetricResult(id: "physDebt", name: "Deuda fisiológica", value: (p.debt * 10).rounded() / 10, unit: "",
                            summary: level + t, confidence: .from(samples: p.baselineNights, medium: 20, high: 28),
                            sampleSize: series.count, formula: debtFormula, version: version)
    }
}
