import Foundation
import PulsoStore

/// "Edad Pulso": your age adjusted by the habits that the evidence ties to how long and how well people live
/// (sleep duration and regularity, aerobic and hard training, steps, VO₂max, resting heart rate).
///
/// Each habit sits between a poor and an optimal value. In the middle it adds nothing; at the poor end it adds
/// up to `weight` years and at the optimal end it takes them off. The weights are deliberately small and the
/// total is an orientation, not a biological measurement.
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
        public let optimal: Double
        /// Years this habit adds (+) or takes off (−) with the recent value.
        public let years: Double?

        /// 0 = poor end, 1 = optimal end.
        public func position(_ v: Double?) -> Double? {
            guard let v else { return nil }
            return Stats.clamp((v - poor) / (optimal - poor), 0, 1)
        }
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
        let poor: Double, optimal: Double, weight: Double
        let aggregate: TrendSeries.Aggregate
        let value: (DaySummary) -> Double?
    }

    static func specs(age: Int, sex: Sex) -> [Spec] {
        // VO₂max that a population-average person of your age and sex has (Fitness.fitnessAge in reverse).
        let base = sex == .female ? 39.0 : (sex == .male ? 47.0 : 43.0)
        let average = base - 0.4 * Double(max(0, age - 20))
        return [
            Spec(key: "sleepHours", label: "Horas de sueño", group: "Sueño", unit: "h", poor: 5 * 60, optimal: 8 * 60, weight: 1.0,
                 aggregate: .average, value: { $0.sleepMinutes }),
            Spec(key: "regularity", label: "Regularidad del sueño", group: "Sueño", unit: "%", poor: 40, optimal: 100, weight: 0.9,
                 aggregate: .average, value: { $0.sleepConsistency }),
            Spec(key: "zonesLight", label: "Tiempo en zonas de FC 1-3 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, optimal: 4 * 60, weight: 1.2,
                 aggregate: .total, value: { d in d.strain == nil || d.source != "strap" ? nil : d.zoneMinutes.prefix(3).reduce(0, +) }),
            Spec(key: "zonesHard", label: "Tiempo en zonas de FC 4-5 (semanal)", group: "Esfuerzo", unit: "h", poor: 0, optimal: 60, weight: 0.8,
                 aggregate: .total, value: { d in d.strain == nil || d.source != "strap" ? nil : d.zoneMinutes.dropFirst(3).reduce(0, +) }),
            Spec(key: "steps", label: "Pasos", group: "Esfuerzo", unit: "pasos", poor: 2000, optimal: 12000, weight: 0.9,
                 aggregate: .average, value: { $0.steps.map(Double.init) }),
            Spec(key: "vo2max", label: "VO₂ máx (estimado)", group: "Fitness", unit: "ml/kg/min", poor: average - 12, optimal: average + 12, weight: 1.5,
                 aggregate: .average, value: { $0.vo2max }),
            Spec(key: "rhr", label: "FC en reposo", group: "Fitness", unit: "lpm", poor: 80, optimal: 45, weight: 0.9,
                 aggregate: .average, value: { $0.rhr }),
        ]
    }

    /// `today` is the open cycle: it is left out (a half-finished day would move the age through the day), so
    /// the windows end on the last complete day. Imported days carry no zone minutes and don't count as zero.
    public static func compute(days: [DaySummary], profile: Profile, today: String) -> Result {
        let days = days.filter { $0.day < today }
        let today = DayKey.shift(today, days: -1)
        let age = Double(profile.age)
        var items: [Item] = []
        var recentTotal = 0.0, longTotal = 0.0, measured = 0, both = 0
        for s in specs(age: profile.age, sex: profile.sex) {
            let r = TrendSeries.window(days: days, value: s.value, period: .month, today: today, aggregate: s.aggregate)
            let l = TrendSeries.window(days: days, value: s.value, period: .halfYear, today: today, aggregate: s.aggregate)
            // A month needs at least a week of readings to count.
            let recent = r.values.count >= 7 ? r.summary : nil
            let longTerm = l.values.count >= 7 ? l.summary : nil
            func years(_ v: Double?) -> Double? {
                guard let v else { return nil }
                let p = Stats.clamp((v - s.poor) / (s.optimal - s.poor), 0, 1)
                return s.weight * (1 - 2 * p)
            }
            let y = years(recent)
            items.append(Item(key: s.key, label: s.label, group: s.group, unit: s.unit, recent: recent, longTerm: longTerm,
                              poor: s.poor, optimal: s.optimal, years: y))
            if let y {
                recentTotal += y
                measured += 1
                if let ly = years(longTerm) {
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
