import Foundation
import PulsoStore
import PulsoAnalytics

/// One card on Inicio. The night-pending, nap question, alarm and bedtime cards are not here: they appear on
/// their own when relevant and can't be removed.
struct HomeWidget: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case hero, sleep, strainRecovery, plan, stress, vitals, activity, pulsoAge, hrv, respiration, skinTemp, spo2, journal, metric
    }

    enum Size: String, Codable { case small, large }

    var kind: Kind
    /// `TrendMetric` raw value, only for `.metric`.
    var metric: String?
    var size: Size = .large
    /// Days the "usual" (and the mini chart) covers: 7 or 30.
    var period: Int = 30

    var id: String { kind == .metric ? "metric.\(metric ?? "")" : kind.rawValue }

    var trendMetric: TrendMetric? {
        switch kind {
        case .metric: return metric.flatMap(TrendMetric.init(rawValue:))
        case .hrv: return .hrv
        case .respiration: return .respRate
        case .skinTemp: return .skinTemp
        case .spo2: return .spo2
        default: return nil
        }
    }

    var title: String {
        switch kind {
        case .hero: return "Diales del día"
        case .sleep: return "Resumen del sueño"
        case .strainRecovery: return "Esfuerzo y recuperación"
        case .plan: return "Plan semanal"
        case .stress: return "Monitor de estrés"
        case .vitals: return "Constantes"
        case .activity: return "Pasos y calorías"
        case .pulsoAge: return "Edad Pulso"
        case .hrv: return "VFC (gráfica)"
        case .respiration: return "Respiración (gráfica)"
        case .skinTemp: return "Temperatura (gráfica)"
        case .spo2: return "SpO₂ (gráfica, experimental)"
        case .journal: return "Diario"
        case .metric: return trendMetric.map(HomeLayout.title) ?? "Métrica"
        }
    }

    var icon: String {
        switch kind {
        case .hero: return "circle.circle"
        case .sleep: return "moon.zzz"
        case .strainRecovery: return "chart.xyaxis.line"
        case .plan: return "checklist"
        case .stress: return "gauge.with.dots.needle.33percent"
        case .vitals: return "square.grid.2x2"
        case .activity: return "shoeprints.fill"
        case .pulsoAge: return "hourglass"
        case .journal: return "book"
        default: return trendMetric?.icon ?? "square"
        }
    }

    var allowsSmall: Bool {
        switch kind {
        case .metric, .hrv, .respiration, .skinTemp, .spo2, .pulsoAge, .activity: return true
        default: return false
        }
    }

    var allowsPeriod: Bool {
        switch kind {
        case .metric, .hrv, .respiration, .skinTemp, .spo2, .activity, .vitals: return true
        default: return false
        }
    }

    static func card(_ k: Kind) -> HomeWidget { HomeWidget(kind: k) }
    static func row(_ m: TrendMetric) -> HomeWidget { HomeWidget(kind: .metric, metric: m.rawValue) }
}

/// Inicio's arrangement, saved as JSON in `pulso.home`; the old metric-only list (`pulso.dashboard`) seeds it once.
enum HomeLayout {
    static let key = "pulso.home"
    static let legacyKey = "pulso.dashboard"
    static let maxItems = 30

    static let legacyDefault: [TrendMetric] = [
        .hrv, .rhr, .respRate, .sleepPerformance, .sleepHours, .sleepDebt, .efficiency, .strain, .avgHR,
        .calories, .steps, .zonesLight, .zonesHard, .vo2max, .recovery, .regularity, .restorativePct, .restorativeHours, .timeInBed,
    ]

    static func defaults(metrics: [TrendMetric] = legacyDefault) -> [HomeWidget] {
        [.card(.hero), .card(.sleep), .card(.strainRecovery), .card(.plan), .card(.stress)]
            + metrics.map(HomeWidget.row)
            + [.card(.journal)]
    }

