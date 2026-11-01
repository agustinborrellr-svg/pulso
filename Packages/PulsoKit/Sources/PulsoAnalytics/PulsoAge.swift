import Foundation
import PulsoStore

/// "Edad Pulso": your age plus the years your habits add or take off, from published all-cause mortality studies.
///
/// For each habit, a dose–response curve from the literature gives the relative risk of death at your level
/// compared with meeting the public-health guideline (the neutral point, 0 years). A relative risk becomes years
/// with the Gompertz law: adult mortality grows about 8.5 % per year of age (it doubles every ~8 years), so a risk
/// ×RR is the risk of someone ln(RR) / 0.085 years older.
///
/// Curves (relative risk of all-cause mortality):
/// - Sleep duration: lowest at 7–8 h; RR 1.06 per hour below 7 h (Liu et al., JAHA 2017 dose–response
///   meta-analysis); RR 1.30 at ≥ 9 h (Cappuccio et al., Sleep 2010).
/// - Sleep regularity: RR 1.53 at the 5th percentile (41), 1 at the median (~60), 0.90 at the 95th (75)
///   (Pase et al., eLife 2023, UK Biobank).
/// - Steps: RR 0.53 at 7 000 vs 2 000 steps/day, little extra benefit beyond (Ding et al., Lancet Public Health 2025).
/// - Moderate activity (zones 1-3): RR ≈0.79 at 150, 0.72 at 300 and 0.65 from ~600 min/week (Lee et al.,
///   Circulation 2022; device-measured plateau 0.6–0.7, UK Biobank).
/// - Vigorous activity (zones 4-5): optimal ≈54 min/week with RR 0.64; half the benefit at ≈15 min
///   (Ahmadi et al., Eur Heart J 2022).
/// - Strength: RR 0.85 at 30–60 min/week, back to 1 around 140 min/week (J-shape; Momma et al., BJSM 2022).
/// - VO₂max: RR 0.86 per MET (3.5 ml/kg/min) vs the average of your age and sex, up to the high-vs-low
///   difference of RR 0.47 (Lang et al., BJSM 2024; JSHS 2025 meta-analysis).
/// - Resting heart rate: RR 1.09 per 10 bpm, from 0.89 to 1.45 (Zhang et al., CMAJ 2016).
///
/// The guidelines count moderate minutes, vigorous minutes and steps as interchangeable ways of doing your aerobic
/// activity, so only the best of the three counts towards the total (the others are the same habit measured twice).
///
/// Windows: the age uses your last 90 days and is recalculated once a week; the last 30 days show where you are now
/// and set the pace of ageing.
public enum PulsoAge {
    /// Gompertz rate of ageing of adult mortality (per year).
    public static let gompertz = 0.085

    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let group: String
        public let unit: String
        /// Last 30 days ("ahora").
        public let recent: Double?
        /// Last 90 days: what the age uses.
        public let longTerm: Double?
        /// Ends and neutral point of the bar.
        public let poor: Double
        public let neutral: Double
        public let optimal: Double
        /// Years this habit adds (+) or takes off (−) over the 90 days.
        public let years: Double?
        /// Years with the last 30 days.
        public let recentYears: Double?
        /// False when another measure of the same habit counts instead (aerobic activity).
        public let counted: Bool
        /// The study behind it.
        public let source: String

        /// 0 = poor end, 1 = optimal end.
        public func position(_ v: Double?) -> Double? {
            guard let v else { return nil }
            return Stats.clamp((v - poor) / (optimal - poor), 0, 1)
        }

