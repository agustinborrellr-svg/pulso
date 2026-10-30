import Foundation
import PulsoStore

/// Night-by-night physiological deviation from the wearer's own recent pattern.
///
/// For each night the vector (ln VFC, FC reposo, respiración, temperatura) is standardised against a
/// rolling 28-night window (median / MAD, at least 14 nights). Two distances come out of it:
/// - `mahalanobis` (D): joint distance that accounts for how the signals normally move together
///   (covariance shrunk 30 % towards the identity so it stays stable with few nights). It feeds the
///   "coherencia" score: the percentile rank of tonight's D² among the baseline nights' own D².
/// - `strain` (D⁺): only the "bad" directions (low VFC, high FC / respiración / temperatura), weighted.
///   It feeds recovery tracking after load and the accumulated physiological debt.
public enum Deviation {
    public static let version = "1.0"

    struct Var {
        let key: String
        let label: String
        let value: (DaySummary) -> Double?
        /// Back to the unit people read (ms for the ln VFC).
        let display: (Double) -> Double
        let floor: Double
        /// +1: higher is worse, −1: lower is worse.
        let badSign: Double
        let weight: Double
    }

    static let vars: [Var] = [
        Var(key: "hrv", label: "VFC", value: { $0.hrv.flatMap { $0 > 0 ? log($0) : nil } }, display: { exp($0) }, floor: 0.05, badSign: -1, weight: 0.4),
        Var(key: "rhr", label: "FC en reposo", value: { $0.rhr }, display: { $0 }, floor: 1.0, badSign: 1, weight: 0.3),
        Var(key: "resp", label: "Respiración", value: { $0.respRate }, display: { $0 }, floor: 0.3, badSign: 1, weight: 0.15),
        Var(key: "temp", label: "Temperatura", value: { $0.skinTemp }, display: { $0 }, floor: 0.1, badSign: 1, weight: 0.15),
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
        /// Last night's value and the baseline median, in display units (ms, lpm, rpm, °C).
        public var value: Double = 0
        public var usual: Double = 0
        /// 10th–90th percentile of the baseline nights' own z: the "normal for you" band.
        public var band: ClosedRange<Double> = -1...1
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
        /// This night and how many baseline nights came from an import (measured with another method).
        public var imported: Bool = false
        public var importedInBaseline: Int = 0

        /// Imported and Pulso-measured nights mixed between the night and its reference.
        public var mixesSources: Bool {
            let measured = baselineNights - importedInBaseline
            return (importedInBaseline > 0 && measured > 0) || (imported ? measured > 0 : importedInBaseline > 0)
        }

        /// Signals in the order they're listed (VFC, FC reposo, respiración, temperatura).
        public var signals: [Contributor] {
            Deviation.vars.compactMap { v in contributors.first { $0.key == v.key } }
        }
    }

    /// Whether "anoche" really is last night: the point for that day, or which signals it lacks.
    public struct NightCheck: Equatable, Sendable {
        public var day: String
        public var point: Point?
        /// Labels of the signals missing that night (empty when the night has them all or doesn't exist).
        public var missing: [String]
        /// The night exists in the history at all.
        public var hasNight: Bool
        /// Latest night with a coherence, when it isn't `day`.
        public var latest: Point?
    }

