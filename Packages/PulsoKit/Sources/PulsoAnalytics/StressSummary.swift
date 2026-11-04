import Foundation

/// Where the day's high-stress minutes came from: an activity (during it or the 90 minutes after, while the body
/// recovers), sleep (the hour after waking up and around naps) or neither.
public enum StressSummary {
    public static let afterActivity = 90 * 60
    public static let afterWaking = 60 * 60
    public static let aroundNap = 30 * 60

    public struct Split: Equatable, Sendable {
        public var total = 0
        public var activity = 0
        public var sleep = 0
        public var other = 0
    }

    /// `minutes`: stress of each minute from `origin` (the cycle's first minute, at waking up).
    public static func split(minutes: [Double?], origin: Int, workouts: [ClosedRange<Int>], naps: [ClosedRange<Int>],
                             threshold: Double = StressAlert.threshold) -> Split {
        var out = Split()
        for (i, v) in minutes.enumerated() {
            guard let v, v >= threshold else { continue }
            let ts = origin + i * 60
            out.total += 1
            if workouts.contains(where: { ts >= $0.lowerBound && ts <= $0.upperBound + afterActivity }) {
                out.activity += 1
            } else if ts - origin < afterWaking || naps.contains(where: { ts >= $0.lowerBound - aroundNap && ts <= $0.upperBound + aroundNap }) {
                out.sleep += 1
            } else {
                out.other += 1
            }
        }
        return out
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
