import Foundation

/// Guided breathing: the protocols, the timeline of phases the screen and the strap's vibration follow, and what a
/// session did to your pulse and stress.
public enum Breathwork {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Cyclic hyperventilation with breath holds on empty lungs (raises alertness).
        case alert
        /// Cyclic physiological sigh: double inhale, long exhale (Balban et al. 2023).
        case sigh
        /// Slow breathing at your resonance pace, ~6 breaths a minute (Lehrer).
        case coherence
        /// Box breathing, 4-4-4-4.
        case box
        /// 4-7-8 breathing before sleep.
        case sleep
    }

    public enum Phase: String, Codable, Sendable {
        case inhale, topUp, exhale, holdIn, holdOut
        /// Hold on empty lungs until you need to breathe (you tap to end it).
        case retention
    }

    public struct Step: Equatable, Sendable {
        public var phase: Phase
        /// Nil: lasts until you tap.
        public var seconds: Double?
        public var round: Int
        /// Breaths left in the round, for the countdown.
        public var count: Int?
    }

    public struct Settings: Codable, Equatable, Sendable {
        public var breaths: Int
        public var rounds: Int
        public var minutes: Int
        /// Breaths per minute for coherence.
        public var pace: Double

        public init(breaths: Int = 30, rounds: Int = 3, minutes: Int = 5, pace: Double = 6) {
            self.breaths = breaths
            self.rounds = rounds
            self.minutes = minutes
            self.pace = pace
        }
    }

    /// Name of the activity it is logged as (also in the activity catalog).
    public static func activityName(_ kind: Kind) -> String {
        switch kind {
        case .alert: return "Aumentar el estado de alerta"
        case .sigh: return "Suspiro fisiológico"
        case .coherence: return "Coherencia cardíaca"
        case .box: return "Respiración en caja"
        case .sleep: return "Respiración para dormir"
        }
    }

    public static var activityNames: Set<String> { Set(Kind.allCases.map(activityName)) }

    /// After the hold on empty lungs, a deep breath held this long.
    public static let recoveryHold = 15.0

    public static func steps(_ kind: Kind, _ s: Settings) -> [Step] {
        var out: [Step] = []
        let seconds = Double(max(1, s.minutes) * 60)
        func cycles(_ period: Double) -> Int { max(1, Int((seconds / period).rounded())) }
        switch kind {
        case .alert:
            for r in 1...max(1, s.rounds) {
                for b in stride(from: max(1, s.breaths), through: 1, by: -1) {
                    out.append(Step(phase: .inhale, seconds: 1.5, round: r, count: b))
                    out.append(Step(phase: .exhale, seconds: 1.2, round: r, count: b))
                }
                out.append(Step(phase: .holdOut, seconds: 4, round: r, count: nil))
                out.append(Step(phase: .retention, seconds: nil, round: r, count: nil))
                out.append(Step(phase: .inhale, seconds: 3, round: r, count: nil))
                out.append(Step(phase: .holdIn, seconds: recoveryHold, round: r, count: nil))
                out.append(Step(phase: .exhale, seconds: 4, round: r, count: nil))
            }
        case .sigh:
            for _ in 0..<cycles(10) {
                out += [Step(phase: .inhale, seconds: 2.5, round: 1, count: nil), Step(phase: .topUp, seconds: 1, round: 1, count: nil),
                        Step(phase: .exhale, seconds: 6.5, round: 1, count: nil)]
            }
        case .coherence:
            let period = 60 / min(max(s.pace, 3), 10)
            for _ in 0..<cycles(period) {
                out += [Step(phase: .inhale, seconds: period * 0.4, round: 1, count: nil),
                        Step(phase: .exhale, seconds: period * 0.6, round: 1, count: nil)]
            }
        case .box:
            for _ in 0..<cycles(16) {
                out += [Step(phase: .inhale, seconds: 4, round: 1, count: nil), Step(phase: .holdIn, seconds: 4, round: 1, count: nil),
                        Step(phase: .exhale, seconds: 4, round: 1, count: nil), Step(phase: .holdOut, seconds: 4, round: 1, count: nil)]
            }
        case .sleep:
            for _ in 0..<max(4, cycles(19)) {
                out += [Step(phase: .inhale, seconds: 4, round: 1, count: nil), Step(phase: .holdIn, seconds: 7, round: 1, count: nil),
                        Step(phase: .exhale, seconds: 8, round: 1, count: nil)]
            }
        }
        return out
    }

    /// What a finished session did.
    public struct Summary: Codable, Equatable, Sendable {
        public var kind: Kind
        public var start: Int
        public var end: Int
        public var inhaleSeconds: Double
        public var exhaleSeconds: Double
        public var holdSeconds: Double
        /// Each hold on empty lungs, in seconds.
        public var retentions: [Double]
        public var hrMin: Double?
        public var hrAvg: Double?
        public var hrMax: Double?
        /// Stress (0–3) in the minute before and the last minute of the session.
        public var stressBefore: Double?
        public var stressAfter: Double?
        public var rmssdBefore: Double?
        public var rmssdAfter: Double?
        /// Pulse every 5 s and stress every 15 s through the session, for the charts.
        public var hrSeries: [Double]
        public var stressSeries: [Double]

        public var duration: Int { end - start }
        public var stressChange: Double? { stressAfter.flatMap { a in stressBefore.map { a - $0 } } }
    }

    /// Seconds spent breathing in (with top-ups), out, and holding, from what was actually done.
    public static func split(_ done: [(phase: Phase, seconds: Double)]) -> (inhale: Double, exhale: Double, hold: Double) {
        var i = 0.0, e = 0.0, h = 0.0
        for d in done {
            switch d.phase {
            case .inhale, .topUp: i += d.seconds
            case .exhale: e += d.seconds
            case .holdIn, .holdOut, .retention: h += d.seconds
            }
        }
        return (i, e, h)
    }

    public static func summarize(kind: Kind, start: Int, end: Int, done: [(phase: Phase, seconds: Double)],
                                 hr: [(t: Double, hr: Double)], beats: [LiveMetrics.Beat], baseline: LiveMetrics.Baseline) -> Summary {
        let s = split(done)
        let inside = hr.filter { $0.t >= Double(start) && $0.t <= Double(end) }.map(\.hr)
        func scan(_ a: Double, _ b: Double) -> LiveMetrics.Scan? { LiveMetrics.scan(beats.filter { $0.t >= a && $0.t < b }, baseline: baseline) }
        let before = scan(Double(start) - 60, Double(start))
        let after = scan(Double(end) - 60, Double(end))
        var hrSeries: [Double] = []
        var t = Double(start)
        while t < Double(end) {
            if let m = Stats.mean(hr.filter { $0.t >= t && $0.t < t + 5 }.map(\.hr)) { hrSeries.append(m) }
            t += 5
        }
        var stressSeries: [Double] = []
        t = Double(start) + 45
        while t <= Double(end) {
            if let v = scan(t - 45, t)?.stress { stressSeries.append(v) }
            t += 15
        }
        return Summary(kind: kind, start: start, end: end, inhaleSeconds: s.inhale, exhaleSeconds: s.exhale, holdSeconds: s.hold,
                       retentions: done.filter { $0.phase == .retention }.map(\.seconds),
                       hrMin: inside.min(), hrAvg: Stats.mean(inside), hrMax: inside.max(),
                       stressBefore: before?.stress, stressAfter: after?.stress, rmssdBefore: before?.rmssd, rmssdAfter: after?.rmssd,
                       hrSeries: hrSeries, stressSeries: stressSeries)
    }
}

/// When to tap you on the wrist: sitting still with stress high for a while, at most once an hour.
public enum StressAlert {
    public static let threshold = 2.0
    public static let minutes = 5.0
    public static let quietHours = 1.0

    /// `readings`: live stress readings (time, stress, wrist still), oldest first.
    public static func shouldAlert(_ readings: [(t: Double, stress: Double, still: Bool)], now: Double, lastAlert: Double?) -> Bool {
        if let last = lastAlert, now - last < quietHours * 3600 { return false }
        let recent = readings.filter { $0.t >= now - minutes * 60 }
        guard let first = recent.first, now - first.t >= (minutes - 0.5) * 60, recent.count >= 5 else { return false }
        return recent.allSatisfy { $0.still && $0.stress >= threshold }
    }
}
