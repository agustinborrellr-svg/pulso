import Foundation
import PulsoStore

/// What happens to the wearer's physiology in the nights after a hard day.
///
/// A load day is a day with Strain ≥ max(12, your 75th percentile) or a workout with Strain ≥ 8.
/// The adverse deviation D⁺ of the following nights (see `Deviation`) is followed until it drops
/// under 1 σ. From that curve:
/// - recovery time (nights, interpolated where D⁺ crosses the threshold),
/// - recovery cost = Σ D⁺ of the nights still out of range (area under the curve),
/// - peak deviation and first-night changes of VFC / FC en reposo / respiración.
/// Events followed by another load day before recovering are kept apart ("carga encadenada").
public enum LoadResponse {
    public static let version = "1.0"
    public static let threshold = 1.0
    public static let maxNights = 5

    public struct Event: Equatable, Sendable {
        public var day: String
        public var sport: String
        public var strain: Double
        /// Strain of the 3 days ending on the load day (for the ceiling analysis).
        public var load3d: Double
        public var intensity: String
        /// Nights until back in range (fractional), nil if never within `maxNights`.
        public var recoveryNights: Double?
        public var cost: Double
        public var peak: Double
        public var hrvChangePct: Double?
        public var rhrChange: Double?
        public var respChange: Double?
        /// Another load day came before recovering: not a clean measurement.
        public var chained: Bool
        /// All `maxNights` nights were measured and none was back in range: recovery took at least that long.
        public var censored: Bool = false

        /// Nights to recover counting overloads as `maxNights` (a lower bound); nil when the nights weren't measured.
        public var nightsAtLeast: Double? { recoveryNights ?? (censored ? Double(LoadResponse.maxNights) : nil) }
    }

    static func intensity(_ strain: Double) -> String {
        strain >= 17 ? "muy alta" : (strain >= 13 ? "alta" : "moderada")
    }

