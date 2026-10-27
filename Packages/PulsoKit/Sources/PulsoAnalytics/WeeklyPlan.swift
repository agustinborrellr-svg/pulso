import Foundation
import PulsoStore

// MARK: - VO₂max norms

/// Approximate population norms for VO₂max by age and sex (treadmill-test registries such as FRIEND):
/// the median falls ≈ 0.4 ml/kg/min a year from ≈ 47 (men) / 39 (women) at 20, with a spread of ≈ 7 / 6.
public enum VO2Norms {
    public struct Band: Equatable, Sendable {
        public let label: String
        public let lower: Double
        public let upper: Double
    }

    public static func median(age: Int, sex: Sex) -> Double {
        let base = sex == .female ? 39.0 : (sex == .male ? 47.0 : 43.0)
        return base - 0.4 * Double(max(0, age - 20))
    }

    public static func spread(sex: Sex) -> Double { sex == .female ? 6.0 : (sex == .male ? 7.0 : 6.5) }

    /// Value at percentile `p` (0…1).
    public static func value(percentile p: Double, age: Int, sex: Sex) -> Double {
        median(age: age, sex: sex) + Stats.normalQuantile(Stats.clamp(p, 0.001, 0.999)) * spread(sex: sex)
    }

    /// Percentile (0…100) of `vo2` for this age and sex.
    public static func percentile(_ vo2: Double, age: Int, sex: Sex) -> Double {
        100 * Stats.normalCDF((vo2 - median(age: age, sex: sex)) / spread(sex: sex))
    }

    /// Five levels split at the 20th, 40th, 60th and 80th percentiles.
    public static func bands(age: Int, sex: Sex) -> [Band] {
        let cuts = [0.2, 0.4, 0.6, 0.8].map { value(percentile: $0, age: age, sex: sex) }
        let lo = value(percentile: 0.01, age: age, sex: sex), hi = value(percentile: 0.99, age: age, sex: sex)
        let edges = [lo] + cuts + [hi]
        let names = ["Bajo", "Por debajo de la media", "En la media", "Bueno", "Excelente"]
        return (0..<5).map { Band(label: names[$0], lower: edges[$0], upper: edges[$0 + 1]) }
    }

    public static func band(_ vo2: Double, age: Int, sex: Sex) -> Band {
        let b = bands(age: age, sex: sex)
        return b.first { vo2 < $0.upper } ?? b[b.count - 1]
    }
}

// MARK: - Weekly plan

/// Goals for the week (Monday to Sunday) and how far along each one is.
public struct PlanGoal: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case zonesLight, zonesHard, strengthDays, avgStrain
        case sleepHours, regularity, bedtimeBefore
        case steps, activeDays
        case habitYes, habitNo

        public var group: String {
            switch self {
            case .zonesLight, .zonesHard, .strengthDays, .avgStrain: return "Esfuerzo y zonas"
            case .sleepHours, .regularity, .bedtimeBefore: return "Sueño"
            case .steps, .activeDays: return "Pasos y actividad"
            case .habitYes, .habitNo: return "Hábitos"
            }
        }
    }

    public var id: String
    public var kind: Kind
    /// Minutes for time goals, hours×60 for sleep, %, steps, days, or minutes after midnight for bedtime.
    public var target: Double
    /// Journal key for habit goals.
    public var habit: String?

    public init(id: String = UUID().uuidString, kind: Kind, target: Double, habit: String? = nil) {
        self.id = id
        self.kind = kind
        self.target = target
        self.habit = habit
    }

    /// Sensible starting targets.
    public static func defaultTarget(_ k: Kind) -> Double {
        switch k {
        case .zonesLight: return 150
        case .zonesHard: return 30
        case .strengthDays: return 2
        case .avgStrain: return 12
        case .sleepHours: return 8 * 60
        case .regularity: return 80
        case .bedtimeBefore: return 23 * 60 + 30
        case .steps: return 8000
        case .activeDays: return 4
        case .habitYes: return 5
        case .habitNo: return 1
        }
    }
}

public enum WeeklyPlan {
    public struct Progress: Equatable, Sendable {
        public let goal: PlanGoal
        /// This week's value so far.
        public let value: Double?
        /// Mean of the four previous weeks (same measure).
        public let previous: Double?
        /// 0…1 of the target (for "max" goals, 1 while within the limit).
        public let fraction: Double
        public let met: Bool
        /// "deficiente" < 50 %, "suficiente" < 100 %, "óptimo" ≥ 100 %.
        public var level: Int { met ? 2 : (fraction >= 0.5 ? 1 : 0) }
    }

