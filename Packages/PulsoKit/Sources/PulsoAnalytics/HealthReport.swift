import Foundation
import PulsoStore

/// Printable health summary to hand to a doctor or a coach: the last 30 days day by day and the last 180 days month
/// by month, each night measure against your own six-month range.
public enum HealthReport {
    public struct Series: Sendable {
        public var key: String
        /// One value per day of the window (nil without data).
        public var values: [Double?]
        public var average: Double?
        /// 10th–90th percentile of the last 180 days: your usual band.
        public var range: ClosedRange<Double>?
        /// Mean per month ("2026-10") for months with at least `minMonthDays` days of data.
        public var monthly: [String: Double]
    }

    public struct Sport: Sendable, Equatable {
        public var name: String
        public var count: Int
    }

    public struct Report: Sendable {
        /// The last 30 days, oldest first, and the last 180.
        public var days: [String]
        public var longDays: [String]
        /// Months covered by the 180 days, oldest first ("2026-05").
        public var months: [String]
        /// Night vitals over the 180 days: "resp", "rhr", "hrv", "spo2", "temp" (skin temperature deviation).
        public var long: [String: Series]
        /// Hours asleep, hours of naps, minutes of moderate (zones 1-3) and vigorous (zones 4-5) activity in logged
        /// workouts, over the 180 days.
        public var sleep: Series
        public var naps: Series
        public var moderate: Series
        public var vigorous: Series
        public var topSports: [Sport]

        /// The last 30 days of a 180-day series, with its own average.
        public func recent(_ s: Series) -> Series {
            var r = s
            r.values = Array(s.values.suffix(days.count))
            r.average = Stats.mean(r.values.compactMap { $0 })
            return r
        }

        public var aerobicAverage: Double? {
            let m = recent(moderate).values, v = recent(vigorous).values
            return Stats.mean(zip(m, v).map { ($0 ?? 0) + ($1 ?? 0) })
        }
    }

    public static let recentDays = 30
    public static let longDaysCount = 180
    public static let minMonthDays = 7

    public static func build(days: [DaySummary], workouts: [Workout], end: String) -> Report {
        let long = (0..<longDaysCount).map { DayKey.shift(end, days: $0 - longDaysCount + 1) }
        let recent = Array(long.suffix(recentDays))
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let months = long.reduce(into: [String]()) { m, d in
            let k = String(d.prefix(7))
            if m.last != k { m.append(k) }
        }

        func series(_ key: String, _ values: [Double?], range: Bool = true) -> Series {
            let present = values.compactMap { $0 }
            var monthly: [String: Double] = [:]
            for m in months {
                let v = zip(long, values).filter { $0.0.hasPrefix(m) }.compactMap { $0.1 }
                if v.count >= minMonthDays, let a = Stats.mean(v) { monthly[m] = a }
            }
            var band: ClosedRange<Double>?
            if range, present.count >= 14, let lo = Stats.percentile(present, 10), let hi = Stats.percentile(present, 90) {
                band = lo...hi
            }
            return Series(key: key, values: values, average: Stats.mean(present), range: band, monthly: monthly)
        }
        func night(_ path: KeyPath<DaySummary, Double?>) -> [Double?] { long.map { byDay[$0]?[keyPath: path] } }

        var moderate = [Double](repeating: 0, count: long.count)
        var vigorous = [Double](repeating: 0, count: long.count)
        let index = Dictionary(long.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var counts: [String: Int] = [:]
        for w in workouts {
            guard let i = index[DayKey.string(ts: w.start)] else { continue }
            let z = w.zoneMinutes + [0, 0, 0, 0, 0]
            moderate[i] += z[0] + z[1] + z[2]
            vigorous[i] += z[3] + z[4]
            counts[w.sport, default: 0] += 1
        }
        let sports = counts.map { Sport(name: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }

        return Report(
            days: recent, longDays: long, months: months,
            long: ["resp": series("resp", night(\.respRate)), "rhr": series("rhr", night(\.rhr)),
                   "hrv": series("hrv", night(\.hrv)), "spo2": series("spo2", night(\.spo2)),
                   "temp": series("temp", night(\.skinTempDeviation))],
            sleep: series("sleep", long.map { byDay[$0]?.sleepMinutes.map { $0 / 60 } }, range: false),
            naps: series("naps", long.map { byDay[$0]?.napMinutes.map { $0 / 60 } }, range: false),
            moderate: series("moderate", moderate.map { $0 }, range: false),
            vigorous: series("vigorous", vigorous.map { $0 }, range: false),
            topSports: Array(sports.prefix(5))
        )
    }
}
