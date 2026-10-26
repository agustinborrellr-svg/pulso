import Foundation
import PulsoStore

/// Week / month / six-month windows over daily values, as the trend screens show them.
public enum TrendPeriod: Int, CaseIterable, Sendable {
    case week = 7
    case month = 30
    case halfYear = 182

    public var label: String {
        switch self {
        case .week: return "S"
        case .month: return "M"
        case .halfYear: return "6 M"
        }
    }

    /// "la semana anterior", "el mes anterior", "los 6 meses anteriores".
    public var previousText: String {
        switch self {
        case .week: return "la semana anterior"
        case .month: return "el mes anterior"
        case .halfYear: return "los 6 meses anteriores"
        }
    }
}

public struct TrendSample: Equatable, Sendable {
    /// First day of the point (the day itself, or the Monday-less start of a 7-day bucket).
    public var day: String
    public var value: Double?
}

public struct TrendWindow: Equatable, Sendable {
    public var from: String
    public var to: String
    public var points: [TrendSample]
    /// Average per day (`.average`) or per week (`.total`) over the window.
    public var summary: Double?
    public var previous: Double?
    /// Days of the window that had a value.
    public var values: [Double]
}

public enum TrendSeries {
    public enum Aggregate: Sendable {
        /// Mean of the daily values.
        case average
        /// Daily values add up (time in zones…): the summary is per week.
        case total
    }

    /// The window ending `offset` periods before `today` (0 = the current one).
    public static func window(days: [DaySummary], value: (DaySummary) -> Double?, period: TrendPeriod, offset: Int = 0,
                              today: String, aggregate: Aggregate = .average) -> TrendWindow {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        func range(_ k: Int) -> (String, String) {
            let to = DayKey.shift(today, days: -k * period.rawValue)
            return (DayKey.shift(to, days: -(period.rawValue - 1)), to)
        }
        func daily(_ from: String, _ count: Int) -> [TrendSample] {
            (0..<count).map { i in
                let d = DayKey.shift(from, days: i)
                return TrendSample(day: d, value: byDay[d].flatMap(value))
            }
        }
        func summary(_ samples: [TrendSample]) -> Double? {
            let v = samples.compactMap(\.value)
            guard !v.isEmpty else { return nil }
            switch aggregate {
            case .average: return v.reduce(0, +) / Double(v.count)
            case .total: return v.reduce(0, +) / (Double(samples.count) / 7)
            }
        }

        let (from, to) = range(offset)
        let days = daily(from, period.rawValue)
        let (pFrom, _) = range(offset + 1)
        let previous = summary(daily(pFrom, period.rawValue))

        var points = days
        if period == .halfYear {
            // 26 weekly points: mean of the days (or the week's total).
            points = stride(from: 0, to: days.count, by: 7).map { i in
                let chunk = Array(days[i..<min(days.count, i + 7)])
                let v = chunk.compactMap(\.value)
                let agg: Double? = v.isEmpty ? nil : (aggregate == .total ? v.reduce(0, +) : v.reduce(0, +) / Double(v.count))
                return TrendSample(day: chunk[0].day, value: agg)
            }
        }
        return TrendWindow(from: from, to: to, points: points, summary: summary(days), previous: previous,
                           values: days.compactMap(\.value))
    }
}
