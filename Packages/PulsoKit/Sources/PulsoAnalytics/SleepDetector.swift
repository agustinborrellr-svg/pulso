import Foundation
import PulsoStore

/// Finds sleep periods in a span of minute epochs using movement, heart rate and the strap's own
/// on-device sleep flag. Pure function of its inputs.
public enum SleepDetector {
    public struct Block: Equatable {
        public var startIndex: Int
        public var endIndex: Int // inclusive
        public var length: Int { endIndex - startIndex + 1 }
    }

    public struct Config {
        public var windowMinutes = 15
        public var stillFractionForSleep = 0.75
        public var mergeGapMinutes = 25
        public var minBlockMinutes = 20
        public init() {}
    }

    /// Movement level below which a minute counts as still. Adaptive to the wearer's rest floor.
    public static func stillThreshold(_ epochs: [MinuteEpoch]) -> Double {
        let m = epochs.filter { $0.worn }.compactMap { $0.motion }
        guard let p10 = Stats.percentile(m, 10) else { return 0.03 }
        return Stats.clamp(p10 * 2.5 + 0.004, 0.012, 0.06)
    }

    /// Sleep-floor heart rate: the 5th percentile of worn 5-minute mean HR in the span.
    public static func hrFloor(_ epochs: [MinuteEpoch]) -> Double? {
        var means: [Double] = []
        var i = 0
        while i + 5 <= epochs.count {
            let hrs = epochs[i..<i + 5].compactMap { $0.worn ? $0.hr : nil }
            if hrs.count >= 4, let m = Stats.mean(hrs) { means.append(m) }
            i += 5
        }
        return Stats.percentile(means, 5)
    }

    /// Per-minute sleep-candidate flags.
    public static func candidates(_ epochs: [MinuteEpoch], config: Config = Config()) -> [Bool] {
        let n = epochs.count
        guard n > 0 else { return [] }
        let thr = stillThreshold(epochs)
        let floor = hrFloor(epochs)
        let hrLimit = floor.map { max($0 * 1.22, $0 + 12) }
        let still: [Double] = epochs.map { e in
            guard e.worn else { return -1 } // unknown
            if let m = e.motion { return m < thr ? 1 : 0 }
            return e.posture < 0.05 ? 1 : 0
        }
        let half = config.windowMinutes / 2
        var out = [Bool](repeating: false, count: n)
        for i in 0..<n {
            guard epochs[i].worn else { continue }
            let lo = max(0, i - half), hi = min(n - 1, i + half)
            var stillCount = 0.0, known = 0.0, asleepVotes = 0.0, hrs: [Double] = []
            for k in lo...hi {
                if still[k] >= 0 {
                    known += 1
                    stillCount += still[k]
                }
                asleepVotes += epochs[k].strapAsleepFraction
                if epochs[k].worn, let h = epochs[k].hr { hrs.append(h) }
            }
            guard known >= Double(hi - lo + 1) * 0.6 else { continue }
            let stillFrac = stillCount / known
            let asleepFrac = asleepVotes / Double(hi - lo + 1)
            let hrMed = Stats.median(hrs)
            let hrOK = hrLimit.map { lim in hrMed.map { $0 <= lim } ?? false } ?? true
            if asleepFrac >= 0.6 && stillFrac >= 0.5 {
                out[i] = true
            } else if stillFrac >= config.stillFractionForSleep && hrOK {
                out[i] = true
            }
        }
        return out
    }

    /// Contiguous candidate blocks, merged across short awakenings / off-wrist blips.
    public static func blocks(_ epochs: [MinuteEpoch], config: Config = Config()) -> [Block] {
        let c = candidates(epochs, config: config)
        var raw: [Block] = []
        var start: Int?
        for i in 0..<c.count {
            if c[i] {
                if start == nil { start = i }
            } else if let s = start {
                raw.append(Block(startIndex: s, endIndex: i - 1))
                start = nil
            }
        }
        if let s = start { raw.append(Block(startIndex: s, endIndex: c.count - 1)) }
        var merged: [Block] = []
        for b in raw {
            if var last = merged.last, b.startIndex - last.endIndex - 1 <= config.mergeGapMinutes {
                last.endIndex = b.endIndex
                merged[merged.count - 1] = last
            } else {
                merged.append(b)
            }
        }
        return merged.filter { $0.length >= config.minBlockMinutes }
    }

    /// Daytime blocks need more evidence than a night: sitting still on the sofa looks like sleep to motion
    /// alone. Accept one when the strap itself flagged sleep, or when it lasts 30+ minutes with heart rate
    /// near the sleeping floor (falling asleep lowers HR well below quiet wakefulness).
    public static func daytimeSleepIsPlausible(_ epochs: ArraySlice<MinuteEpoch>, hrFloor: Double?) -> Bool {
        let worn = epochs.filter { $0.worn }
        guard worn.count >= 20 else { return false }
        let strapAsleep = worn.reduce(0) { $0 + $1.strapAsleepFraction } / Double(worn.count)
        if strapAsleep >= 0.5 { return true }
        guard worn.count >= 30, let floor = hrFloor, let hr = Stats.median(worn.compactMap(\.hr)) else { return false }
        return hr <= min(floor * 1.12, floor + 8)
    }
}
