import Foundation
import PulsoStore

/// Everything the "Inteligencia" screen shows, computed in one pass from stored data.
public struct IntelligenceReport: Sendable {
    public struct Section: Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var subtitle: String
        public var metrics: [MetricResult]
    }

    public var deviation: [Deviation.Point]
    public var events: [LoadResponse.Event]
    public var fingerprints: [LoadResponse.Fingerprint]
    public var habits: [HabitImpact.Item]
    public var outlook: RecoveryModel.Outlook?
    public var sections: [Section]
    public var generated: Date

    /// Metric by id across sections.
    public func metric(_ id: String) -> MetricResult? { sections.lazy.flatMap { $0.metrics }.first { $0.id == id } }
}

public enum Intelligence {
    public static let version = "1.0"

    /// Weeks between a sustained change in weekly load and the change in weekly ln VFC (max |correlation|
    /// over lags 0–4 weeks). Needs ~12 weeks.
    public static func adaptationLag(_ days: [DaySummary], calendar: Calendar = .current) -> MetricResult {
        let f = "Correlación cruzada entre el cambio semanal de esfuerzo y el cambio semanal de ln VFC, desfases 0–4 semanas; IC por remuestreo"
        var weeks: [String: (strain: [Double], hrv: [Double])] = [:]
        for d in days {
            guard let date = DayKey.date(d.day, calendar: calendar) else { continue }
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let key = String(format: "%04d-%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
            var w = weeks[key] ?? ([], [])
            if let s = d.strain { w.strain.append(s) }
            if let h = d.hrv, h > 0 { w.hrv.append(log(h)) }
            weeks[key] = w
        }
        let series = weeks.keys.sorted().compactMap { k -> (Double, Double)? in
            guard let w = weeks[k], w.strain.count >= 4, w.hrv.count >= 4, let s = Num.mean(w.strain), let h = Num.median(w.hrv) else { return nil }
            return (s, h)
        }
        // 12 weeks give 11 weekly differences: the best of five lags then clears |r| ≥ 0.3 on pure noise
        // most of the time, so more history and a permutation test are required before naming a lag.
        guard series.count >= 26 else {
            return .insufficient("adaptationLag", "Desfase de adaptación", unit: "semanas", need: "26 semanas con datos (llevas \(series.count))",
                                 have: series.count, formula: f, version: version)
        }
        let dl = zip(series.dropFirst(), series).map { $0.0 - $1.0 }
        let dh = zip(series.dropFirst(), series).map { $0.1 - $1.1 }
        func corr(_ lag: Int, _ idx: [Int]) -> Double? {
            let pairs = idx.compactMap { i -> (Double, Double)? in i + lag < dh.count ? (dl[i], dh[i + lag]) : nil }
            guard pairs.count >= 6, let ma = Num.mean(pairs.map { $0.0 }), let mb = Num.mean(pairs.map { $0.1 }) else { return nil }
            var n = 0.0, a = 0.0, b = 0.0
            for (x, y) in pairs { n += (x - ma) * (y - mb); a += (x - ma) * (x - ma); b += (y - mb) * (y - mb) }
            return a > 0 && b > 0 ? n / (a * b).squareRoot() : nil
        }
        let all = Array(0..<dl.count)
        let lags = (0...4).compactMap { l in corr(l, all).map { (l, $0) } }
        // Permutation test over the max-|r|-of-5-lags statistic (deterministic shuffles of the load diffs).
        var permState: UInt64 = 7
        func corrShuffled(_ lag: Int, _ x: [Double]) -> Double? {
            let pairs = (0..<x.count).compactMap { i -> (Double, Double)? in i + lag < dh.count ? (x[i], dh[i + lag]) : nil }
            guard pairs.count >= 6, let ma = Num.mean(pairs.map { $0.0 }), let mb = Num.mean(pairs.map { $0.1 }) else { return nil }
            var n = 0.0, a = 0.0, b = 0.0
            for (x, y) in pairs { n += (x - ma) * (y - mb); a += (x - ma) * (x - ma); b += (y - mb) * (y - mb) }
            return a > 0 && b > 0 ? n / (a * b).squareRoot() : nil
        }
        let observed = lags.map { abs($0.1) }.max() ?? 0
        var exceed = 0
        let perms = 300
        for _ in 0..<perms {
            var x = dl
            for i in stride(from: x.count - 1, to: 0, by: -1) {
                permState = permState &* 6364136223846793005 &+ 1442695040888963407
                x.swapAt(i, Int(permState >> 33) % (i + 1))
            }
            let m = (0...4).compactMap { corrShuffled($0, x) }.map { abs($0) }.max() ?? 0
            if m >= observed { exceed += 1 }
        }
        let pValue = Double(exceed + 1) / Double(perms + 1)
        guard let best = lags.max(by: { abs($0.1) < abs($1.1) }), abs(best.1) >= 0.3, pValue < 0.05 else {
            return MetricResult(id: "adaptationLag", name: "Desfase de adaptación", value: nil, unit: "semanas",
                                summary: "No se ve un desfase claro entre tus cambios de carga y tu VFC.", confidence: .low,
                                sampleSize: series.count, formula: f, version: version)
        }
        // Bootstrap the lag (deterministic resampling).
        var state: UInt64 = 99
        var picks: [Double] = []
        for _ in 0..<200 {
            let idx = (0..<all.count).map { _ -> Int in
                state = state &* 6364136223846793005 &+ 1442695040888963407
                return Int(state >> 33) % all.count
            }
            if let b = (0...4).compactMap({ l in corr(l, idx).map { (l, $0) } }).max(by: { abs($0.1) < abs($1.1) }) { picks.append(Double(b.0)) }
        }
        let s = picks.sorted()
        let ci = s.isEmpty ? Double(best.0)...Double(best.0) : s[Int(Double(s.count) * 0.05)]...s[Int(Double(s.count - 1) * 0.95)]
        return MetricResult(id: "adaptationLag", name: "Desfase de adaptación", value: Double(best.0), unit: "semanas",
                            summary: "Tu VFC tarda unas \(best.0) semana\(best.0 == 1 ? "" : "s") en reflejar un cambio sostenido de carga. Es una estimación personal, no una constante.",
                            interval: ci, confidence: .from(samples: series.count, medium: 20, high: 30), sampleSize: series.count, formula: f,
                            version: version)
    }

    public static func report(days: [DaySummary], sleeps: [SleepSession], workouts: [Workout], journal: [JournalEntry],
                              hrrDrops: [(day: String, drop: Double)] = [], now: Date = Date(), calendar: Calendar = .current) -> IntelligenceReport {
        let sorted = days.sorted { $0.day < $1.day }
        let dev = Deviation.series(sorted)
        let events = LoadResponse.events(days: sorted, deviation: dev, workouts: workouts)
        let habits = HabitImpact.analyze(journal: journal, days: sorted, deviation: dev)
        let today = DayKey.string(now, calendar: calendar)
        let lastDay = sorted.last(where: { $0.recovery != nil })?.day ?? today
        let outlook = RecoveryModel.outlook(days: sorted, deviation: dev, journal: journal, today: lastDay)
        let nowTs = Int(now.timeIntervalSince1970)

        let habitMetric: MetricResult = {
            let clear = habits.filter { $0.isClear }
            let f = "Diferencia media de recuperación al día siguiente (con − sin), IC 90 % de Welch; mínimo 4 días con y 4 sin"
            guard !habits.isEmpty else {
                return .insufficient("habits", "Impacto de tus hábitos", need: "registrar el diario: 4 días con y 4 sin cada hábito",
                                     have: Set(journal.map { $0.day }).count, formula: f, version: HabitImpact.version)
            }
            return MetricResult(id: "habits", name: "Impacto de tus hábitos", value: Double(clear.count), unit: "con efecto claro",
                                summary: clear.first?.summary ?? "Aún no hay ningún hábito con un efecto claro en tu recuperación.",
                                confidence: .from(samples: habits.map { min($0.withCount, $0.withoutCount) }.max() ?? 0, medium: 8, high: 15),
                                sampleSize: habits.count, formula: f, version: HabitImpact.version)
        }()

        let sections = [
            IntelligenceReport.Section(title: "Hoy", subtitle: "Cómo de habitual es tu estado y qué esperar mañana", metrics: [
                Deviation.coherenceMetric(dev), Deviation.debtMetric(dev), RecoveryModel.forecastMetric(outlook),
                RecoveryModel.surpriseMetric(outlook), Rhythms.cardiacCostMetric(sorted),
            ]),
            IntelligenceReport.Section(title: "Respuesta a la carga", subtitle: "Qué te pasa en las noches después de un día exigente", metrics: [
                LoadResponse.velocityMetric(events), LoadResponse.efficiencyMetric(events), LoadResponse.consistencyMetric(events),
                WorkoutAnalysis.hrrTrendMetric(hrrDrops), LoadResponse.adaptationMetric(events), LoadResponse.ceilingMetric(events),
                adaptationLag(sorted, calendar: calendar),
            ]),
            IntelligenceReport.Section(title: "Sueño y ritmo", subtitle: "Horarios, regularidad y qué te cuesta dormir mal",
                                       metrics: Rhythms.regularityMetrics(sleeps: sleeps, now: nowTs, calendar: calendar)
                                           + [Rhythms.nadirMetric(sleeps)] + Rhythms.sleepEffects(days: sorted, calendar: calendar)),
            IntelligenceReport.Section(title: "Hábitos y predicción", subtitle: "Qué se asocia con tu recuperación y cuánto puedes fiarte del modelo",
                                       metrics: [habitMetric, RecoveryModel.predictabilityMetric(outlook)]),
        ]
        return IntelligenceReport(deviation: dev, events: events, fingerprints: LoadResponse.fingerprints(events), habits: habits,
                                  outlook: outlook, sections: sections, generated: now)
    }
}