        /// Where «adds nothing» sits on the bar.
        public var neutralPosition: Double { Stats.clamp((neutral - poor) / (optimal - poor), 0, 1) }
    }

    public struct Result: Equatable, Sendable {
        public let age: Double
        public let pulsoAge: Double?
        /// Years older (+) or younger (−) than your real age.
        public let difference: Double?
        /// Edad Pulso with your last 30 days.
        public let recentAge: Double?
        /// Years of Edad Pulso per calendar year at the current trend (1 = like the calendar, 0 = steady, < 0 younger).
        public let pace: Double?
        public let items: [Item]
        public let measured: Int
    }

    /// A dose–response curve: (value, relative risk) points, log-linear between them and flat outside.
    struct Curve {
        let points: [(Double, Double)]

        func rr(_ v: Double) -> Double {
            let p = points.sorted { $0.0 < $1.0 }
            guard let first = p.first, let last = p.last else { return 1 }
            if v <= first.0 { return first.1 }
            if v >= last.0 { return last.1 }
            for i in 1..<p.count where v <= p[i].0 {
                let (x0, y0) = p[i - 1], (x1, y1) = p[i]
                let t = (v - x0) / (x1 - x0)
                return exp(log(y0) + t * (log(y1) - log(y0)))
            }
            return last.1
        }
    }

    struct Spec {
        let key: String, label: String, group: String, unit: String
        let poor: Double, neutral: Double, optimal: Double
        let curve: Curve
        let source: String
        let aggregate: TrendSeries.Aggregate
        let value: (DaySummary) -> Double?

        /// Years vs meeting the guideline: ln(RR(v) / RR(neutral)) / Gompertz rate.
        func years(_ v: Double?) -> Double? {
            guard let v else { return nil }
            return log(curve.rr(v) / curve.rr(neutral)) / PulsoAge.gompertz
        }
    }

    /// Sports that count as strength training.
    static let strengthSports: Set<String> = ["Fuerza", "Entrenamiento funcional", "Core / abdominales", "Calistenia", "Crossfit", "HIIT"]
    /// Habits that are the same aerobic activity measured three ways.
    static let aerobicKeys: Set<String> = ["zonesLight", "zonesHard", "steps"]

    static func specs(age: Int, sex: Sex, zones: @escaping (DaySummary) -> [Double]?, strength: @escaping (DaySummary) -> Double?) -> [Spec] {
        // VO₂max of a population-average person of your age and sex (Fitness.fitnessAge in reverse).
        let base = sex == .female ? 39.0 : (sex == .male ? 47.0 : 43.0)
        let average = base - 0.4 * Double(max(0, age - 20))
        // RR 0.86 per MET (3.5 ml/kg/min), bounded to half the high-vs-low difference (RR 0.47) on each side:
        // the bound is reached 8.8 ml/kg/min from the average.
        let cap = sqrt(0.47), reach = 3.5 * log(cap) / log(0.86)
        let vo2 = Curve(points: [(average - reach, 1 / cap), (average + reach, cap)])
        return [
            Spec(key: "sleepHours", label: "Horas de sueño", group: "Sueño", unit: "h", poor: 5 * 60, neutral: 7.5 * 60, optimal: 8 * 60,
                 curve: Curve(points: [(300, 1.06 * 1.06), (360, 1.06), (420, 1), (480, 1), (540, 1.30)]),
                 source: "Liu 2017 (JAHA) y Cappuccio 2010 (Sleep)", aggregate: .average, value: { $0.sleepMinutes }),
            Spec(key: "regularity", label: "Regularidad del sueño", group: "Sueño", unit: "%", poor: 40, neutral: 60, optimal: 100,
                 curve: Curve(points: [(41, 1.53), (60, 1), (75, 0.90)]),
                 source: "Pase 2023 (eLife, UK Biobank)", aggregate: .average, value: { $0.sleepConsistency }),
            Spec(key: "zonesLight", label: "Tiempo en zonas de FC 1-3 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 150, optimal: 600,
                 curve: Curve(points: [(0, 1), (150, 0.79), (300, 0.72), (600, 0.65)]),
                 source: "Lee 2022 (Circulation)", aggregate: .total, value: { d in zones(d).map { $0.prefix(3).reduce(0, +) } }),
            Spec(key: "zonesHard", label: "Tiempo en zonas de FC 4-5 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 75, optimal: 120,
                 curve: Curve(points: [(2, 1), (15, 0.80), (54, 0.64)]),
                 source: "Ahmadi 2022 (Eur Heart J)", aggregate: .total, value: { d in zones(d).map { $0.dropFirst(3).reduce(0, +) } }),
            Spec(key: "strength", label: "Tiempo de actividad de fuerza (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 60, optimal: 150,
                 curve: Curve(points: [(0, 1), (30, 0.85), (60, 0.85), (140, 1)]),
                 source: "Momma 2022 (BJSM)", aggregate: .total, value: strength),
            Spec(key: "steps", label: "Pasos", group: "Esfuerzo", unit: "pasos", poor: 2000, neutral: 7000, optimal: 12000,
                 curve: Curve(points: [(2000, 1), (7000, 0.53)]),
                 source: "Ding 2025 (Lancet Public Health)", aggregate: .average, value: { $0.steps.map(Double.init) }),
            Spec(key: "vo2max", label: "VO₂ máx (estimado)", group: "Fitness", unit: "ml/kg/min", poor: average - 14, neutral: average, optimal: average + 14,
                 curve: vo2, source: "Lang 2024 (BJSM)", aggregate: .average, value: { $0.vo2max }),
            Spec(key: "rhr", label: "FC en reposo", group: "Fitness", unit: "lpm", poor: 80, neutral: 60, optimal: 45,
                 curve: Curve(points: [(47, 0.89), (60, 1), (70, 1.09), (80, 1.188), (100, 1.45)]),
                 source: "Zhang 2016 (CMAJ)", aggregate: .average, value: { $0.rhr }),
        ]
    }

    /// Average per day, or minutes per week for `.total`, of the days in [from, to] that have a value.
    static func window(_ days: [DaySummary], from: String, to: String, aggregate: TrendSeries.Aggregate,
                       value: (DaySummary) -> Double?, minDays: Int) -> Double? {
        let v = days.filter { $0.day >= from && $0.day <= to }.compactMap(value)
        guard v.count >= minDays else { return nil }
        let mean = v.reduce(0, +) / Double(v.count)
        return aggregate == .total ? mean * 7 : mean
    }

    /// `today` is the day the age is calculated for (the app passes the start of the week, so it changes weekly):
    /// it uses the complete days before it. Imported days have no whole-day zones: their workouts' zone minutes and
    /// strength sessions count instead.
    public static func compute(days: [DaySummary], profile: Profile, today: String, workouts: [Workout] = [],
                               calendar: Calendar = .current) -> Result {
        let days = days.filter { $0.day < today }
        let end = DayKey.shift(today, days: -1, calendar: calendar)
        let from90 = DayKey.shift(today, days: -90, calendar: calendar)
        let from30 = DayKey.shift(today, days: -30, calendar: calendar)
        var byDay: [String: [Workout]] = [:]
        for w in workouts { byDay[DayKey.string(ts: w.start, calendar: calendar), default: []].append(w) }
        let zones: (DaySummary) -> [Double]? = { d in
            guard d.strain != nil else { return nil }
            if d.source == "strap" { return d.zoneMinutes }
            let ws = byDay[d.day] ?? []
            return (0..<5).map { z in ws.reduce(0) { $0 + (z < $1.zoneMinutes.count ? $1.zoneMinutes[z] : 0) } }
        }
        let strength: (DaySummary) -> Double? = { d in
            guard d.strain != nil else { return nil }
            return (byDay[d.day] ?? []).filter { strengthSports.contains($0.sport) }.reduce(0) { $0 + Double($1.end - $1.start) / 60 }
        }
        let age = Double(profile.age)
        let specs = specs(age: profile.age, sex: profile.sex, zones: zones, strength: strength)
        var raw: [(spec: Spec, long: Double?, recent: Double?, y: Double?, ry: Double?)] = []
        for s in specs {
            // 90 days need three weeks of readings; 30 days, one.
            let long = window(days, from: from90, to: end, aggregate: s.aggregate, value: s.value, minDays: 21)
            let recent = window(days, from: from30, to: end, aggregate: s.aggregate, value: s.value, minDays: 7)
            raw.append((s, long, recent, s.years(long), s.years(recent)))
        }
        // Aerobic activity counts once: the best of moderate minutes, vigorous minutes and steps.
        func bestAerobic(_ pick: (Double?, Double?) -> Double?) -> String? {
            raw.filter { aerobicKeys.contains($0.spec.key) }
                .compactMap { r in pick(r.y, r.ry).map { (r.spec.key, $0) } }
                .min { $0.1 < $1.1 }?.0
        }
        let countedLong = bestAerobic { y, _ in y }
        let countedRecent = bestAerobic { _, ry in ry }
        var items: [Item] = []
        var total = 0.0, recentTotal = 0.0, measured = 0, measuredRecent = 0
        for r in raw {
            let aerobic = aerobicKeys.contains(r.spec.key)
            let counted = !aerobic || r.spec.key == countedLong
            items.append(Item(key: r.spec.key, label: r.spec.label, group: r.spec.group, unit: r.spec.unit, recent: r.recent,
                              longTerm: r.long, poor: r.spec.poor, neutral: r.spec.neutral, optimal: r.spec.optimal,
                              years: r.y, recentYears: r.ry, counted: counted, source: r.spec.source))
            if let y = r.y, counted { total += y; measured += 1 }
            if let ry = r.ry, !aerobic || r.spec.key == countedRecent { recentTotal += ry; measuredRecent += 1 }
        }
        guard measured >= 4 else {
            return Result(age: age, pulsoAge: nil, difference: nil, recentAge: nil, pace: nil, items: items, measured: measured)
        }
        let recentAge = measuredRecent >= 4 ? age + recentTotal : nil
        // The 30- and 90-day windows are centred 30 days apart: the gap is how far Edad Pulso moved in a month.
        let pace = recentAge.map { Stats.clamp(1 + 12 * ($0 - (age + total)), -1, 3) }
        return Result(age: age, pulsoAge: age + total, difference: total, recentAge: recentAge, pace: pace, items: items, measured: measured)
    }
}