    /// Monday of the week that contains `day`.
    public static func weekStart(_ day: String, calendar: Calendar = .current) -> String {
        guard let d = DayKey.date(day, calendar: calendar) else { return day }
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d
        return DayKey.string(start, calendar: calendar)
    }

    static func value(_ g: PlanGoal, days: [DaySummary], workouts: [Workout], journal: [JournalEntry], calendar: Calendar) -> Double? {
        let measured = days.filter { $0.strain != nil || $0.sleepMinutes != nil }
        func mean(_ xs: [Double]) -> Double? { xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count) }
        switch g.kind {
        case .zonesLight: return measured.isEmpty ? nil : measured.reduce(0) { $0 + $1.zoneMinutes.prefix(3).reduce(0, +) }
        case .zonesHard: return measured.isEmpty ? nil : measured.reduce(0) { $0 + $1.zoneMinutes.dropFirst(3).reduce(0, +) }
        case .strengthDays:
            return Double(Set(workouts.filter { ["Fuerza", "Crossfit", "HIIT"].contains($0.sport) }.map { DayKey.string(ts: $0.start, calendar: calendar) }).count)
        case .avgStrain: return mean(days.compactMap(\.strain))
        case .sleepHours: return mean(days.compactMap(\.sleepMinutes))
        case .regularity: return mean(days.compactMap(\.sleepConsistency))
        case .bedtimeBefore:
            // Nights asleep by the target time (bedtimes after midnight count as late).
            let onsets = days.compactMap(\.sleepStart).map { ts -> Double in
                let m = SleepCoach.minutesAfterMidnight(ts: ts, calendar: calendar)
                return m < 12 * 60 ? m + 24 * 60 : m
            }
            guard !onsets.isEmpty else { return nil }
            return Double(onsets.filter { $0 <= g.target }.count)
        case .steps: return mean(days.compactMap { $0.steps.map(Double.init) })
        case .activeDays: return Double(days.filter { ($0.strain ?? 0) >= 10 }.count)
        case .habitYes, .habitNo:
            guard let key = g.habit else { return nil }
            return Double(Set(journal.filter { $0.key == key && $0.value > 0 }.map(\.day)).count)
        }
    }

    public static func progress(goals: [PlanGoal], days: [DaySummary], workouts: [Workout], journal: [JournalEntry],
                                today: String, calendar: Calendar = .current) -> [Progress] {
        let start = weekStart(today, calendar: calendar)
        func slice(_ from: String) -> (days: [DaySummary], workouts: [Workout], journal: [JournalEntry]) {
            // The current week only counts up to today.
            let to = min(DayKey.shift(from, days: 6, calendar: calendar), today)
            let ds = days.filter { $0.day >= from && $0.day <= to }
            let ws = workouts.filter { let k = DayKey.string(ts: $0.start, calendar: calendar); return k >= from && k <= to }
            let js = journal.filter { $0.day >= from && $0.day <= to }
            return (ds, ws, js)
        }
        let now = slice(start)
        let before = (1...4).map { slice(DayKey.shift(start, days: -7 * $0, calendar: calendar)) }
        return goals.map { g in
            let v = value(g, days: now.days, workouts: now.workouts, journal: now.journal, calendar: calendar)
            let prev = before.compactMap { value(g, days: $0.days, workouts: $0.workouts, journal: $0.journal, calendar: calendar) }
            let previous = prev.isEmpty ? nil : prev.reduce(0, +) / Double(prev.count)
            let fraction: Double
            let met: Bool
            if g.kind == .habitNo {
                // "Como mucho N días": met while within the limit.
                met = (v ?? 0) <= g.target
                fraction = met ? 1 : max(0, 1 - ((v ?? 0) - g.target) / max(1, g.target))
            } else {
                // "Dormido antes de las HH:MM" counts nights: five a week (its target is the time).
                let goal = g.kind == .bedtimeBefore ? 5 : g.target
                fraction = Stats.clamp((v ?? 0) / max(goal, 0.0001), 0, 1)
                met = (v ?? 0) >= goal
            }
            return Progress(goal: g, value: v, previous: previous, fraction: fraction, met: met)
        }
    }
}
