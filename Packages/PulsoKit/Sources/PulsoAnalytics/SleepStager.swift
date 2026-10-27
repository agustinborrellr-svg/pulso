import Foundation
import PulsoStore

/// Four-class sleep staging (awake / light / deep / REM) over one-minute epochs from cardiac and
/// movement features, smoothed with a sticky Viterbi decoder. The split is reported as detected (it is
/// not pushed toward textbook proportions) together with how far it can be trusted.
public enum SleepStager {
    struct Features {
        var hr: [Double]
        var hrVar: [Double]
        var rmssd: [Double]
        var motion: [Double]
        var wakeVote: [Double]
    }

    static func zscores(_ x: [Double?]) -> [Double] {
        let vals = x.compactMap { $0 }
        let med = Stats.median(vals) ?? 0
        let spread = max(Stats.robustSpread(vals) ?? 1, 1e-6)
        return x.map { v in v.map { Stats.clamp(($0 - med) / spread, -4, 4) } ?? 0 }
    }

    /// Stages each minute of `epochs` (already cut to the sleep period). `rmssdPerMinute` is a
    /// centred-window RMSSD for each minute (nil where the beat stream was broken).
    public static func stage(_ epochs: [MinuteEpoch], rmssdPerMinute: [Double?], stillThreshold: Double) -> [SleepStage] {
        stageWithConfidence(epochs, rmssdPerMinute: rmssdPerMinute, stillThreshold: stillThreshold).stages
    }

    public static func stageWithConfidence(_ epochs: [MinuteEpoch], rmssdPerMinute: [Double?],
                                           stillThreshold: Double) -> (stages: [SleepStage], confidence: StageConfidence?) {
        let n = epochs.count
        guard n > 0 else { return ([], nil) }

        // Smooth HR over 3 minutes to suppress single-minute noise.
        let hrRaw = epochs.map { $0.hr }
        var hrSmooth = [Double?](repeating: nil, count: n)
        for i in 0..<n {
            let w = (max(0, i - 1)...min(n - 1, i + 1)).compactMap { hrRaw[$0] }
            hrSmooth[i] = Stats.mean(w)
        }
        let hrVar: [Double?] = epochs.map { $0.hrSD }
        let motion: [Double?] = epochs.map { e in e.motion.map { log(max($0, 0.002)) } }
        let f = Features(
            hr: zscores(hrSmooth),
            hrVar: zscores(hrVar),
            rmssd: zscores(rmssdPerMinute.map { $0.map { log(max($0, 1)) } }),
            motion: zscores(motion),
            wakeVote: epochs.map { e in
                var v = 0.0
                if let m = e.motion, m > stillThreshold * 2.5 { v += 1.6 } else if let m = e.motion, m > stillThreshold * 1.4 { v += 0.6 }
                if e.posture > 0.25 { v += 1.0 }
                v += 0.8 * e.strapWakeFraction
                if !e.worn { v += 0.5 }
                return v
            }
        )

        let (stages, emit) = decode(f, n: n)
        let confidence = assess(stages: stages, emit: emit, epochs: epochs, rmssdPerMinute: rmssdPerMinute)
        return (stages, confidence)
    }

