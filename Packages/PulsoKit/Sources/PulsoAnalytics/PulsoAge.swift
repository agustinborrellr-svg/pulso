import Foundation
import PulsoStore

/// "Edad Pulso": your age adjusted by the habits that the evidence ties to how long and how well people live
/// (sleep duration and regularity, aerobic and hard training, steps, VO₂max, resting heart rate).
///
/// Each habit has a poor, a neutral and an optimal value. At the neutral value (what an average adult does) it adds
/// nothing; below it adds up to `penalty` years at the poor end, above it takes off up to `benefit` years at the
/// optimal end. Neutral points follow the guidelines (7 h of sleep, 150 min/week of aerobic activity, 8 000 steps,
/// twice-weekly strength, the VO₂max of your age and sex) and the penalties are larger where the evidence of harm
/// is stronger (short sleep, irregular sleep, no strength training, low fitness). An orientation, not a
/// biological measurement.
public enum PulsoAge {
    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let group: String
        public let unit: String
        /// Recent value (last 30 days) and the longer one (last 6 months).
        public let recent: Double?
        public let longTerm: Double?
        public let poor: Double
        public let neutral: Double
        public let optimal: Double
        /// Years this habit adds (+) or takes off (−) with the recent value.
        public let years: Double?

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
        /// Years of Edad Pulso gained per calendar year at the recent pace (1 = like the calendar).
        public let pace: Double?
        public let items: [Item]
        public let measured: Int
    }

    struct Spec {
        let key: String, label: String, group: String, unit: String
        let poor: Double, neutral: Double, optimal: Double
        /// Years added at the poor end / taken off at the optimal end.
        let penalty: Double, benefit: Double
        let aggregate: TrendSeries.Aggregate
        let value: (DaySummary) -> Double?

        func years(_ v: Double?) -> Double? {
            guard let v else { return nil }
            let t = Stats.clamp((v - poor) / (optimal - poor), 0, 1)
            let n = Stats.clamp((neutral - poor) / (optimal - poor), 0.001, 0.999)
            return t <= n ? penalty * (n - t) / n : -benefit * (t - n) / (1 - n)
        }
    }

    /// Sports that count as strength training.
    static let strengthSports: Set<String> = ["Fuerza", "Entrenamiento funcional", "Core / abdominales", "Calistenia", "Crossfit", "HIIT"]

    /// `zones(day)` gives the day's minutes in zones 1…5 (strap days: the whole day; imported days: their workouts),
    /// `strength(day)` the minutes of strength training; both nil when the day has no activity data at all.
    static func specs(age: Int, sex: Sex, zones: @escaping (DaySummary) -> [Double]?, strength: @escaping (DaySummary) -> Double?) -> [Spec] {
        // VO₂max that a population-average person of your age and sex has (Fitness.fitnessAge in reverse).
        let base = sex == .female ? 39.0 : (sex == .male ? 47.0 : 43.0)
        let average = base - 0.4 * Double(max(0, age - 20))
        return [
            Spec(key: "sleepHours", label: "Horas de sueño", group: "Sueño", unit: "h", poor: 5 * 60, neutral: 7 * 60, optimal: 8 * 60,
                 penalty: 2.0, benefit: 0.8, aggregate: .average, value: { $0.sleepMinutes }),
            Spec(key: "regularity", label: "Regularidad del sueño", group: "Sueño", unit: "%", poor: 40, neutral: 70, optimal: 100,
                 penalty: 1.8, benefit: 1.0, aggregate: .average, value: { $0.sleepConsistency }),
            Spec(key: "zonesLight", label: "Tiempo en zonas de FC 1-3 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 150, optimal: 270,
                 penalty: 1.5, benefit: 1.5, aggregate: .total, value: { d in zones(d).map { $0.prefix(3).reduce(0, +) } }),
            Spec(key: "zonesHard", label: "Tiempo en zonas de FC 4-5 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 15, optimal: 60,
                 penalty: 0.2, benefit: 1.0, aggregate: .total, value: { d in zones(d).map { $0.dropFirst(3).reduce(0, +) } }),
            Spec(key: "strength", label: "Tiempo de actividad de fuerza (semanal)", group: "Esfuerzo", unit: "h", poor: 0, neutral: 30, optimal: 120,
                 penalty: 1.6, benefit: 1.0, aggregate: .total, value: strength),
            Spec(key: "steps", label: "Pasos", group: "Esfuerzo", unit: "pasos", poor: 2000, neutral: 8000, optimal: 16000,
                 penalty: 1.5, benefit: 1.6, aggregate: .average, value: { $0.steps.map(Double.init) }),
            Spec(key: "vo2max", label: "VO₂ máx (estimado)", group: "Fitness", unit: "ml/kg/min", poor: average - 12, neutral: average, optimal: average + 12,
                 penalty: 2.0, benefit: 2.0, aggregate: .average, value: { $0.vo2max }),
            Spec(key: "rhr", label: "FC en reposo", group: "Fitness", unit: "lpm", poor: 80, neutral: 62, optimal: 45,
                 penalty: 1.2, benefit: 0.8, aggregate: .average, value: { $0.rhr }),
        ]
    }

    /// `today` is the open cycle: it is left out (a half-finished day would move the age through the day), so
    /// the windows end on the last complete day. Imported days carry no zone minutes and don't count as zero.
    public static func compute(days: [DaySummary], profile: Profile, today: String, workouts: [Workout] = [],
                               calendar: Calendar = .current) -> Result {
        let days = days.filter { $0.day < today }
        // Workouts by day: imported days have no whole-day zones, but their workouts carry minutes per zone.
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
        let today = DayKey.shift(today, days: -1)
        let age = Double(profile.age)
        var items: [Item] = []
        var recentTotal = 0.0, longTotal = 0.0, measured = 0, both = 0
        for s in specs(age: profile.age, sex: profile.sex, zones: zones, strength: strength) {
            let r = TrendSeries.window(days: days, value: s.value, period: .month, today: today, aggregate: s.aggregate)
            let l = TrendSeries.window(days: days, value: s.value, period: .halfYear, today: today, aggregate: s.aggregate)
            // A month needs at least a week of readings to count.
            let recent = r.values.count >= 7 ? r.summary : nil
            let longTerm = l.values.count >= 7 ? l.summary : nil
            let y = s.years(recent)
            items.append(Item(key: s.key, label: s.label, group: s.group, unit: s.unit, recent: recent, longTerm: longTerm,
                              poor: s.poor, neutral: s.neutral, optimal: s.optimal, years: y))
            if let y {
                recentTotal += y
                measured += 1
                if let ly = s.years(longTerm) {
                    longTotal += ly
                    both += 1
                }
            }
        }
        guard measured >= 3 else {
            return Result(age: age, pulsoAge: nil, difference: nil, pace: nil, items: items, measured: measured)
        }
        // Pace: how fast Edad Pulso is drifting. Habits a year better than your 6-month norm slow the clock.
        let pace = both >= 3 ? Stats.clamp(1 + (recentTotal - longTotal) * 1.5, -1, 3) : nil
        return Result(age: age, pulsoAge: age + recentTotal, difference: recentTotal, pace: pace, items: items, measured: measured)
    }
}
