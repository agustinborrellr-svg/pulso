import Foundation

/// The day's stress from the per-minute readings (`Stress.everyMinute`), and where its high minutes came from.
///
/// One definition everywhere: the day's numbers (`DaySummary.stressAvg`, `stressHighMinutes`, `stressHourly`) count
/// only the minutes awake and outside workouts and the 90 minutes after them (`daily`). The high minutes inside a
/// workout or asleep are still in `Split` so the 21:00 summary can say where they happened.
public enum StressSummary {
    /// After a workout the pulse stays up and HRV down for a while: recovery from exercise, not stress.
    public static let afterActivity = Stress.postWorkoutMinutes * 60
    public static let afterWaking = 60 * 60
    public static let aroundNap = 30 * 60

    /// What was going on in a minute.
    public enum Context: Equatable, Sendable {
        /// In a workout or the 90 minutes after it.
        case activity
        /// Asleep: the night before waking up, or a nap or daytime sleep.
        case asleep
        /// The hour after waking up, or the half hour around a nap.
        case waking
        case other

        /// Whether the minute counts in the day's stress (awake, outside workouts and the recovery after them).
        public var counted: Bool { self == .waking || self == .other }
    }

    /// `wake`: when you got up; minutes before it are the night. `naps`: naps and daytime sleeps.
    public static func context(_ ts: Int, wake: Int, workouts: [ClosedRange<Int>], naps: [ClosedRange<Int>]) -> Context {
        if workouts.contains(where: { ts >= $0.lowerBound && ts <= $0.upperBound + afterActivity }) { return .activity }
        if ts < wake || naps.contains(where: { $0.contains(ts) }) { return .asleep }
        if ts - wake < afterWaking || naps.contains(where: { ts >= $0.lowerBound - aroundNap && ts <= $0.upperBound + aroundNap }) {
            return .waking
        }
        return .other
    }

    /// High-stress minutes by what was going on.
    public struct Split: Equatable, Sendable {
        public var total = 0
        public var activity = 0
        public var asleep = 0
        public var waking = 0
        public var other = 0
        /// The high minutes awake and outside workouts: the day's `stressHighMinutes`.
        public var counted: Int { waking + other }
    }

    public struct Daily: Equatable, Sendable {
        /// Mean stress of the counted minutes.
        public var avg: Double?
        /// Counted minutes at or above the threshold.
        public var highMinutes = 0
        /// Mean stress of the counted minutes in each local clock hour (0…23).
        public var hourly = [Double?](repeating: nil, count: 24)
        /// Counted minutes low (< 1), medium (1 to the threshold) and high.
        public var levelMinutes = [0, 0, 0]
        /// Minutes with a reading that count (awake, outside workouts and the 90 minutes after them).
        public var counted = 0
        public var split = Split()
    }

    /// `minutes`: stress of each minute from `origin` (nil with the strap off).
    /// `wake`: when you got up (`origin` when nil); minutes before it, the night, are asleep.
    /// `workouts` without the breathing sessions; `naps` with the daytime sleeps.
    public static func daily(minutes: [Double?], origin: Int, wake: Int? = nil, workouts: [ClosedRange<Int>], naps: [ClosedRange<Int>],
                             threshold: Double = StressAlert.threshold, calendar: Calendar = .current) -> Daily {
        var out = Daily()
        var sums = [Double](repeating: 0, count: 24), counts = [Int](repeating: 0, count: 24)
        var total = 0.0
        // Every time zone's offset is a multiple of 15 minutes: one Calendar lookup per quarter hour.
        var quarter = Int.min, hour = 0
        for (i, v) in minutes.enumerated() {
            guard let v else { continue }
            let ts = origin + i * 60
            let kind = context(ts, wake: wake ?? origin, workouts: workouts, naps: naps)
            if v >= threshold {
                out.split.total += 1
                switch kind {
                case .activity: out.split.activity += 1
                case .asleep: out.split.asleep += 1
                case .waking: out.split.waking += 1
                case .other: out.split.other += 1
                }
            }
            guard kind.counted else { continue }
            out.counted += 1
            total += v
            out.levelMinutes[v < 1 ? 0 : (v < threshold ? 1 : 2)] += 1
            if ts / 900 != quarter {
                quarter = ts / 900
                hour = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(quarter * 900)))
            }
            sums[hour] += v
            counts[hour] += 1
        }
        out.highMinutes = out.split.counted
        out.avg = out.counted > 0 ? total / Double(out.counted) : nil
        out.hourly = (0..<24).map { counts[$0] > 0 ? sums[$0] / Double(counts[$0]) : nil }
        return out
    }

    /// The high minutes of `daily` by what was going on.
    public static func split(minutes: [Double?], origin: Int, wake: Int? = nil, workouts: [ClosedRange<Int>], naps: [ClosedRange<Int>],
                             threshold: Double = StressAlert.threshold) -> Split {
        daily(minutes: minutes, origin: origin, wake: wake, workouts: workouts, naps: naps, threshold: threshold).split
    }

    /// Clock minutes (0…1439) of the usual sleep window from recent nights' bed and wake times, widened by 30 minutes;
    /// nil without at least three nights.
    public static func sleepWindow(starts: [Int], ends: [Int], calendar: Calendar = .current) -> (from: Int, to: Int)? {
        guard starts.count >= 3, ends.count >= 3 else { return nil }
        func clock(_ ts: Int) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            return Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
        }
        // Bedtimes straddle midnight: count the small hours as the night before.
        let bed = starts.map { let m = clock($0); return m < 720 ? m + 1440 : m }
        guard let b = Stats.median(bed), let w = Stats.median(ends.map(clock)) else { return nil }
        return ((Int(b) - 30 + 1440) % 1440, (Int(w) + 30) % 1440)
    }

    /// Whether a clock minute falls inside a window that may wrap midnight.
    public static func contains(_ window: (from: Int, to: Int), clock m: Int) -> Bool {
        window.from <= window.to ? (m >= window.from && m < window.to) : (m >= window.from || m < window.to)
    }
}