    /// How far the split can be trusted: strap coverage, a clean beat stream, how clear each minute was and
    /// whether the proportions are physiologically plausible.
    static func assess(stages: [SleepStage], emit: [[Double]], epochs: [MinuteEpoch], rmssdPerMinute: [Double?]) -> StageConfidence {
        let n = Double(max(1, stages.count))
        let coverage = Double(epochs.filter { $0.worn && $0.hr != nil }.count) / n
        let beatCoverage = Double(rmssdPerMinute.filter { $0 != nil }.count) / n
        let index: [SleepStage: Int] = [.awake: 0, .light: 1, .deep: 2, .rem: 3]
        var probs: [Double] = []
        for (i, st) in stages.enumerated() where st != .awake {
            let e = emit[i]
            let m = e.max() ?? 0
            let ex = e.map { exp($0 - m) }
            probs.append(ex[index[st] ?? 1] / ex.reduce(0, +))
        }
        let decisiveness = Stats.mean(probs) ?? 0
        let asleep = Double(stages.filter { $0 != .awake }.count)
        let deepFrac = asleep > 0 ? Double(stages.filter { $0 == .deep }.count) / asleep : 0
        let remFrac = asleep > 0 ? Double(stages.filter { $0 == .rem }.count) / asleep : 0
        func pct(_ x: Double) -> Int { Int((x * 100).rounded()) }

        var score = 100.0
        var reasons: [String] = []
        if coverage < 0.9 {
            score -= (0.9 - coverage) * 200
            reasons.append("La pulsera no leyó bien el \(pct(1 - coverage)) % de la noche (floja, mal colocada o quitada).")
        }
        if beatCoverage < 0.8 {
            score -= (0.8 - beatCoverage) * 120
            reasons.append("Solo hubo señal latido a latido limpia el \(pct(beatCoverage)) % del tiempo, y la VFC es la clave para separar profundo y REM.")
        }
        if decisiveness < 0.75 {
            score -= (0.75 - decisiveness) * 150
            reasons.append("Muchos minutos estaban a medio camino entre dos fases (pulso y VFC sin un patrón claro).")
        }
        if asleep >= 60 {
            if deepFrac < 0.05 || deepFrac > 0.35 {
                score -= 20
                reasons.append("El sueño profundo (\(pct(deepFrac)) %) queda fuera de lo habitual en adultos (5-35 %).")
            }
            if remFrac < 0.08 || remFrac > 0.35 {
                score -= 20
                reasons.append("El REM (\(pct(remFrac)) %) queda fuera de lo habitual en adultos (8-35 %).")
            }
        }
        if asleep < 180 {
            score -= 15
            reasons.append("Es un sueño corto: con menos de 3 horas los ciclos no se completan y cuesta más separarlos.")
        }
        score = Stats.clamp(score, 0, 100)
        let level: StageConfidence.Level = score >= 75 ? .high : (score >= 50 ? .medium : .low)
        return StageConfidence(level: level, score: score.rounded(), reasons: reasons, coverage: coverage,
                               beatCoverage: beatCoverage, decisiveness: decisiveness)
    }

    /// Emission log-scores per stage then Viterbi with sticky transitions.
    static func decode(_ f: Features, n: Int, deepBias: Double = 0, remBias: Double = 0) -> ([SleepStage], [[Double]]) {
        let states: [SleepStage] = [.awake, .light, .deep, .rem]
        var emit = [[Double]](repeating: [0, 0, 0, 0], count: n)
        for i in 0..<n {
            let pos = Double(i) / Double(max(1, n - 1)) // 0 at onset … 1 at wake
            // Deep sleep concentrates in the first half of the night; REM grows toward morning
            // and is rare in the first ~60 minutes.
            let deepPrior = pos < 0.5 ? 0.5 : (pos < 0.75 ? -0.2 : -0.9)
            let remPrior = i < 60 ? -1.6 : (pos > 0.5 ? 0.4 : 0.0)
            let wake = 1.3 * f.motion[i] + 0.4 * f.hr[i] + 1.4 * f.wakeVote[i] + log(0.10) - 0.6
            let light = log(0.47)
            let deep = -0.9 * f.hr[i] - 0.7 * f.hrVar[i] + 0.35 * f.rmssd[i] - 0.5 * f.motion[i]
                + log(0.18) + deepPrior + deepBias - 0.8 * f.wakeVote[i]
            let rem = 0.55 * f.hr[i] + 0.75 * f.hrVar[i] - 0.3 * f.rmssd[i] - 0.6 * f.motion[i]
                + log(0.22) + remPrior + remBias - 0.8 * f.wakeVote[i]
            emit[i] = [wake, light, deep, rem]
        }
        // Transition log-probs (rows: from, cols: to).
        let stay: [Double] = [0.80, 0.86, 0.88, 0.90]
        var trans = [[Double]](repeating: [0, 0, 0, 0], count: 4)
        for a in 0..<4 {
            for b in 0..<4 {
                if a == b {
                    trans[a][b] = log(stay[a])
                } else {
                    var p = (1 - stay[a]) / 3
                    // Deep ↔ REM direct jumps are uncommon; wake → deep is rare.
                    if (a == 2 && b == 3) || (a == 3 && b == 2) { p *= 0.3 }
                    if a == 0 && b == 2 { p *= 0.3 }
                    trans[a][b] = log(p)
                }
            }
        }
        var score = emit[0]
        var back = [[Int]](repeating: [0, 0, 0, 0], count: n)
        if n > 1 {
            for i in 1..<n {
                var next = [Double](repeating: -Double.infinity, count: 4)
                for b in 0..<4 {
                    var best = -Double.infinity, arg = 0
                    for a in 0..<4 {
                        let v = score[a] + trans[a][b]
                        if v > best { best = v; arg = a }
                    }
                    next[b] = best + emit[i][b]
                    back[i][b] = arg
                }
                score = next
            }
        }
        var idx = score.indices.max(by: { score[$0] < score[$1] }) ?? 1
        var path = [Int](repeating: 1, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            path[i] = idx
            idx = back[i][idx]
        }
        return (path.map { states[$0] }, emit)
    }
}
