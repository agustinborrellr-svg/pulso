import Foundation
import PulsoStore

/// One minute of strap data, aggregated from the 1 Hz samples.
public struct MinuteEpoch: Equatable {
    public var ts: Int
    public var hr: Double?
    /// SD of the per-second HR within the minute (short-term HR variability).
    public var hrSD: Double?
    /// Mean on-chip dynamic acceleration (g) — the main movement signal.
    public var motion: Double?
    /// Sum of |Δ gravity| between consecutive seconds (posture change).
    public var posture: Double
    public var wornFraction: Double
    public var poorFraction: Double
    public var strapAsleepFraction: Double
    public var strapWakeFraction: Double
    public var temp: Double?
    public var spo2: [Double]
    public var stepsDelta: Int
    public var activityClass: Int?
    public var secondsWithData: Int

    public var worn: Bool { wornFraction >= 0.5 && hr != nil }
}

/// A run of beat-to-beat intervals with no missing beats between them.
public typealias RRRun = [Double]

public enum Epochs {
    /// Aggregates per-second samples into minute epochs spanning [from, to) (minutes with no data are
    /// emitted with `secondsWithData == 0` so indices stay aligned with wall-clock minutes).
    public static func minutes(_ samples: [Sample], from: Int, to: Int) -> [MinuteEpoch] {
        let start = from - from % 60
        let count = max(0, (to - start + 59) / 60)
        guard count > 0 else { return [] }
        var buckets = [[Sample]](repeating: [], count: count)
        for s in samples where s.ts >= start && s.ts < start + count * 60 {
            buckets[(s.ts - start) / 60].append(s)
        }
        var out: [MinuteEpoch] = []
        out.reserveCapacity(count)
        var lastSteps: Int?
        var lastStepsTs = 0
        for i in 0..<count {
            let b = buckets[i]
            let ts = start + i * 60
            if b.isEmpty {
                out.append(MinuteEpoch(ts: ts, hr: nil, hrSD: nil, motion: nil, posture: 0, wornFraction: 0,
                                       poorFraction: 0, strapAsleepFraction: 0, strapWakeFraction: 0, temp: nil,
                                       spo2: [], stepsDelta: 0, activityClass: nil, secondsWithData: 0))
                continue
            }
            let worn = b.filter { $0.worn }
            let hrs = worn.compactMap { $0.hr }.map(Double.init)
            let motions = worn.compactMap { $0.dyn }
            var posture = 0.0
            var prev: (Double, Double, Double)?
            for s in b {
                if let x = s.gx, let y = s.gy, let z = s.gz {
                    if let p = prev {
                        let dx = x - p.0, dy = y - p.1, dz = z - p.2
                        posture += (dx * dx + dy * dy + dz * dz).squareRoot()
                    }
                    prev = (x, y, z)
                }
            }
            var steps = 0
            for s in b {
                if let st = s.steps {
                    if let l = lastSteps {
                        let d = (st - l + 65536) % 65536
                        // Across a gap in the data the counter keeps counting: keep the jump if a human could
                        // have walked it in that time (≤ 3.5 steps/s). Larger jumps are resets, not steps.
                        if d < 512 || Double(d) <= Double(s.ts - lastStepsTs) * 3.5 && d < 20000 { steps += d }
                    }
                    lastSteps = st
                    lastStepsTs = s.ts
                }
            }
            let states = b.compactMap { $0.sleepState }
            let acts = b.compactMap { $0.activity }
            var actMode: Int?
            if !acts.isEmpty {
                var counts = [0, 0, 0]
                for a in acts where a >= 0 && a <= 2 { counts[a] += 1 }
                actMode = counts.firstIndex(of: counts.max() ?? 0)
            }
            out.append(MinuteEpoch(
                ts: ts,
                hr: Stats.mean(hrs),
                hrSD: hrs.count >= 10 ? Stats.sd(hrs) : nil,
                motion: Stats.mean(motions),
                posture: posture,
                wornFraction: Double(worn.count) / Double(b.count),
                poorFraction: Double(b.filter { $0.poor }.count) / Double(b.count),
                strapAsleepFraction: states.isEmpty ? 0 : Double(states.filter { $0 == 2 }.count) / Double(states.count),
                strapWakeFraction: states.isEmpty ? 0 : Double(states.filter { $0 == 1 || $0 == 3 }.count) / Double(states.count),
                temp: Stats.median(worn.compactMap { $0.temp }),
                spo2: worn.compactMap { $0.spo2 }.map(Double.init),
                stepsDelta: steps,
                activityClass: actMode,
                secondsWithData: b.count
            ))
        }
        return out
    }

    /// Samples with ts in [from, to), assuming `samples` is sorted by ts (binary search).
    public static func slice(_ samples: [Sample], from: Int, to: Int) -> [Sample] {
        func lowerBound(_ t: Int) -> Int {
            var lo = 0, hi = samples.count
            while lo < hi {
                let mid = (lo + hi) / 2
                if samples[mid].ts < t { lo = mid + 1 } else { hi = mid }
            }
            return lo
        }
        let a = lowerBound(from), b = lowerBound(to)
        return a < b ? Array(samples[a..<b]) : []
    }

    /// Beat-to-beat runs over [from, to).
    ///
    /// The strap reports the R-R intervals of the beats that fell in each second, so at low heart rates
    /// some seconds legitimately carry none. Contiguity is therefore checked against the wall clock:
    /// the cumulative beat time of a run must stay consistent with the seconds that elapsed. A missed
    /// beat (or a duplicated report) breaks that consistency and starts a new run, so no successive
    /// difference ever spans a gap. Off-wrist / poor-signal seconds always break the run.
    public static func rrRuns(_ samples: [Sample], from: Int, to: Int, skipPoor: Bool = true) -> [RRRun] {
        var runs: [RRRun] = []
        var current: RRRun = []
        var runStart = 0
        var cumulative = 0.0 // seconds since the first beat of the run
        // Feasible offset of the run's first beat inside its second. Every later beat must land inside
        // its own reported second, which narrows this interval; an empty interval means a beat is
        // missing (or duplicated) and the run is split there.
        var lo = 0.0, hi = 1.0
        let tolerance = 0.12
        func flush() {
            if current.count > 1 { runs.append(current) }
            current = []
            cumulative = 0
        }
        func startRun(_ v: Double, _ ts: Int) {
            current = [v]
            runStart = ts
            cumulative = 0
            lo = 0
            hi = 1
        }
        for s in samples where s.ts >= from && s.ts < to {
            if s.off || (skipPoor && s.poor) {
                flush()
                continue
            }
            if s.rr.isEmpty {
                if !current.isEmpty && Double(s.ts - runStart) - cumulative > 2.6 { flush() }
                continue
            }
            for rr in s.rr {
                let v = Double(rr)
                if current.isEmpty {
                    startRun(v, s.ts)
                    continue
                }
                let c = cumulative + v / 1000
                let base = Double(s.ts - runStart) - c
                let newLo = max(lo, base), newHi = min(hi, base + 1)
                if newLo <= newHi + tolerance {
                    current.append(v)
                    cumulative = c
                    lo = min(newLo, newHi)
                    hi = max(newLo, newHi)
                } else {
                    flush()
                    startRun(v, s.ts)
                }
            }
        }
        flush()
        return runs
    }
}
