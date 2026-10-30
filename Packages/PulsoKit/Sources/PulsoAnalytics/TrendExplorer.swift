import Foundation
import PulsoStore

/// The periods of the trends tab: 7, 30, 90 and 365 days.
public enum TrendRange: Int, CaseIterable, Sendable {
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365

    /// "7 d".
    public var label: String { "\(rawValue) d" }
    /// "últimos 30 días".
    public var title: String { "últimos \(rawValue) días" }
    /// Days per chart point: one point per day, or per week over a year.
    public var bucketDays: Int { self == .year ? 7 : 1 }
}

/// Last days vs your usual: only flagged when the change is bigger than how much the metric normally moves.
public struct RecentChange: Equatable, Sendable {
    public var recent: Double
    public var baseline: Double
    public var recentDays: Int
    public var baselineDays: Int
    /// What a normal swing of the 7-day mean looks like in the baseline.
    public var threshold: Double
    public var delta: Double { recent - baseline }
    public var isNotable: Bool { abs(delta) > threshold }
}

public enum TrendExplorer {
    /// Window ending today: daily points (weekly over a year), summary and the previous window of the same length.
    public static func window(days: [DaySummary], value: (DaySummary) -> Double?, range: TrendRange, today: String,
                              aggregate: TrendSeries.Aggregate = .average) -> TrendWindow {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let n = range.rawValue
        func daily(_ from: String) -> [TrendSample] {
            (0..<n).map { i in
                let d = DayKey.shift(from, days: i)
                return TrendSample(day: d, value: byDay[d].flatMap(value).flatMap { $0.isFinite ? $0 : nil })
            }
        }
        func summary(_ s: [TrendSample]) -> Double? {
            let v = s.compactMap(\.value)
            guard !v.isEmpty else { return nil }
            switch aggregate {
            case .average: return v.reduce(0, +) / Double(v.count)
            case .total: return v.reduce(0, +) / (Double(v.count) / 7)
            }
        }
        let from = DayKey.shift(today, days: -(n - 1))
        let current = daily(from)
        let previous = daily(DayKey.shift(from, days: -n))
        var points = current
        if range.bucketDays > 1 {
            // Buckets end today so the last point is the current week.
            let size = range.bucketDays
            let first = current.count % size
            points = stride(from: first, to: current.count, by: size).map { i in
                let chunk = Array(current[i..<min(current.count, i + size)])
                let v = chunk.compactMap(\.value)
                let agg: Double? = v.isEmpty ? nil : (aggregate == .total ? v.reduce(0, +) : v.reduce(0, +) / Double(v.count))
                return TrendSample(day: chunk[0].day, value: agg)
            }
        }
        return TrendWindow(from: from, to: today, points: points, summary: summary(current), previous: summary(previous),
                           values: current.compactMap(\.value))
    }

    /// Mean of the last `recent` days vs the `baseline` days before them. nil without enough data
    /// (at least 4 recent days and 14 baseline days).
    public static func recentChange(days: [DaySummary], value: (DaySummary) -> Double?, today: String,
                                    recent: Int = 7, baseline: Int = 28) -> RecentChange? {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        func series(from: String, count: Int) -> [Double?] {
            (0..<count).map { i in byDay[DayKey.shift(from, days: i)].flatMap(value).flatMap { $0.isFinite ? $0 : nil } }
        }
        let recentFrom = DayKey.shift(today, days: -(recent - 1))
        let base = series(from: DayKey.shift(recentFrom, days: -baseline), count: baseline)
        let r = series(from: recentFrom, count: recent).compactMap { $0 }
        let b = base.compactMap { $0 }
        guard r.count >= 4, b.count >= 14, let rm = Stats.mean(r), let bm = Stats.mean(b), let sd = Stats.sd(b), sd > 0 else {
            return nil
        }
        // Spread of the rolling 7-day means inside the baseline: day-to-day values are correlated, so this
        // is a fairer "normal swing" than the daily SD over √n.
        var rolling: [Double] = []
        if base.count >= recent {
            for i in 0...(base.count - recent) {
                let w = base[i..<(i + recent)].compactMap { $0 }
                if w.count >= 4, let m = Stats.mean(w) { rolling.append(m) }
            }
        }
        let swing = rolling.count >= 5 ? (Stats.sd(rolling) ?? 0) : sd * (1 / Double(r.count) + 1 / Double(b.count)).squareRoot()
        let threshold = max(2 * swing, 0.5 * sd)
        return RecentChange(recent: rm, baseline: bm, recentDays: r.count, baselineDays: b.count, threshold: threshold)
    }

