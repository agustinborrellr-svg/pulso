import Foundation
import PulsoStore

/// Computes every per-night metric for a sleep period: stages, HRV, resting HR, respiration,
/// SpO₂, skin temperature, latency, disturbances and an overnight trend.
public enum SleepAnalyzer {
    public static func analyze(samples: [Sample], start: Int, end: Int, isNap: Bool, manual: Bool,
                               stillThreshold: Double? = nil, existingID: Int64? = nil) -> SleepSession {
        let inRange = Epochs.slice(samples, from: start, to: end)
        let epochs = Epochs.minutes(inRange, from: start, to: end)
        let thr = stillThreshold ?? SleepDetector.stillThreshold(epochs)

        // Centred 5-minute RMSSD per minute for the stager.
        let allRuns = HRV.clean(Epochs.rrRuns(inRange, from: start, to: end))
        let rmssdPerMinute: [Double?] = epochs.map { e in
            let runs = HRV.clean(Epochs.rrRuns(Epochs.slice(inRange, from: e.ts - 120, to: e.ts + 180), from: e.ts - 120, to: e.ts + 180))
            return HRV.rmssd(runs, minPairs: 30)
        }
        let (stages, confidence) = SleepStager.stageWithConfidence(epochs, rmssdPerMinute: rmssdPerMinute, stillThreshold: thr)

        var s = SleepSession(id: existingID, start: start, end: end, isNap: isNap, manual: manual, stages: stages,
                             stageConfidence: confidence)
        s.minutesAwake = Double(stages.filter { $0 == .awake }.count)
        s.minutesLight = Double(stages.filter { $0 == .light }.count)
        s.minutesDeep = Double(stages.filter { $0 == .deep }.count)
        s.minutesREM = Double(stages.filter { $0 == .rem }.count)

        // Latency: minutes until the first 10 consecutive asleep minutes. A night that never
        // consolidates counts as all latency (no onset), not as latency 0.
        var run = 0
        s.latencyMinutes = Double(stages.count)
        for (i, st) in stages.enumerated() {
            run = st == .awake ? 0 : run + 1
            if run >= 10 {
                s.latencyMinutes = Double(i - 9)
                break
            }
        }
        // Disturbances: awake bouts ≥ 2 min after onset.
        var bouts = 0, awakeRun = 0
        let onset = Int(s.latencyMinutes)
        if onset < stages.count {
            for st in stages[onset...] {
                if st == .awake {
                    awakeRun += 1
                    if awakeRun == 2 { bouts += 1 }
                } else {
                    awakeRun = 0
                }
            }
        }
        s.disturbances = bouts

        // 5-minute buckets: HR and RMSSD, tagged with the dominant stage.
        struct Bucket { var ts: Int; var hr: Double?; var rmssd: Double?; var pairs: Int; var deep: Bool; var asleep: Bool }
        var buckets: [Bucket] = []
        var b = start
        while b < end {
            let e = min(end, b + 300)
            let window = Epochs.slice(inRange, from: b, to: e)
            let bs = window.filter { $0.worn }
            let runs = HRV.clean(Epochs.rrRuns(window, from: b, to: e))
            let i0 = (b - start) / 60, i1 = min(stages.count, (e - start + 59) / 60)
            let st = i0 < i1 ? Array(stages[i0..<i1]) : []
            let deepCount = st.filter { $0 == .deep }.count
            let asleepCount = st.filter { $0 != .awake }.count
            buckets.append(Bucket(
                ts: b,
                hr: bs.count >= 120 ? Stats.mean(bs.compactMap { $0.hr }.map(Double.init)) : nil,
                rmssd: HRV.rmssd(runs, minPairs: 60),
                pairs: HRV.pairCount(runs),
                deep: !st.isEmpty && Double(deepCount) / Double(st.count) >= 0.6,
                asleep: !st.isEmpty && Double(asleepCount) / Double(st.count) >= 0.8
            ))
            b = e
        }
        s.trend = buckets.map { TrendPoint(ts: $0.ts, hr: $0.hr, hrv: $0.rmssd) }

        // Nightly HRV + RHR: WHOOP-style, from deep-sleep windows; fall back to the calmest asleep windows
        // of the second half of the night.
        var hrvWindows = buckets.filter { $0.deep && $0.rmssd != nil }
        if hrvWindows.count < 2 {
            let asleep = buckets.filter { $0.asleep && $0.rmssd != nil && $0.hr != nil }
            let secondHalf = asleep.filter { $0.ts >= start + (end - start) / 2 }
            let pool = secondHalf.count >= 3 ? secondHalf : asleep
            hrvWindows = Array(pool.sorted { ($0.hr ?? 999) < ($1.hr ?? 999) }.prefix(max(2, pool.count / 3)))
        }
        s.hrv = Stats.mean(hrvWindows.compactMap { $0.rmssd })
        let hrvHRs = hrvWindows.compactMap { $0.hr }
        let asleepHR = buckets.filter { $0.asleep }.compactMap { $0.hr }
        s.rhr = Stats.mean(hrvHRs) ?? Stats.percentile(asleepHR, 10)
        s.avgHR = Stats.mean(asleepHR)
        s.minHR = asleepHR.min()
        let asleepRuns = buckets.filter { $0.asleep }.flatMap { bucket -> [RRRun] in
            HRV.clean(Epochs.rrRuns(Epochs.slice(inRange, from: bucket.ts, to: bucket.ts + 300), from: bucket.ts, to: bucket.ts + 300))
        }
        s.hrvSDNN = HRV.sdnn(asleepRuns, minBeats: 300)
        s.respRate = HRV.respiratoryRate(asleepRuns.isEmpty ? allRuns : asleepRuns)

        // SpO₂ and skin temperature are computed on the strap; average them over asleep minutes.
        let asleepEpochs = zip(epochs, stages).filter { $0.1 != .awake }.map { $0.0 }
        let spo2 = asleepEpochs.flatMap { $0.spo2 }
        s.spo2 = spo2.count >= 10 ? Stats.median(spo2) : nil
        let temps = asleepEpochs.compactMap { $0.temp }
        s.skinTemp = temps.count >= 30 ? Stats.median(temps) : nil
        return s
    }
}
