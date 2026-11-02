import Foundation
import PulsoStore

/// "Edad Pulso": your age plus the years your habits add or take off, following the method of WHOOP's 2025 Healthspan
/// white paper (WHOOP Age).
///
/// Each habit becomes an all-cause mortality hazard ratio against someone who just meets the guideline (the neutral
/// point, 0 years). A hazard ratio becomes years with t = ln(HR) / 0.1 (Spiegelhalter's effective age: risk grows
/// ~10 % per year of age). The years of the habits are summed and shrunk by `adjustment`, which stands in for the
/// white paper's structural-equation correction for habits that overlap (RHR and VO₂ máx, steps and zone time);
/// WHOOP does not publish those factors, so 0.85 is fitted so the white paper's median 30-year-old man and woman come
/// out at −1.6 years, as published.
///
/// Neutral points (white paper): sleep 7 h (7–9 h a small benefit, over 9 h nothing); sleep consistency 70 %;
/// steps 8 000/day (5 600 from 60); zones 1-3 100 min/week (down to 70 with age), zones 4-5 10 min/week (down to 7);
/// strength 40 min/week (no extra benefit past 120); VO₂ máx from WHOOP's age and sex table; resting HR 60 (men) /
/// 64 (women). Zone time counts only inside activities. Lean body mass is not entered in Pulso: 0 years, as in WHOOP.
///
/// Curves (slopes cited by the white paper, saturating): short sleep HR 1.12 at 6 h (Itani 2017); consistency
/// (Windred 2024); steps −23 % per 1 000 below the target, flat from 10 000 (Sheng 2021, Paluch 2022); zones 1-3
/// down to 0.75 at 600 min (Lee 2022); zones 4-5 −10 % at 20 min (Ahmadi 2022); strength (Momma 2022);
/// VO₂ máx −13 % per MET (Mandsager 2018); resting HR +9 % per 10 bpm (Zhang 2016).
///
/// Windows: the age uses your last 6 months and is recalculated once a week. Pace of ageing projects the age 6 months
/// ahead with your last 30 days held constant: (projected − current) / 0.5, from −1 to 3 (1 = like the calendar).
public enum PulsoAge {
    /// Years of age per unit of ln(hazard ratio): 1 / 0.1.
    public static let yearsPerLnHR = 10.0
    /// Shared correction for overlapping habits (see above).
    public static let adjustment = 0.85
    /// Days of the long window (6 months) and of "ahora".
    public static let longDays = 182
    public static let recentDays = 30

    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let group: String
        public let unit: String
        /// Last 30 days ("ahora").
        public let recent: Double?
        /// Last 6 months: what the age uses.
        public let longTerm: Double?
        /// Ends and neutral point of the bar.
        public let poor: Double
        public let neutral: Double
        public let optimal: Double
        /// Years this habit adds (+) or takes off (−) over the 6 months.
        public let years: Double?
        /// Years with the last 30 days.
        public let recentYears: Double?
        /// Every habit counts (kept for the views).
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
        /// Years of Edad Pulso per calendar year if the last 30 days continue (1 = like the calendar, < 1 slower).
        public let pace: Double?
        public let items: [Item]
        public let measured: Int
    }

    /// A dose–response curve: (value, hazard ratio) points, log-linear between them and flat outside.
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

        /// Same shape with the x values scaled (thresholds that move with age).
        func scaled(_ k: Double) -> Curve { Curve(points: points.map { ($0.0 * k, $0.1) }) }
    }

    struct Spec {
        let key: String, label: String, group: String, unit: String
        let poor: Double, neutral: Double, optimal: Double
        let curve: Curve
        let source: String
        let aggregate: TrendSeries.Aggregate
        let value: (DaySummary) -> Double?

        /// Years vs meeting the guideline, before the shared adjustment: 10 · ln(HR(v) / HR(neutral)).
        func years(_ v: Double?) -> Double? {
            guard let v else { return nil }
            return PulsoAge.yearsPerLnHR * log(curve.rr(v) / curve.rr(neutral))
        }
    }

    /// Sports that count as strength activity (white paper Table 1: weightlifting, functional fitness, HIIT, pilates,
    /// yoga, barre, rucking…).
    static let strengthSports: Set<String> = ["Fuerza", "Entrenamiento funcional", "Core / abdominales", "Calistenia", "Crossfit",
                                              "HIIT", "Yoga", "Pilates", "Barre"]

    /// WHOOP's minimum VO₂ máx targets (ml/kg/min) for ages 20, 25 … 100.
    static let vo2TargetsMen: [Double] = [46, 46, 44, 42, 40, 37, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21]
    static let vo2TargetsWomen: [Double] = [40, 40, 38, 36, 34, 32, 30, 29, 27, 26, 25, 23, 22, 21, 20, 19, 18]

    public static func vo2Target(age: Int, sex: Sex) -> Double {
        func at(_ table: [Double]) -> Double {
            let x = Stats.clamp((Double(age) - 20) / 5, 0, Double(table.count - 1))
            let i = Int(x), f = x - Double(i)
            return i + 1 < table.count ? table[i] + (table[i + 1] - table[i]) * f : table[i]
        }
        switch sex {
        case .male: return at(vo2TargetsMen)
        case .female: return at(vo2TargetsWomen)
        case .other: return (at(vo2TargetsMen) + at(vo2TargetsWomen)) / 2
        }
    }

    static func specs(age: Int, sex: Sex, zones: @escaping (DaySummary) -> [Double]?, strength: @escaping (DaySummary) -> Double?) -> [Spec] {
        let a = Double(age)
        let vo2 = vo2Target(age: age, sex: sex)
        // −13 % per MET (3.5 ml/kg/min) around the target, bounded at ±3 METs.
        let perMET = 0.87, reach = 3 * 3.5
        let rhr = sex == .female ? 64.0 : (sex == .male ? 60.0 : 62.0)
        // Thresholds that fall with age: zones 1-3 100 → 70 min/week, zones 4-5 10 → 7, steps 8 000 → 5 600 from 60.
        let light = Stats.clamp(100 - 0.6 * (a - 30), 70, 100), hard = Stats.clamp(10 - 0.06 * (a - 30), 7, 10)
        let steps = age >= 60 ? 5600.0 : 8000.0
        return [
            Spec(key: "sleepHours", label: "Horas de sueño", group: "Sueño", unit: "h", poor: 5 * 60, neutral: 7 * 60, optimal: 8 * 60,
                 curve: Curve(points: [(300, 1.25), (360, 1.12), (420, 1), (480, 0.98), (540, 0.98), (570, 1)]),
                 source: "Itani 2017 (Sleep Med)", aggregate: .average, value: { $0.sleepMinutes }),
            Spec(key: "regularity", label: "Regularidad del sueño", group: "Sueño", unit: "%", poor: 40, neutral: 70, optimal: 100,
                 curve: Curve(points: [(40, 1.5), (50, 1.3), (70, 1), (90, 0.8)]),
                 source: "Windred 2024 (Sleep)", aggregate: .average, value: { $0.sleepConsistency }),
            Spec(key: "zonesLight", label: "Tiempo en zonas de FC 1-3 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: light, optimal: 600,
                 curve: Curve(points: [(0, 1.25), (100, 1), (300, 0.85), (600, 0.75)]).scaled(light / 100),
                 source: "Lee 2022 (Circulation)", aggregate: .total, value: { d in zones(d).map { $0.prefix(3).reduce(0, +) } }),
            Spec(key: "zonesHard", label: "Tiempo en zonas de FC 4-5 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: hard, optimal: 60,
                 curve: Curve(points: [(0, 1.15), (10, 1), (20, 0.9), (60, 0.85)]).scaled(hard / 10),
                 source: "Ahmadi 2022 (Eur Heart J)", aggregate: .total, value: { d in zones(d).map { $0.dropFirst(3).reduce(0, +) } }),
            Spec(key: "strength", label: "Tiempo de actividad de fuerza (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 40, optimal: 120,
                 curve: Curve(points: [(0, 1.15), (40, 1), (60, 0.95), (120, 0.92)]),
                 source: "Momma 2022 (BJSM)", aggregate: .total, value: strength),
            Spec(key: "steps", label: "Pasos", group: "Esfuerzo", unit: "pasos", poor: 2000, neutral: steps, optimal: 12000,
                 curve: Curve(points: [(2000, 1.6), (5000, 1.25), (8000, 1), (10000, 0.9)]).scaled(steps / 8000),
                 source: "Sheng 2021 y Paluch 2022", aggregate: .average, value: { $0.steps.map(Double.init) }),
            Spec(key: "vo2max", label: "VO₂ máx (estimado)", group: "Fitness", unit: "ml/kg/min", poor: vo2 - 14, neutral: vo2, optimal: vo2 + 14,
                 curve: Curve(points: [(vo2 - reach, pow(perMET, -3)), (vo2 + reach, pow(perMET, 3))]),
                 source: "Mandsager 2018 (JAMA Netw Open)", aggregate: .average, value: { $0.vo2max }),
            Spec(key: "rhr", label: "FC en reposo", group: "Fitness", unit: "lpm", poor: 80, neutral: rhr, optimal: 45,
                 curve: Curve(points: [(rhr - 20, pow(1.09, -2)), (rhr + 30, pow(1.09, 3))]),
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
    /// it uses the complete days before it. Zone time counts only inside activities (white paper), so it comes from
    /// the workouts of each day.
    public static func compute(days: [DaySummary], profile: Profile, today: String, workouts: [Workout] = [],
                               calendar: Calendar = .current) -> Result {
        let days = days.filter { $0.day < today }
        let end = DayKey.shift(today, days: -1, calendar: calendar)
        let fromLong = DayKey.shift(today, days: -longDays, calendar: calendar)
        let fromRecent = DayKey.shift(today, days: -recentDays, calendar: calendar)
        var byDay: [String: [Workout]] = [:]
        for w in workouts { byDay[DayKey.string(ts: w.start, calendar: calendar), default: []].append(w) }
        let zones: (DaySummary) -> [Double]? = { d in
            guard d.strain != nil else { return nil }
            let ws = byDay[d.day] ?? []
            return (0..<5).map { z in ws.reduce(0) { $0 + (z < $1.zoneMinutes.count ? $1.zoneMinutes[z] : 0) } }
        }
        let strength: (DaySummary) -> Double? = { d in
            guard d.strain != nil else { return nil }
            return (byDay[d.day] ?? []).filter { strengthSports.contains($0.sport) }.reduce(0) { $0 + Double($1.end - $1.start) / 60 }
        }
        let age = Double(profile.age)
        var items: [Item] = []
        var total = 0.0, recentTotal = 0.0, measured = 0, measuredRecent = 0
        for s in specs(age: profile.age, sex: profile.sex, zones: zones, strength: strength) {
            // 6 months need three weeks of readings; 30 days, one.
            let long = window(days, from: fromLong, to: end, aggregate: s.aggregate, value: s.value, minDays: 21)
            let recent = window(days, from: fromRecent, to: end, aggregate: s.aggregate, value: s.value, minDays: 7)
            let y = s.years(long).map { $0 * adjustment }, ry = s.years(recent).map { $0 * adjustment }
            items.append(Item(key: s.key, label: s.label, group: s.group, unit: s.unit, recent: recent, longTerm: long,
                              poor: s.poor, neutral: s.neutral, optimal: s.optimal, years: y, recentYears: ry,
                              counted: true, source: s.source))
            if let y { total += y; measured += 1 }
            if let ry { recentTotal += ry; measuredRecent += 1 }
        }
        guard measured >= 4 else {
            return Result(age: age, pulsoAge: nil, difference: nil, recentAge: nil, pace: nil, items: items, measured: measured)
        }
        let recentAge = measuredRecent >= 4 ? age + recentTotal : nil
        // Projected age in 6 months with the last 30 days held = age + 0.5 + recent years; pace = (projected − now) / 0.5.
        let pace = recentAge.map { Stats.clamp(1 + 2 * ($0 - (age + total)), -1, 3) }
        return Result(age: age, pulsoAge: age + total, difference: total, recentAge: recentAge, pace: pace, items: items, measured: measured)
    }
}