    public static func check(night day: String, days: [DaySummary], series: [Point]) -> NightCheck {
        let d = days.first { $0.day == day }
        let p = series.last { $0.day == day }
        let missing = d.map { s in vars.filter { $0.value(s) == nil }.map(\.label) } ?? []
        return NightCheck(day: day, point: p, missing: missing, hasNight: d != nil,
                          latest: p == nil ? series.last { $0.day < day } : nil)
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
        let rows: [(day: String, x: [Double], imported: Bool)] = sorted.compactMap { d in vector(d).map { (d.day, $0, d.source != "strap") } }
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
            // Coherence = where tonight's D² sits among the baseline nights' own D² (same centre, scale and
            // covariance). The χ²₄ tail over-fires with median/MAD scaling on 14–28 nights (a typical night
            // read ≈ 40 %, and "very unusual" fired 3–6× too often), so the empirical rank is used instead.
            // Beyond every baseline night the rank has no resolution left, so the χ² tail takes over there,
            // capped at the rank's own floor.
            let pastD2 = zPast.map { zp -> Double in max(0, Num.dot(zp, Num.matVec(inv, zp))) }
            let asExtreme = pastD2.filter { $0 >= d2 }.count
            let rankFloor = 100 * 0.5 / (Double(pastD2.count) + 1)
            let coherence = asExtreme > 0
                ? 100 * (Double(asExtreme) + 0.5) / (Double(pastD2.count) + 1)
                : min(rankFloor, 100 * Num.chiSquareSurvival(d2, k: k))
            let contributors = (0..<k).map { j -> Contributor in
                let col = zPast.map { $0[j] }.sorted()
                let lo = col[Int(Double(col.count - 1) * 0.1)], hi = col[Int((Double(col.count - 1) * 0.9).rounded())]
                return Contributor(key: vars[j].key, label: vars[j].label, z: z[j], share: d2 > 1e-9 ? z[j] * w[j] / d2 : 0,
                                   adverse: z[j] * vars[j].badSign > 0, value: vars[j].display(row.x[j]),
                                   usual: vars[j].display(center[j]), band: lo...hi)
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
                             coherence: coherence, contributors: contributors, debt: debt,
                             baselineNights: past.count, imported: row.imported,
                             importedInBaseline: past.filter(\.imported).count))
        }
        return out
    }

    /// "27 oct" for a day key.
    public static func shortDate(_ day: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: day) else { return day }
        f.locale = Locale(identifier: "es_ES")
        f.dateFormat = "d MMM"
        return f.string(from: d).replacingOccurrences(of: ".", with: "")
    }

    static func daysBetween(_ a: String, _ b: String) -> Int {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let da = f.date(from: a), let db = f.date(from: b) else { return 1 }
        return Int((db.timeIntervalSince(da) / 86400).rounded())
    }

    // MARK: - Metrics

    static let coherenceFormula = "z = (valor − mediana) / MAD de tus 28 noches previas para ln VFC, FC reposo, respiración y temperatura; D² = zᵀ Σ⁻¹ z (Σ de esas noches, contraída un 30 %). Coherencia = percentil empírico: 100 · (nº de noches de referencia con D² ≥ el de anoche + 0,5) / (n + 1). Si anoche supera a todas, cola χ²₄ acotada a ese mínimo"
    static let debtFormula = "PD_d = 0,6 · PD_(d−1) + max(0, D⁺_d − 1); D⁺ = desviación ponderada solo en la dirección desfavorable"

    /// Reference length is all the "confidence" this percentile has: say that, not "alta".
    static func referenceNote(_ n: Int) -> String {
        n >= window ? "Referencia completa: \(window) noches" : "Referencia parcial: \(n) de \(window) noches"
    }

    public static func coherenceMetric(_ series: [Point], night: NightCheck? = nil) -> MetricResult {
        let name = "Coherencia fisiológica"
        guard let last = series.last else {
            return .insufficient("coherence", name, unit: "/100",
                                 need: "\(minBaseline) noches con VFC, FC en reposo, respiración y temperatura", have: 0,
                                 formula: coherenceFormula, version: version)
        }
        if let night, night.point == nil {
            let why: String
            if !night.hasNight {
                why = "Anoche aún no está analizada."
            } else if !night.missing.isEmpty {
                why = "Anoche falta " + night.missing.map { $0.lowercased() }.joined(separator: ", ") + ": sin coherencia para esa noche."
            } else {
                why = "Anoche aún no tiene \(minBaseline) noches de referencia."
            }
            let prev = night.latest.map { String(format: " Última noche completa: %@ (%.0f/100).", locale: Num.spanish, shortDate($0.day), $0.coherence) } ?? ""
            return MetricResult(id: "coherence", name: name, value: nil, unit: "/100", summary: why + prev, confidence: .low,
                                sampleSize: last.baselineNights, formula: coherenceFormula, version: version,
                                confidenceNote: referenceNote(last.baselineNights))
        }
        let p = night?.point ?? last
        let top = p.contributors.first { abs($0.share) > 0.25 && abs($0.z) >= 1 }
        var text: String
        switch p.coherence {
        case 50...: text = "Tus constantes de anoche encajan con tu patrón habitual."
        case 10..<50: text = "Combinación algo inusual para ti" + (top.map { ", sobre todo por \($0.label.lowercased()) \(arrow($0))" } ?? "") + "."
        default: text = "Combinación muy poco habitual para ti" + (top.map { ": destaca \($0.label.lowercased()) \(arrow($0))" } ?? "") + ". Pasa con enfermedad, alcohol, viajes o mucho estrés."
        }
        if p.mixesSources { text += " Tu referencia mezcla noches importadas y medidas por Pulso (métodos distintos)." }
        return MetricResult(id: "coherence", name: name, value: p.coherence.rounded(), unit: "/100", summary: text,
                            confidence: .from(samples: p.baselineNights, medium: 20, high: 28), sampleSize: p.baselineNights,
                            formula: coherenceFormula, version: version, confidenceNote: referenceNote(p.baselineNights))
    }

    static func arrow(_ c: Contributor) -> String {
        let dir = c.z > 0 ? "más alta" : "más baja"
        return String(format: "(%@ de lo normal, %.1f σ)", locale: Num.spanish, dir, abs(c.z))
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