    static func decode(_ raw: String, legacy: String? = UserDefaults.standard.string(forKey: legacyKey)) -> [HomeWidget] {
        if let data = raw.data(using: .utf8), !raw.isEmpty,
           let list = try? JSONDecoder().decode([HomeWidget].self, from: data) {
            return sanitize(list)
        }
        guard let legacy else { return defaults() }
        let metrics = legacy.split(separator: ",").compactMap { TrendMetric(rawValue: String($0)) }
        return defaults(metrics: metrics)
    }

    static func encode(_ list: [HomeWidget]) -> String {
        guard let data = try? JSONEncoder().encode(sanitize(list)) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Drops unknown metrics and duplicates, clamps options to what each card allows, caps the count.
    static func sanitize(_ list: [HomeWidget]) -> [HomeWidget] {
        var seen = Set<String>()
        var out: [HomeWidget] = []
        for var w in list {
            if w.kind == .metric && w.trendMetric == nil { continue }
            guard seen.insert(w.id).inserted else { continue }
            if !w.allowsSmall { w.size = .large }
            w.period = w.period == 7 ? 7 : 30
            out.append(w)
        }
        return Array(out.prefix(maxItems))
    }

    /// Small tiles go two per line; a small tile left alone keeps its half width so the grid stays even.
    static func lines(_ list: [HomeWidget]) -> [[HomeWidget]] {
        var out: [[HomeWidget]] = []
        var pending: HomeWidget?
        for w in list {
            if w.size == .small {
                if let p = pending {
                    out.append([p, w])
                    pending = nil
                } else {
                    pending = w
                }
            } else {
                if let p = pending { out.append([p]); pending = nil }
                out.append([w])
            }
        }
        if let p = pending { out.append([p]) }
        return out
    }

    /// Cards that can still be added.
    static func addable(to list: [HomeWidget]) -> [HomeWidget] {
        let ids = Set(list.map(\.id))
        let cards = HomeWidget.Kind.allCases.filter { $0 != .metric }.map(HomeWidget.card)
        let metrics = TrendMetric.allCases.map(HomeWidget.row)
        return (cards + metrics).filter { !ids.contains($0.id) }
    }

    /// Inicio's name for a metric: the strap can't see you get into bed, only when you became still.
    static func title(_ m: TrendMetric) -> String {
        m == .timeInBed ? "Bloque de sueño detectado" : m.title
    }
}

extension TrendMetric {
    /// Grows or shifts through the day, so an open cycle can't be compared with whole days.
    var accumulatesDuringDay: Bool {
        switch self {
        case .strain, .avgHR, .calories, .steps, .zonesLight, .zonesHard, .stress, .stressHigh: return true
        default: return false
        }
    }
}

extension AppModel {
    /// The cycle still running (it closes when you next fall asleep).
    func isOpenCycle(_ day: DaySummary) -> Bool { day.day == currentDayKey }

    /// "En curso · hasta las 14:20" for the open cycle; nil once the day is closed.
    func inProgressText(_ day: DaySummary) -> String? {
        guard isOpenCycle(day) else { return nil }
        let until = day.cycleEnd ?? lastSampleTs
        return until.map { "En curso · hasta las \(Fmt.time($0))" } ?? "En curso"
    }

    /// Usual daily value over the `period` days before `day` (whole days only).
    func usual(_ m: TrendMetric, before day: DaySummary, period: Int) -> Double? {
        TrendSeries.window(days: days.filter { $0.day < day.day }, value: { m.value($0) },
                           period: period == 7 ? .week : .month, today: DayKey.shift(day.day, days: -1)).summary
    }

    /// Daily values of the `period` days ending on `day`, oldest first, for mini charts.
    func recentValues(_ m: TrendMetric, through day: DaySummary, period: Int) -> [(day: String, value: Double)] {
        let from = DayKey.shift(day.day, days: -(period - 1))
        return days.filter { $0.day >= from && $0.day <= day.day }.compactMap { d in m.value(d).map { (d.day, $0) } }
    }
}
