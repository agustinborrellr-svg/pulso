import Foundation

/// The strap's battery readings over time: how long a charge lasts and what the live stream costs it.
public enum BatteryLog {
    public struct Point: Codable, Equatable, Sendable {
        public var t: Int
        public var pct: Double
        /// Whether the live stream was on when this reading came in (it stays so until the next one).
        public var live: Bool

        public init(t: Int, pct: Double, live: Bool) {
            self.t = t
            self.pct = pct
            self.live = live
        }
    }

    /// Readings older than this are dropped.
    public static let keep = 30 * 86_400
    /// A level this much above the lowest reading since the last charge means the strap was charged again.
    static let chargeJump = 2.0

    /// Adds a reading when the level moved by 0.5 points or more, the stream switched, or an hour went by
    /// (so a later stream change is pinned to the right time).
    public static func append(_ p: Point, to log: [Point]) -> [Point] {
        guard (0...100).contains(p.pct) else { return log }
        var out = log.filter { $0.t >= p.t - keep && $0.t < p.t }
        if let last = out.last, abs(last.pct - p.pct) < 0.5, last.live == p.live, p.t - last.t < 3600 { return out }
        out.append(p)
        return out
    }

    public struct Drain: Equatable, Sendable {
        /// Points lost per day over the discharge so far.
        public var perDay: Double
        /// Hours covered since the last charge.
        public var hours: Double
        /// Points per hour with the live stream on / off, when each has at least 2 h behind it.
        public var liveHourly: Double?
        public var idleHourly: Double?
        public var liveHours: Double

        /// Days a full charge lasts at this pace.
        public var daysPerCharge: Double { perDay > 0 ? 100 / perDay : .infinity }
    }

    /// The discharge since the last charge. Needs 6 h and 2 points lost, or the pace is mostly rounding.
    public static func drain(_ log: [Point]) -> Drain? {
        let sorted = log.sorted { $0.t < $1.t }
        guard sorted.count >= 2 else { return nil }
        // A charge seen in small steps (40, 40.5, 41 …) never jumps 2 points between two readings, so compare
        // against the trough since the run began. Once a charge is recognised, the run follows the level up
        // and starts at its peak: the discharge is measured from the highest point after the last charge.
        var start = 0
        var low = sorted[0].pct
        var charged = false
        for i in 1..<sorted.count {
            let p = sorted[i].pct
            if charged && p > sorted[start].pct {
                start = i
                low = p
            } else if p - low >= chargeJump {
                charged = true
                start = i
                low = p
            } else {
                low = min(low, p)
            }
        }
        let run = Array(sorted[start...])
        guard run.count >= 2 else { return nil }
        var hours = 0.0, drop = 0.0, liveH = 0.0, liveDrop = 0.0
        for (a, b) in zip(run, run.dropFirst()) {
            let h = Double(b.t - a.t) / 3600
            let d = max(0, a.pct - b.pct)
            hours += h
            drop += d
            if a.live {
                liveH += h
                liveDrop += d
            }
        }
        guard hours >= 6, drop >= 2 else { return nil }
        let idleH = hours - liveH
        return Drain(perDay: drop / hours * 24, hours: hours,
                     liveHourly: liveH >= 2 ? liveDrop / liveH : nil,
                     idleHourly: idleH >= 2 ? (drop - liveDrop) / idleH : nil,
                     liveHours: liveH)
    }
}