    public static func events(days: [DaySummary], deviation: [Deviation.Point], workouts: [Workout]) -> [Event] {
        let sorted = days.sorted { $0.day < $1.day }
        let strains = sorted.compactMap { $0.strain }
        let p75 = strains.count >= 8 ? (strains.sorted()[Int(Double(strains.count - 1) * 0.75)]) : 12
        let loadCut = max(12, p75)
        let devByDay = Dictionary(deviation.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let byDay = Dictionary(sorted.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        func workoutsOn(_ d: DaySummary) -> [Workout] {
            guard let a = d.cycleStart, let b = d.cycleEnd else { return [] }
            return workouts.filter { $0.start >= a && $0.start < b }
        }
        func isLoad(_ d: DaySummary) -> Bool {
            (d.strain ?? 0) >= loadCut || workoutsOn(d).contains { $0.strain >= 8 }
        }
        var out: [Event] = []
        for (i, d) in sorted.enumerated() where isLoad(d) {
            // Nights after the load day = the deviation points of the following days.
            var curve: [Double] = []
            var chained = false
            for n in 1...maxNights {
                let key = shift(d.day, n)
                guard let p = devByDay[key] else { break }
                curve.append(p.strain)
                if p.strain <= threshold { break }
                if let next = byDay[key], isLoad(next) { chained = true }
            }
            guard !curve.isEmpty else { continue }
            var rec: Double?
            if curve[0] <= threshold {
                // Already back in range on the first night: zero nights, not a σ ratio dressed as nights.
                rec = 0
            } else if let j = curve.firstIndex(where: { $0 <= threshold }) {
                let a = curve[j - 1], b = curve[j]
                rec = Double(j) + (a - threshold) / max(1e-6, a - b)
            }
            let outOfRange = curve.prefix { $0 > threshold }
            let main = workoutsOn(d).max { $0.strain < $1.strain }
            let last3 = sorted[max(0, i - 2)...i].compactMap { $0.strain }.reduce(0, +)
            // First-night changes vs the 14 nights before the load day.
            let before = sorted[max(0, i - 14)..<i]
            let next = byDay[shift(d.day, 1)]
            func change(_ v: (DaySummary) -> Double?) -> Double? {
                guard let x = next.flatMap(v), let base = Num.median(before.compactMap(v)) else { return nil }
                return x - base
            }
            var hrvPct: Double?
            if let x = next?.hrv, let base = Num.median(before.compactMap { $0.hrv }), base > 0 { hrvPct = (x / base - 1) * 100 }
            out.append(Event(day: d.day, sport: main?.sport ?? "Día exigente", strain: d.strain ?? main?.strain ?? 0, load3d: last3,
                             intensity: intensity(d.strain ?? 0), recoveryNights: rec, cost: outOfRange.reduce(0, +),
                             peak: curve.max() ?? 0, hrvChangePct: hrvPct, rhrChange: change { $0.rhr }, respChange: change { $0.respRate },
                             chained: chained, censored: rec == nil && curve.count == maxNights))
        }
        return out
    }

    static func shift(_ day: String, _ n: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        guard let d = f.date(from: day) else { return day }
        return f.string(from: d.addingTimeInterval(Double(n) * 86400))
    }

    // MARK: - Metrics

    static func clean(_ e: [Event]) -> [Event] { e.filter { !$0.chained } }

    public static func velocityMetric(_ events: [Event]) -> MetricResult {
        let f = "Noches hasta que D⁺ vuelve por debajo de 1 σ tras un día exigente (interpolado; sin volver en 5 noches = 5); mediana de los últimos 10"
        let rec = clean(events).suffix(10).compactMap { $0.nightsAtLeast }
        guard rec.count >= 3, let med = Num.median(rec) else {
            return .insufficient("recoveryVelocity", "Velocidad de recuperación", unit: "noches",
                                 need: "3 días exigentes con las noches siguientes medidas", have: rec.count, formula: f, version: version)
        }
        let text: String
        switch med {
        case ..<1: text = "Tras un día exigente, tus constantes vuelven a lo normal en la primera noche."
        case ..<2: text = String(format: "Tras un día exigente tardas unas %.1f noches en volver a tu patrón.", locale: Num.spanish, med)
        default: text = String(format: "Tras un día exigente tardas %.1f noches en volver a tu patrón: recuperas despacio.", locale: Num.spanish, med)
        }
        return MetricResult(id: "recoveryVelocity", name: "Velocidad de recuperación", value: (med * 10).rounded() / 10, unit: "noches",
                            summary: text, interval: (rec.min() ?? med)...(rec.max() ?? med),
                            confidence: .from(samples: rec.count, medium: 5, high: 10), sampleSize: rec.count, formula: f, version: version)
    }

    public static func efficiencyMetric(_ events: [Event]) -> MetricResult {
        let f = "RE = Σ D⁺ de las noches fuera de rango tras la carga (área bajo la curva de alteración); menor = mejor"
        let ev = clean(events).suffix(10)
        guard ev.count >= 3, let med = Num.median(ev.map { $0.cost }) else {
            return .insufficient("recoveryEfficiency", "Coste de recuperación", need: "3 días exigentes medidos", have: ev.count,
                                 formula: f, version: version)
        }
        let text = med < 0.5 ? "Los días exigentes apenas te desajustan." :
            (med < 2.5 ? "Coste de recuperación moderado tras los días exigentes." : "Los días exigentes te desajustan bastante y durante varias noches.")
        return MetricResult(id: "recoveryEfficiency", name: "Coste de recuperación", value: (med * 10).rounded() / 10, unit: "σ·noche",
                            summary: text, confidence: .from(samples: ev.count, medium: 5, high: 10), sampleSize: ev.count,
                            formula: f, version: version)
    }

    public static func consistencyMetric(_ events: [Event]) -> MetricResult {
        let f = "RCS = 100 · exp(−CV) del tiempo de recuperación en sesiones comparables"
        // Most frequent bucket = comparable sessions.
        let groups = Dictionary(grouping: clean(events).filter { $0.recoveryNights != nil }) { "\($0.sport)|\($0.intensity)" }
        guard let best = groups.max(by: { $0.value.count < $1.value.count }), best.value.count >= 4 else {
            return .insufficient("recoveryConsistency", "Consistencia de recuperación", unit: "/100",
                                 need: "4 sesiones comparables (mismo deporte e intensidad)", have: groups.values.map { $0.count }.max() ?? 0,
                                 formula: f, version: version)
        }
        let t = best.value.compactMap { $0.recoveryNights }.map { $0 + 0.25 } // small offset: CV stays defined near 0
        guard let m = Num.mean(t), let s = Num.sd(t), m > 0 else {
            return .insufficient("recoveryConsistency", "Consistencia de recuperación", unit: "/100", need: "más sesiones", have: t.count,
                                 formula: f, version: version)
        }
        let rcs = 100 * exp(-s / m)
        let parts = best.key.split(separator: "|")
        return MetricResult(id: "recoveryConsistency", name: "Consistencia de recuperación", value: rcs.rounded(), unit: "/100",
                            summary: "En \(parts[0].lowercased()) de intensidad \(parts.count > 1 ? parts[1] : ""), tu recuperación es " +
                                (rcs >= 70 ? "muy predecible." : (rcs >= 45 ? "bastante regular." : "muy variable: depende de otros factores (sueño, estrés…).")),
                            confidence: .from(samples: t.count, medium: 6, high: 12), sampleSize: t.count, formula: f, version: version)
    }

    /// Is the cost of comparable sessions going down over time? OLS of cost on (date, strain).
    public static func adaptationMetric(_ events: [Event]) -> MetricResult {
        let f = "Regresión cost ~ fecha + esfuerzo en sesiones limpias; pendiente por 30 días con IC 90 %"
        let ev = clean(events)
        guard ev.count >= 8, let first = ev.first?.day else {
            return .insufficient("adaptation", "Adaptación a la carga", need: "8 días exigentes medidos (unas 4–6 semanas)", have: ev.count,
                                 formula: f, version: version)
        }
        let x = ev.map { [Double(Deviation.daysBetween(first, $0.day)) / 30, $0.strain] }
        let y = ev.map { $0.cost }
        guard let fit = Num.ridge(x, y), let se = fit.se else {
            return .insufficient("adaptation", "Adaptación a la carga", need: "más variedad de días", have: ev.count, formula: f, version: version)
        }
        let slope = fit.beta[1], half = Num.tCritical(df: fit.n - 3) * se[1]
        let ci = (slope - half)...(slope + half)
        let text: String
        if ci.upperBound < 0 {
            text = "A igual esfuerzo, cada vez te desajustas menos: te estás adaptando."
        } else if ci.lowerBound > 0 {
            text = "A igual esfuerzo, cada vez te cuesta más recuperarte: vigila fatiga, sueño y estrés."
        } else {
            text = "Tu respuesta a cargas parecidas se mantiene estable."
        }
        return MetricResult(id: "adaptation", name: "Adaptación a la carga", value: (slope * 100).rounded() / 100, unit: "σ·noche / 30 d",
                            summary: text, interval: ci, confidence: .from(samples: ev.count, medium: 12, high: 20), sampleSize: ev.count,
                            formula: f, version: version)
    }

    /// Recovery time against the 3-day load, overloads included as "≥ 5 nights" (dropping them hid exactly
    /// the cases a ceiling is about).
    public struct Ceiling: Equatable, Sendable {
        public struct Point: Equatable, Sendable {
            public var day: String
            public var load: Double
            public var nights: Double
            public var censored: Bool
        }
        public var points: [Point]
        /// Load where the slope breaks; nil when there's no knee (or too few points).
        public var knee: Double?
        public var slopeBelow: Double?
        public var slopeAbove: Double?
        public var overloads: Int { points.filter(\.censored).count }
    }

    public static let minCeilingEvents = 20

    public static func ceiling(_ events: [Event]) -> Ceiling {
        let pts = events.compactMap { e in e.nightsAtLeast.map { Ceiling.Point(day: e.day, load: e.load3d, nights: $0, censored: e.censored) } }
            .sorted { $0.load < $1.load }
        var out = Ceiling(points: pts)
        guard pts.count >= minCeilingEvents else { return out }
        let y = pts.map(\.nights)
        guard let lin = Num.ridge(pts.map { [$0.load] }, y) else { return out }
        func sse(_ f: Num.Fit, _ x: [[Double]]) -> Double { zip(x, y).reduce(0) { $0 + pow($1.1 - f.predict($1.0), 2) } }
        let linSSE = sse(lin, pts.map { [$0.load] })
        out.slopeBelow = lin.beta[1]
        // Continuous hinge y = a + b·load + c·max(0, load − k): a cluster of "≥ 5 nights" above the knee reads as
        // a steeper segment, which two separate fits (both flat) would miss.
        var best: (knee: Double, sse: Double, below: Double, above: Double)?
        for q in stride(from: 0.3, through: 0.8, by: 0.05) {
            let k = pts[Int(Double(pts.count) * q)].load
            let x = pts.map { [$0.load, max(0, $0.load - k)] }
            guard x.filter({ $0[1] > 0 }).count >= 5, let f = Num.ridge(x, y) else { continue }
            let e = sse(f, x)
            if e < (best?.sse ?? .infinity) { best = (k, e, f.beta[1], f.beta[1] + f.beta[2]) }
        }
        if let b = best, b.sse < linSSE * 0.85, b.above > max(0.01, 2 * b.below) {
            out.knee = b.knee
            out.slopeBelow = b.below
            out.slopeAbove = b.above
        }
        return out
    }

    /// Load above which recovery time grows disproportionately (piecewise-linear knee).
    public static func ceilingMetric(_ events: [Event]) -> MetricResult {
        let f = "Recta con codo (continua) de noches hasta recuperarte ~ esfuerzo acumulado 3 días (sin recuperar en 5 noches = 5, cota inferior); codo si mejora el error > 15 % frente a una recta y la pendiente al menos se duplica"
        let c = ceiling(events)
        guard c.points.count >= minCeilingEvents else {
            return .insufficient("recoveryCeiling", "Techo de carga", need: "\(minCeilingEvents) días exigentes medidos (unos 2–3 meses)", have: c.points.count,
                                 formula: f, version: version)
        }
        let over = c.overloads > 0 ? " \(c.overloads) \(c.overloads == 1 ? "vez" : "veces") no te recuperaste en \(maxNights) noches." : ""
        let conf = MetricResult.Confidence.from(samples: c.points.count, medium: 30, high: 50)
        guard let knee = c.knee else {
            let hi = c.points.map(\.load).max() ?? 0
            return MetricResult(id: "recoveryCeiling", name: "Techo de carga", value: nil, unit: "esfuerzo 3 días",
                                summary: String(format: "No se ve límite: hasta %.0f puntos de esfuerzo en 3 días, tu recuperación crece en proporción a la carga.", locale: Num.spanish, hi) + over,
                                confidence: conf, sampleSize: c.points.count, formula: f, version: version)
        }
        return MetricResult(id: "recoveryCeiling", name: "Techo de carga", value: knee.rounded(), unit: "esfuerzo 3 días",
                            summary: String(format: "Por encima de unos %.0f puntos de esfuerzo en 3 días, tu recuperación se alarga mucho más que la carga.", locale: Num.spanish, knee) + over,
                            confidence: conf, sampleSize: c.points.count, formula: f, version: version)
    }

    /// Response fingerprint per sport and intensity (medians), buckets with ≥ 3 clean sessions.
    public struct Fingerprint: Equatable, Sendable, Identifiable {
        public var id: String { "\(sport)|\(intensity)" }
        public var sport: String
        public var intensity: String
        public var count: Int
        public var recoveryNights: Double?
        public var cost: Double
        public var peak: Double
        public var hrvChangePct: Double?
        public var rhrChange: Double?
        public var respChange: Double?
    }

    public static func fingerprints(_ events: [Event]) -> [Fingerprint] {
        Dictionary(grouping: clean(events)) { "\($0.sport)|\($0.intensity)" }.compactMap { _, g -> Fingerprint? in
            guard g.count >= 3, let e = g.first else { return nil }
            return Fingerprint(sport: e.sport, intensity: e.intensity, count: g.count, recoveryNights: Num.median(g.compactMap { $0.nightsAtLeast }),
                               cost: Num.median(g.map { $0.cost }) ?? 0, peak: Num.median(g.map { $0.peak }) ?? 0,
                               hrvChangePct: Num.median(g.compactMap { $0.hrvChangePct }), rhrChange: Num.median(g.compactMap { $0.rhrChange }),
                               respChange: Num.median(g.compactMap { $0.respChange }))
        }.sorted { $0.count > $1.count }
    }
}