    /// Each value as standard deviations from the series mean, so two metrics with different units share an axis.
    public static func standardized(_ samples: [TrendSample]) -> [TrendSample] {
        let v = samples.compactMap(\.value)
        guard let m = Stats.mean(v), let sd = Stats.sd(v), sd > 0 else {
            return samples.map { TrendSample(day: $0.day, value: $0.value.map { _ in 0 }) }
        }
        return samples.map { TrendSample(day: $0.day, value: $0.value.map { ($0 - m) / sd }) }
    }
}

/// One month of the physiological calendar.
public enum CalendarMonth {
    public struct Extreme: Equatable, Sendable {
        public var day: String
        public var value: Double
    }

    public struct Summary: Equatable, Sendable {
        public var average: Double?
        public var highest: Extreme?
        public var lowest: Extreme?
        public var daysWithData: Int
        /// Days of the month up to today (the whole month when it is over).
        public var elapsedDays: Int
        public var measuredDays: Int
        public var importedDays: Int
        public var daysWithoutData: Int { max(0, elapsedDays - daysWithData) }
    }

    /// Days in `month` ("yyyy-MM") and blank cells before the 1st with Monday first.
    public static func layout(_ month: String, calendar: Calendar = .current) -> (leading: Int, count: Int) {
        guard let first = DayKey.date(month + "-01", calendar: calendar),
              let count = calendar.range(of: .day, in: .month, for: first)?.count else { return (0, 30) }
        return ((calendar.component(.weekday, from: first) + 5) % 7, count)
    }

    public static func dayKeys(_ month: String, calendar: Calendar = .current) -> [String] {
        let n = layout(month, calendar: calendar).count
        return (1...n).map { String(format: "%@-%02d", month, $0) }
    }

    public static func summary(month: String, days: [DaySummary], today: String, value: (DaySummary) -> Double?,
                               calendar: Calendar = .current) -> Summary {
        let keys = dayKeys(month, calendar: calendar)
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var vals: [(String, Double, Bool)] = []
        for k in keys {
            guard let d = byDay[k], let v = value(d), v.isFinite else { continue }
            vals.append((k, v, d.source != "strap"))
        }
        let elapsed = keys.filter { $0 <= today }.count
        let hi = vals.max { $0.1 < $1.1 }, lo = vals.min { $0.1 < $1.1 }
        return Summary(average: Stats.mean(vals.map(\.1)),
                       highest: hi.map { Extreme(day: $0.0, value: $0.1) },
                       lowest: lo.map { Extreme(day: $0.0, value: $0.1) },
                       daysWithData: vals.count, elapsedDays: elapsed,
                       measuredDays: vals.filter { !$0.2 }.count, importedDays: vals.filter { $0.2 }.count)
    }
}

extension Records {
    /// Streak lengths worth marking.
    public static let milestones = [7, 14, 30, 60, 100, 180, 365]

    /// The next milestone above `current` (nil past the last one).
    public static func nextMilestone(after current: Int) -> Int? {
        milestones.first { $0 > current }
    }

    /// A day the strap itself recorded and was worn (imported days never count).
    public static func wornWithStrap(_ d: DaySummary) -> Bool? {
        guard d.source == "strap" else { return false }
        return d.wornMinutes > 600 || d.recovery != nil ? true : nil
    }
}
