import Foundation
import PulsoStore

// MARK: - Menstrual cycle calendar

/// Day-by-day phases for the cycle calendar, from period starts (logged by hand or detected from the nightly
/// temperature) and the detected ovulations. Future cycles are predicted with your average length.
public enum CyclePhases {
    public enum Phase: String, Codable, Equatable, Sendable, CaseIterable {
        case menstrual, follicular, ovulatory, luteal

        public var label: String {
            switch self {
            case .menstrual: return "Menstrual"
            case .follicular: return "Folicular"
            case .ovulatory: return "Ovulatoria"
            case .luteal: return "Lútea"
            }
        }
    }

    public struct Day: Equatable, Sendable {
        public var phase: Phase
        /// Day of the cycle (1 = first day of the period).
        public var cycleDay: Int
        /// True for days after today's last known start (a forecast).
        public var predicted: Bool
    }

    /// `starts`: first days of periods ("yyyy-MM-dd"), any order. `periodLength`: days of bleeding.
    public static func map(starts: [String], ovulations: [String], averageLength: Double?, periodLength: Int = 5,
                           through end: String, today: String, calendar: Calendar = .current) -> [String: Day] {
        let s = Array(Set(starts)).sorted()
        guard let first = s.first else { return [:] }
        let avg = Int((averageLength ?? 28).rounded())
        var bounds = s
        // Predicted starts until the end of the requested range.
        var next = DayKey.shift(s.last!, days: avg, calendar: calendar)
        while next <= DayKey.shift(end, days: avg, calendar: calendar) {
            bounds.append(next)
            next = DayKey.shift(next, days: avg, calendar: calendar)
        }
        var out: [String: Day] = [:]
        for (k, start) in bounds.enumerated() {
            let stop = k + 1 < bounds.count ? bounds[k + 1] : DayKey.shift(start, days: avg, calendar: calendar)
            let len = days(from: start, to: stop, calendar: calendar)
            guard len > 0, len <= 60 else { continue }
            let ovulation = ovulations.first { $0 > start && $0 < stop } ?? DayKey.shift(stop, days: -14, calendar: calendar)
            let ovIndex = days(from: start, to: ovulation, calendar: calendar)
            let predicted = start > s.last! || start > today
            for i in 0..<len {
                let day = DayKey.shift(start, days: i, calendar: calendar)
                guard day >= first, day <= end else { continue }
                let phase: Phase
                if i < periodLength { phase = .menstrual }
                else if abs(i - ovIndex) <= 1 { phase = .ovulatory }
                else if i < ovIndex { phase = .follicular }
                else { phase = .luteal }
                out[day] = Day(phase: phase, cycleDay: i + 1, predicted: predicted || day > today)
            }
        }
        return out
    }

    static func days(from a: String, to b: String, calendar: Calendar) -> Int {
        guard let x = DayKey.date(a, calendar: calendar), let y = DayKey.date(b, calendar: calendar) else { return 0 }
        return calendar.dateComponents([.day], from: x, to: y).day ?? 0
    }
}

// MARK: - Blood pressure

/// A cuff reading the user logs by hand. The strap has no validated blood-pressure sensor, so Pulso never invents one.
public struct BloodPressureReading: Codable, Equatable, Identifiable, Sendable {
    public var id: Int { ts }
    public var ts: Int
    public var systolic: Int
    public var diastolic: Int
    public var pulse: Int?

    public init(ts: Int, systolic: Int, diastolic: Int, pulse: Int? = nil) {
        self.ts = ts
        self.systolic = systolic
        self.diastolic = diastolic
        self.pulse = pulse
    }
}

public enum BloodPressure {
    /// 2017 ACC/AHA categories.
    public enum Category: Int, Comparable, Sendable {
        case normal, elevated, stage1, stage2, crisis
        public static func < (a: Category, b: Category) -> Bool { a.rawValue < b.rawValue }

        public var label: String {
            switch self {
            case .normal: return "Normal"
            case .elevated: return "Elevada"
            case .stage1: return "Hipertensión grado 1"
            case .stage2: return "Hipertensión grado 2"
            case .crisis: return "Muy alta: consulta ya"
            }
        }
    }

    public static func category(systolic s: Int, diastolic d: Int) -> Category {
        if s > 180 || d > 120 { return .crisis }
        if s >= 140 || d >= 90 { return .stage2 }
        if s >= 130 || d >= 80 { return .stage1 }
        if s >= 120 { return .elevated }
        return .normal
    }

