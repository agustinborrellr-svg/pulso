import Foundation

/// Heart-rate history for a chart period: per-second strap data and the live stream reduced to bins, with the
/// holes kept as holes (a line never bridges a stretch without data).
public enum HRHistory {
    public struct Bin: Equatable, Sendable {
        /// Unix seconds where the bin starts.
        public var start: Int
        /// Seconds with a reading inside the bin.
        public var seconds: Int
        public var sum: Double
        public var min: Int
        public var max: Int

        public init(start: Int, seconds: Int, sum: Double, min: Int, max: Int) {
            self.start = start
            self.seconds = seconds
            self.sum = sum
            self.min = min
            self.max = max
        }

        public var mean: Double { seconds > 0 ? sum / Double(seconds) : 0 }
    }

    public struct Point: Equatable, Sendable {
        public var start: Int
        public var mean: Double
        public var min: Int
        public var max: Int
        /// Consecutive bins share a segment; a missing bin starts a new one.
        public var segment: Int
    }

    public struct Gap: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var duration: Int { to - from }
    }

    public struct Series: Equatable, Sendable {
        public var from: Int
        public var to: Int
        public var width: Int
        public var points: [Point]
        public var gaps: [Gap]
        public var coveredSeconds: Int
        public var average: Double?
        public var min: Int?
        public var max: Int?

        /// Average/min/max only mean something with at least 5 minutes of readings.
        public var enoughData: Bool { coveredSeconds >= 300 }
        public var coverage: Double { Double(coveredSeconds) / Double(Swift.max(1, to - from)) }
    }

    /// Start of the bin holding `ts`, aligned to local time (`offset` = seconds east of UTC).
    public static func binStart(_ ts: Int, width: Int, offset: Int = 0) -> Int {
        let local = ts + offset
        let floored = local >= 0 ? local / width * width : ((local - width + 1) / width) * width
        return floored - offset
    }

    /// Bins raw readings; values outside 25–240 bpm are dropped.
    public static func bin(_ samples: [(ts: Int, hr: Int)], width: Int, offset: Int = 0) -> [Bin] {
        var out: [Int: Bin] = [:]
        for s in samples where s.hr > 25 && s.hr < 240 {
            let k = binStart(s.ts, width: width, offset: offset)
            if var b = out[k] {
                b.seconds += 1
                b.sum += Double(s.hr)
                b.min = Swift.min(b.min, s.hr)
                b.max = Swift.max(b.max, s.hr)
                out[k] = b
            } else {
                out[k] = Bin(start: k, seconds: 1, sum: Double(s.hr), min: s.hr, max: s.hr)
            }
        }
        return out.values.sorted { $0.start < $1.start }
    }

    /// Joins two sources binned the same way. When both cover a bin (strap history and live stream recorded the
    /// same minutes) the one with more seconds wins, so nothing is counted twice.
    public static func merge(_ a: [Bin], _ b: [Bin]) -> [Bin] {
        var out: [Int: Bin] = [:]
        for x in a + b {
            if let cur = out[x.start], cur.seconds >= x.seconds { continue }
            out[x.start] = x
        }
        return out.values.sorted { $0.start < $1.start }
    }

    /// Groups fine bins into wider ones (`width` must be a multiple of theirs).
    public static func rebin(_ bins: [Bin], width: Int, offset: Int = 0) -> [Bin] {
        var out: [Int: Bin] = [:]
        for x in bins {
            let k = binStart(x.start, width: width, offset: offset)
            if var b = out[k] {
                b.seconds += x.seconds
                b.sum += x.sum
                b.min = Swift.min(b.min, x.min)
                b.max = Swift.max(b.max, x.max)
                out[k] = b
            } else {
                out[k] = Bin(start: k, seconds: x.seconds, sum: x.sum, min: x.min, max: x.max)
            }
        }
        return out.values.sorted { $0.start < $1.start }
    }

    /// Points, gaps and period stats for [from, to).
    public static func series(_ bins: [Bin], from: Int, to: Int, width: Int) -> Series {
        let inRange = bins.filter { $0.start + width > from && $0.start < to && $0.seconds > 0 }.sorted { $0.start < $1.start }
        var points: [Point] = []
        var gaps: [Gap] = []
        var segment = 0
        var cursor = from
        for (i, b) in inRange.enumerated() {
            if i > 0 && b.start - inRange[i - 1].start > width { segment += 1 }
            if b.start > cursor && b.start - cursor >= width { gaps.append(Gap(from: cursor, to: b.start)) }
            points.append(Point(start: b.start, mean: b.mean, min: b.min, max: b.max, segment: segment))
            cursor = b.start + width
        }
        if to - cursor >= width { gaps.append(Gap(from: cursor, to: to)) }
        let covered = inRange.reduce(0) { $0 + $1.seconds }
        let sum = inRange.reduce(0.0) { $0 + $1.sum }
        return Series(from: from, to: to, width: width, points: points, gaps: gaps, coveredSeconds: covered,
                      average: covered > 0 ? sum / Double(covered) : nil,
                      min: inRange.map(\.min).min(), max: inRange.map(\.max).max())
    }
}
