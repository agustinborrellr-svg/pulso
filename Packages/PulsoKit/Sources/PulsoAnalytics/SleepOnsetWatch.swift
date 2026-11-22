import Foundation

/// Silent test: when you fall asleep, read live from the beats after a 4-7-8 session or at the start of a test nap.
/// Nothing vibrates or notifies; each trial is saved and later set against the onset the downloaded seconds give
/// (`SleepStager`), to tune the rule before it ever drives a smart nap.
///
/// Rule (first guess, to be tuned with the trials): the first `baselineMinutes` after the start are you lying awake.
/// A 30-s epoch is «drowsy» when its pulse is at least `hrDrop` below that baseline, it doesn't jump `arousalRise`
/// over the epoch before (a turn in bed) and, when both are known, its RMSSD isn't below 90 % of the baseline's
/// (vagal tone rises falling asleep). Onset is the start of the first `sustainMinutes` of drowsy epochs in a row;
/// an epoch with too few beats (loose contact, moving) breaks the run. The pulse falls a few beats a minute across
/// the wake → N1 → N2 transition (Burgess 1999, Trinder 2001), and requiring minutes of it in a row follows the
/// usual definition of sustained sleep onset.
public enum SleepOnsetWatch {
    public enum Kind: String, Codable, Sendable {
        /// After «Respiración para dormir» (4-7-8).
        case breathing
        /// A test nap: notes when a smart nap would have woken you, without doing it.
        case nap
    }

    public struct Config: Equatable, Sendable {
        public var epochSeconds = 30.0
        public var baselineMinutes = 3.0
        public var hrDrop = 3.0
        public var sustainMinutes = 5.0
        public var arousalRise = 8.0
        public var minBeatsPerEpoch = 15
        public init() {}
    }

    public struct Epoch: Equatable, Sendable {
        public var t: Double
        public var hr: Double
        public var rmssd: Double?
    }

    /// 30-s epochs from `start` up to the last beat; nil where there are too few beats.
    public static func epochs(_ beats: [LiveMetrics.Beat], from start: Double, config: Config = Config()) -> [Epoch?] {
        let inside = beats.filter { $0.t >= start }
        guard let last = inside.last?.t else { return [] }
        let n = Int((last - start) / config.epochSeconds) + 1
        var buckets = Array(repeating: [Double](), count: n)
        for b in inside {
            let i = Int((b.t - start) / config.epochSeconds)
            if i < n { buckets[i].append(b.rr) }
        }
        return buckets.enumerated().map { i, rr in
            let clean = HRV.clean([rr]).flatMap { $0 }
            guard clean.count >= config.minBeatsPerEpoch, let mean = Stats.mean(clean) else { return nil }
            return Epoch(t: start + Double(i) * config.epochSeconds, hr: 60000 / mean, rmssd: HRV.rmssd([clean], minPairs: 10))
        }
    }

    /// Onset time (start of the first sustained drowsy stretch), or nil if it hasn't happened yet.
    public static func detect(_ beats: [LiveMetrics.Beat], from start: Double, config: Config = Config()) -> Double? {
        let ep = epochs(beats, from: start, config: config)
        let nBase = Int(config.baselineMinutes * 60 / config.epochSeconds)
        let need = Int(config.sustainMinutes * 60 / config.epochSeconds)
        guard ep.count > nBase else { return nil }
        let base = ep.prefix(nBase).compactMap { $0 }
        guard base.count >= nBase / 2, let baseHR = Stats.median(base.map(\.hr)) else { return nil }
        let baseRMSSD = Stats.median(base.compactMap(\.rmssd))
        var run = 0
        for i in nBase..<ep.count {
            guard let e = ep[i] else { run = 0; continue }
            var drowsy = e.hr <= baseHR - config.hrDrop
            if let prev = ep[i - 1], e.hr > prev.hr + config.arousalRise { drowsy = false }
            if let r = e.rmssd, let b = baseRMSSD, r < 0.9 * b { drowsy = false }
            run = drowsy ? run + 1 : 0
            if run >= need { return ep[i - need + 1]!.t }
        }
        return nil
    }

    /// One trial, kept in kv `sleepOnset.trials`.
    public struct Trial: Codable, Equatable, Identifiable, Sendable {
        public var id: Int { start }
        public var kind: Kind
        /// When watching started (end of the breathing session, or the tap on «Empezar siesta»).
        public var start: Int
        /// When the live stream was let go.
        public var end: Int
        public var liveOnset: Int?
        /// Test nap: minutes of sleep wanted, and when a smart nap would have woken you.
        public var napMinutes: Int?
        public var wouldWakeAt: Int?

        public init(kind: Kind, start: Int, end: Int, liveOnset: Int? = nil, napMinutes: Int? = nil, wouldWakeAt: Int? = nil) {
            self.kind = kind
            self.start = start
            self.end = end
            self.liveOnset = liveOnset
            self.napMinutes = napMinutes
            self.wouldWakeAt = wouldWakeAt
        }
    }

    /// How long to keep the live stream on: until `afterOnsetMinutes` past the onset (the nap: until it would have
    /// woken you), and never more than `maxMinutes`.
    public static let maxMinutes: [Kind: Double] = [.breathing: 45, .nap: 90]
    public static let afterOnsetMinutes = 10.0

    public static func shouldStop(_ trial: Trial, now: Double) -> Bool {
        if now - Double(trial.start) >= (maxMinutes[trial.kind] ?? 45) * 60 { return true }
        if let w = trial.wouldWakeAt { return now >= Double(w) }
        if let o = trial.liveOnset, trial.kind == .breathing { return now - Double(o) >= afterOnsetMinutes * 60 }
        return false
    }

    /// Onset from the downloaded sleep: the first asleep minute of the first sleep that ends after the trial began
    /// and starts within 3 h of it.
    public static func downloadedOnset(_ trial: Trial, sleeps: [(start: Int, stages: [Int])]) -> Int? {
        let candidates = sleeps.filter { s in
            let end = s.start + s.stages.count * 60
            return end > trial.start && s.start < trial.start + 3 * 3600
        }.sorted { $0.start < $1.start }
        for s in candidates {
            if let i = s.stages.firstIndex(where: { $0 != 0 }) { return s.start + i * 60 }
        }
        return nil
    }

    /// Live minus downloaded, in minutes (positive: live said later).
    public static func errorMinutes(live: Int?, downloaded: Int?) -> Double? {
        guard let l = live, let d = downloaded else { return nil }
        return Double(l - d) / 60
    }
}