    public struct DayRange: Equatable, Sendable, Identifiable {
        public var id: String { day }
        public var day: String
        public var systolic: ClosedRange<Int>
        public var diastolic: ClosedRange<Int>
        public var count: Int
    }

    /// One bar per day with every reading of that day.
    public static func daily(_ readings: [BloodPressureReading], calendar: Calendar = .current) -> [DayRange] {
        Dictionary(grouping: readings) { DayKey.string(ts: $0.ts, calendar: calendar) }
            .map { day, r in
                DayRange(day: day, systolic: r.map(\.systolic).min()!...r.map(\.systolic).max()!,
                         diastolic: r.map(\.diastolic).min()!...r.map(\.diastolic).max()!, count: r.count)
            }
            .sorted { $0.day < $1.day }
    }

    /// Average of the readings in the last `days` days (nil if none).
    public static func average(_ readings: [BloodPressureReading], days: Int, now: Date = Date()) -> (systolic: Int, diastolic: Int)? {
        let from = Int(now.timeIntervalSince1970) - days * 86400
        let r = readings.filter { $0.ts >= from }
        guard !r.isEmpty else { return nil }
        return (Int((Double(r.map(\.systolic).reduce(0, +)) / Double(r.count)).rounded()),
                Int((Double(r.map(\.diastolic).reduce(0, +)) / Double(r.count)).rounded()))
    }
}

// MARK: - Period averages (trend view)

public enum PeriodAverages {
    public struct Segment: Equatable, Sendable, Identifiable {
        public var id: String { start }
        public var start: String
        public var end: String
        public var mean: Double
        public var count: Int
        /// % change vs the previous segment with data.
        public var changePct: Double?
    }

    /// Calendar-month segments (or `weeks`-long blocks when `weeks` > 0) of a daily series.
    public static func segments(_ points: [(day: String, value: Double)], weeks: Int = 0, minCount: Int = 3,
                                calendar: Calendar = .current) -> [Segment] {
        let groups = Dictionary(grouping: points) { p -> String in
            if weeks > 0, let d = DayKey.date(p.day, calendar: calendar) {
                let monday = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: d)) ?? d
                return DayKey.string(monday, calendar: calendar)
            }
            return String(p.day.prefix(7))
        }
        var out: [Segment] = []
        for key in groups.keys.sorted() {
            let g = groups[key]!
            guard g.count >= minCount, let m = Stats.mean(g.map(\.value)) else { continue }
            let days = g.map(\.day).sorted()
            var seg = Segment(start: days.first!, end: days.last!, mean: m, count: g.count)
            if let prev = out.last, prev.mean != 0 { seg.changePct = (m - prev.mean) / abs(prev.mean) * 100 }
            out.append(seg)
        }
        return out
    }
}

// MARK: - Sleep score factors

/// The four parts of the sleep score shown under its ring, each rated deficient / sufficient / optimal.
public enum SleepFactors {
    public enum Level: Int, Sendable { case deficient, sufficient, optimal }

    public struct Factor: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var label: String
        public var icon: String
        /// 0–100.
        public var value: Double
        public var level: Level
    }

    static func level(_ v: Double, sufficient: Double, optimal: Double) -> Level {
        v >= optimal ? .optimal : (v >= sufficient ? .sufficient : .deficient)
    }

    public static func of(_ d: DaySummary) -> [Factor] {
        var out: [Factor] = []
        if let s = d.sleepMinutes, let n = d.sleepNeedMinutes, n > 0 {
            let v = min(100, s / n * 100)
            out.append(Factor(key: "hoursVsNeed", label: "Horas vs. lo necesario", icon: "moon.zzz", value: v,
                              level: level(v, sufficient: 70, optimal: 85)))
        }
        if let r = d.sleepConsistency {
            out.append(Factor(key: "regularity", label: "Regularidad del sueño", icon: "clock.arrow.circlepath", value: r,
                              level: level(r, sufficient: 60, optimal: 80)))
        }
        if let e = d.sleepEfficiency {
            let v = e * 100
            out.append(Factor(key: "efficiency", label: "Eficiencia del sueño", icon: "bed.double", value: v,
                              level: level(v, sufficient: 80, optimal: 90)))
        }
        let restorative = d.restorativeMinutes ?? ((d.deepMinutes ?? 0) + (d.remMinutes ?? 0))
        if let s = d.sleepMinutes, s > 0, restorative > 0 {
            let v = min(100, restorative / s * 100)
            out.append(Factor(key: "restorative", label: "Sueño reparador (profundo + REM)", icon: "sparkles", value: v,
                              level: level(v, sufficient: 35, optimal: 45)))
        }
        return out
    }
}
