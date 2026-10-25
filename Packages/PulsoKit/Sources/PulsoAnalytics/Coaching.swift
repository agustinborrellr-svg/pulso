import Foundation
import PulsoStore

// MARK: - Training load

/// Acute / chronic training load from daily Strain (Banister-style exponentially weighted averages).
///
/// Daily load is the cardiovascular load behind each day's Strain (the inverse of `Strain.score`).
/// ATL = 7-day EWMA (fatigue), CTL = 42-day EWMA (fitness), TSB = CTL − ATL (form) and
/// ACWR = ATL / CTL (acute:chronic ratio; 0.8–1.3 is the usual "sweet spot").
public enum TrainingLoad {
    public struct Point: Equatable {
        public var day: String
        public var load: Double
        public var atl: Double
        public var ctl: Double
        public var tsb: Double { ctl - atl }
        public var acwr: Double? { ctl > 1 ? atl / ctl : nil }
    }

    public enum Status: String, Equatable {
        case calibrating, detraining, maintaining, optimal, overreaching, risk

        public var label: String {
            switch self {
            case .calibrating: return "Calibrando"
            case .detraining: return "Perdiendo forma"
            case .maintaining: return "Mantenimiento"
            case .optimal: return "Progresión óptima"
            case .overreaching: return "Carga alta"
            case .risk: return "Riesgo de sobrecarga"
            }
        }

        public var advice: String {
            switch self {
            case .calibrating: return "Necesito unas dos semanas de datos para medir tu carga."
            case .detraining: return "Tu carga reciente está muy por debajo de lo habitual. Puedes subir poco a poco."
            case .maintaining: return "Carga estable. Para mejorar, añade algo de intensidad o volumen."
            case .optimal: return "Estás subiendo carga a buen ritmo sin pasarte."
            case .overreaching: return "Llevas más carga de la habitual. Vigila la recuperación y el sueño."
            case .risk: return "Has subido la carga demasiado deprisa. Mete un par de días suaves."
            }
        }
    }

    /// Load (TRIMP-like) that produced `strain` (inverse of `Strain.score`).
    public static func load(fromStrain strain: Double) -> Double {
        guard strain > 0 else { return 0 }
        return exp(min(strain, 21) / 21 * log(1 + Strain.ceilingLoad)) - 1
    }

    /// One point per calendar day from the first summary to `through` (missing days count as rest).
    public static func series(_ days: [DaySummary], through: String? = nil, calendar: Calendar = .current) -> [Point] {
        let sorted = days.filter { $0.strain != nil }.sorted { $0.day < $1.day }
        guard let first = sorted.first?.day else { return [] }
        let last = through ?? sorted.last!.day
        let byDay = Dictionary(sorted.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let ka = 1 - exp(-1.0 / 7), kc = 1 - exp(-1.0 / 42)
        // Seed both averages with the first fortnight's mean: starting from zero would make anyone
        // with a steady routine look like they had just spiked their load.
        let seedDays = (0..<14).map { DayKey.shift(first, days: $0, calendar: calendar) }.filter { $0 <= last }
        let seed = seedDays.map { byDay[$0]?.strain.map { load(fromStrain: $0) } ?? 0 }.reduce(0, +) / Double(max(1, seedDays.count))
        var atl = seed, ctl = seed
        var out: [Point] = []
        var day = first
        var guardCount = 0
        while day <= last && guardCount < 5000 {
            let l = byDay[day]?.strain.map { load(fromStrain: $0) } ?? 0
            atl += (l - atl) * ka
            ctl += (l - ctl) * kc
            out.append(Point(day: day, load: l, atl: atl, ctl: ctl))
            day = DayKey.shift(day, days: 1, calendar: calendar)
            guardCount += 1
        }
        return out
    }

    public static func status(_ series: [Point]) -> Status {
        guard series.count >= 14, let p = series.last, let r = p.acwr else { return .calibrating }
        switch r {
        case ..<0.8: return .detraining
        case ..<1.0: return .maintaining
        case ..<1.3: return .optimal
        case ..<1.5: return .overreaching
        default: return .risk
        }
    }
}

// MARK: - Illness / early warning

/// Flags nights where several vital signs move away from the wearer's baseline at once — the
/// pattern that often shows up a day or two before feeling ill (or with alcohol, heat, jet lag).
public enum HealthMonitor {
    public enum Level: Int, Comparable, Equatable {
        case normal = 0, watch = 1, alert = 2
        public static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
    }

    public struct Signal: Equatable {
        public var key: String
        public var label: String
        public var detail: String
        public var weight: Int
    }

    public struct Assessment: Equatable {
        public var day: String
        public var level: Level
        public var signals: [Signal]

        public var title: String {
            switch level {
            case .normal: return "Constantes normales"
            case .watch: return "Constantes alteradas"
            case .alert: return "Posible inicio de enfermedad"
            }
        }

        public var message: String {
            guard !signals.isEmpty else { return "Tus constantes de anoche están dentro de lo habitual." }
            let list = signals.map { $0.detail }.joined(separator: ", ")
            switch level {
            case .alert:
                return "Varias constantes fuera de lo normal a la vez (\(list)). Suele adelantarse a resfriados o infecciones; también pasa con alcohol, calor o viajes. Descansa, hidrátate y evita entrenar fuerte hoy."
            case .watch:
                return "Algo fuera de lo normal: \(list). Tómatelo con calma hoy."
            case .normal:
                return list
            }
        }
    }

    /// `history` = days strictly before `day` (used for the baselines).
    public static func assess(_ day: DaySummary, history: [DaySummary]) -> Assessment {
        let b = Baselines.from(history: history)
        var signals: [Signal] = []
        if let t = day.skinTemp, let bt = b.temp, bt.isUsable {
            let dev = t - bt.center
            if dev >= 0.5 {
                signals.append(Signal(key: "temp", label: "Temperatura", detail: String(format: "temperatura %+.1f °C", dev),
                                      weight: dev >= 0.8 ? 2 : 1))
            }
        }
        if let r = day.rhr, let br = b.rhr, br.isUsable {
            let d = r - br.center
            if d >= max(4, 2 * br.spread) {
                signals.append(Signal(key: "rhr", label: "FC en reposo", detail: String(format: "FC en reposo +%.0f lpm", d),
                                      weight: d >= 8 ? 2 : 1))
            }
        }
        if let r = day.respRate, let br = b.resp, br.isUsable {
            let d = r - br.center
            if d >= max(0.8, 2 * br.spread) {
                signals.append(Signal(key: "resp", label: "Respiración", detail: String(format: "respiración +%.1f rpm", d), weight: 1))
            }
        }
        if let h = day.hrv, h > 0, let bh = b.lnHRV, bh.isUsable, bh.z(log(h)) <= -1.5 {
            let pct = (h / exp(bh.center) - 1) * 100
            signals.append(Signal(key: "hrv", label: "VFC", detail: String(format: "VFC %.0f %%", pct), weight: 1))
        }
        if let s = day.spo2, let bs = b.spo2, bs.isUsable, s <= bs.center - 2 {
            signals.append(Signal(key: "spo2", label: "SpO₂", detail: String(format: "SpO₂ %.0f %%", s), weight: 1))
        }
        let score = signals.reduce(0) { $0 + $1.weight }
        let core = signals.contains { $0.key == "temp" || $0.key == "resp" }
        let level: Level = score >= 3 && core ? .alert : (score >= 2 ? .watch : .normal)
        return Assessment(day: day.day, level: level, signals: signals)
    }

    /// Multi-day drifts worth a heads-up even when no single night is alarming.
    public static func trends(_ days: [DaySummary]) -> [Signal] {
        let sorted = days.sorted { $0.day < $1.day }
        guard sorted.count >= 10 else { return [] }
        let recent = Array(sorted.suffix(3)), history = Array(sorted.dropLast(3))
        let b = Baselines.from(history: history)
        var out: [Signal] = []
        let hrvs = recent.compactMap { $0.hrv }.filter { $0 > 0 }
        if hrvs.count == 3, let bh = b.lnHRV, bh.isUsable, let m = Stats.mean(hrvs.map { log($0) }), (m - bh.center) / bh.spread <= -1 {
            out.append(Signal(key: "hrv_trend", label: "VFC", detail: "tu VFC lleva 3 días por debajo de lo habitual", weight: 1))
        }
        let rhrs = recent.compactMap { $0.rhr }
        if rhrs.count == 3, let br = b.rhr, br.isUsable, let m = Stats.mean(rhrs), m - br.center >= 3 {
            out.append(Signal(key: "rhr_trend", label: "FC en reposo", detail: "tu FC en reposo lleva 3 días alta", weight: 1))
        }
        let debts = recent.compactMap { $0.sleepDebtMinutes }
        if debts.count == 3, debts.allSatisfy({ $0 >= 120 }) {
            out.append(Signal(key: "debt_trend", label: "Sueño", detail: "acumulas más de 2 h de deuda de sueño", weight: 1))
        }
        return out
    }
}

// MARK: - Daily coach

/// Today's recommended Strain range and the reasoning behind it.
public enum DailyCoach {
    public struct Advice: Equatable {
        public var strainTarget: ClosedRange<Double>
        public var headline: String
        public var notes: [String]
    }

    public static func baseTarget(recovery: Double) -> ClosedRange<Double> {
        switch recovery {
        case 67...: return 14...18
        case 34..<67: return 10...14
        default: return 4...10
        }
    }

    public static func advice(recovery: Double?, load: [TrainingLoad.Point], health: HealthMonitor.Assessment?,
                              sleepDebtMinutes: Double?) -> Advice {
        var target = baseTarget(recovery: recovery ?? 50)
        var notes: [String] = []
        var headline: String
        switch recovery.map(Recovery.band) {
        case .green?: headline = "Tu cuerpo está listo para rendir."
        case .yellow?: headline = "Recuperación moderada: esfuerzo razonable."
        case .red?: headline = "Hoy toca priorizar el descanso."
        case nil: headline = "Sin recuperación todavía: escucha a tu cuerpo."
        }
        func cap(_ hi: Double) {
            let upper = min(target.upperBound, hi)
            target = min(target.lowerBound, upper - 2)...upper
        }
        let status = TrainingLoad.status(load)
        if status == .risk {
            cap(12)
            notes.append("Has subido la carga muy deprisa: mejor un día suave.")
        } else if status == .overreaching {
            cap(15)
            notes.append("Llevas más carga de la habitual.")
        } else if status == .detraining, (recovery ?? 0) >= 67 {
            notes.append("Buen día para un entreno de calidad: llevas poca carga.")
        }
        if let h = health {
            if h.level == .alert {
                target = 2...8
                headline = "Tus constantes indican que podrías estar incubando algo."
                notes.append("Descanso activo como mucho: paseo, movilidad.")
            } else if h.level == .watch {
                cap(12)
                notes.append("Alguna constante alterada: no apures.")
            }
        }
        if let debt = sleepDebtMinutes, debt >= 90 {
            notes.append("Debes \(Int(debt / 60)) h \(Int(debt.truncatingRemainder(dividingBy: 60))) min de sueño: acuéstate antes esta noche.")
        }
        return Advice(strainTarget: max(0, target.lowerBound)...max(target.lowerBound, target.upperBound), headline: headline, notes: notes)
    }
}

// MARK: - Sleep planning

/// Bedtime, caffeine cut-off and tonight's need, from the same model as the nightly sleep score.
public enum SleepPlanner {
    public struct Plan: Equatable {
        public var needMinutes: Double
        public var inBedMinutes: Double
        public var wake: Date
        public var bedtime: Date
        public var caffeineCutoff: Date
        public var lastMeal: Date
    }

    /// Tonight's need given today's strain so far, recent shortfalls and today's naps.
    public static func tonightNeed(profile: Profile, today: DaySummary?, recent: [DaySummary]) -> Double {
        let shortfalls = recent.suffix(3).compactMap { d -> Double? in
            guard let need = d.sleepNeedMinutes, let slept = d.sleepMinutes else { return nil }
            return need - slept
        }
        return SleepCoach.need(baseHours: profile.sleepNeedHours, previousStrain: today?.strain,
                               recentShortfalls: shortfalls, napMinutes: today?.napMinutes ?? 0)
    }

    /// Typical wake time (minutes after midnight) over the last two weeks.
    public static func typicalWakeMinutes(_ days: [DaySummary], calendar: Calendar = .current) -> Double? {
        let wakes = days.suffix(14).compactMap { $0.sleepEnd }.map { SleepCoach.minutesAfterMidnight(ts: $0, calendar: calendar) }
        guard wakes.count >= 3 else { return nil }
        return Stats.circularMeanMinutes(wakes)
    }

    public static func plan(wake: Date, needMinutes: Double, recent: [DaySummary], latencyMinutes: Double = 15) -> Plan {
        let eff = Stats.median(recent.suffix(14).compactMap { $0.sleepEfficiency }.filter { $0 > 0.5 }) ?? 0.9
        let inBed = needMinutes / max(0.75, min(0.98, eff)) + latencyMinutes
        let bed = wake.addingTimeInterval(-inBed * 60)
        return Plan(needMinutes: needMinutes, inBedMinutes: inBed, wake: wake, bedtime: bed,
                    caffeineCutoff: bed.addingTimeInterval(-8 * 3600), lastMeal: bed.addingTimeInterval(-3 * 3600))
    }
}

// MARK: - Menstrual cycle (opt-in)

/// Estimates the menstrual phase from the biphasic nightly skin-temperature pattern (the luteal
/// phase runs ~0.2–0.5 °C warmer). Wellness estimate only — never contraception.
public enum CycleTracker {
    public enum Phase: String, Equatable {
        case unknown, follicular, luteal

        public var label: String {
            switch self {
            case .unknown: return "Sin datos suficientes"
            case .follicular: return "Fase folicular"
            case .luteal: return "Fase lútea"
            }
        }
    }

    public struct Estimate: Equatable {
        public var phase: Phase
        /// Days estimated as ovulation (the night before each temperature shift).
        public var ovulations: [String]
        /// Days estimated as the start of a period (temperature drop after a luteal phase).
        public var periodStarts: [String]
        public var averageCycleDays: Double?
        public var nextPeriod: String?
    }

    public static func estimate(_ days: [DaySummary], calendar: Calendar = .current) -> Estimate {
        let series = days.sorted { $0.day < $1.day }.compactMap { d in d.skinTemp.map { (day: d.day, t: $0) } }
        guard series.count >= 20 else {
            return Estimate(phase: .unknown, ovulations: [], periodStarts: [], averageCycleDays: nil, nextPeriod: nil)
        }
        // 3-night running median to tame single noisy nights.
        let smooth: [Double] = series.indices.map { i in
            Stats.median(series[max(0, i - 1)...min(series.count - 1, i + 1)].map { $0.t }) ?? series[i].t
        }
        var ovulations: [String] = [], starts: [String] = []
        var luteal = false
        var lutealStart = 0
        var coverline = 0.0
        var i = 6
        while i + 2 < smooth.count {
            if !luteal {
                // "3 over 6": three nights all ≥ 0.2 °C above the highest of the previous six.
                let prevMax = smooth[(i - 6)..<i].max() ?? 0
                if smooth[i...(i + 2)].allSatisfy({ $0 >= prevMax + 0.2 }) {
                    luteal = true
                    lutealStart = i
                    coverline = prevMax + 0.1
                    ovulations.append(series[i - 1].day)
                    i += 3
                    continue
                }
            } else if i - lutealStart >= 9, smooth[i] < coverline, smooth[i + 1] < coverline {
                luteal = false
                starts.append(series[i].day)
                i += 6
                continue
            }
            i += 1
        }
        var avg: Double?
        if starts.count >= 2 {
            var gaps: [Double] = []
            for k in 1..<starts.count {
                if let a = DayKey.date(starts[k - 1], calendar: calendar), let b = DayKey.date(starts[k], calendar: calendar) {
                    let g = Double(calendar.dateComponents([.day], from: a, to: b).day ?? 0)
                    if (20...45).contains(g) { gaps.append(g) }
                }
            }
            avg = Stats.mean(gaps)
        }
        var next: String?
        if luteal, let ov = ovulations.last {
            next = DayKey.shift(ov, days: 14, calendar: calendar)
        } else if let s = starts.last {
            next = DayKey.shift(s, days: Int((avg ?? 28).rounded()), calendar: calendar)
        }
        let recentEnough = series.count - lutealStart < 25 || !luteal
        return Estimate(phase: recentEnough ? (luteal ? .luteal : .follicular) : .unknown, ovulations: ovulations,
                        periodStarts: starts, averageCycleDays: avg, nextPeriod: next)
    }
}

// MARK: - Workout merging (imports from Health / Strava)

public enum WorkoutMerge {
    public enum Decision: Equatable {
        /// Nothing similar exists: store it as a new workout.
        case insert
        /// Same session as an existing workout: just link the ids (index into `existing`).
        case link(Int)
        /// Overlaps an automatically detected bout: the import replaces it (index into `existing`).
        case replaceAuto(Int)
        /// Already imported from this service.
        case duplicate(Int)
    }

    static func overlapFraction(_ a: Workout, _ b: Workout) -> Double {
        let o = min(a.end, b.end) - max(a.start, b.start)
        let shorter = min(a.end - a.start, b.end - b.start)
        guard o > 0, shorter > 0 else { return 0 }
        return Double(o) / Double(shorter)
    }

    /// `service` is the key used in `externalIDs` ("strava", "health").
    public static func decide(_ incoming: Workout, service: String, existing: [Workout]) -> Decision {
        if let id = incoming.externalID(service), let i = existing.firstIndex(where: { $0.externalID(service) == id }) {
            return .duplicate(i)
        }
        let candidates = existing.indices
            .map { (i: $0, f: overlapFraction(incoming, existing[$0])) }
            .filter { $0.f >= 0.5 }
            .sorted { $0.f > $1.f }
        guard let best = candidates.first else { return .insert }
        return existing[best.i].source == .auto ? .replaceAuto(best.i) : .link(best.i)
    }

    /// Folds an import into an existing workout: keeps the strap's numbers, adds ids, distance and
    /// (for automatic bouts) the real sport name.
    public static func link(_ incoming: Workout, into w: Workout, service: String) -> Workout {
        var out = w
        for (k, v) in incoming.externalIDs ?? [:] { out.setExternalID(v, for: k) }
        if out.distanceMeters == nil { out.distanceMeters = incoming.distanceMeters }
        if out.externalApp == nil { out.externalApp = incoming.externalApp }
        if out.sport == "Actividad" { out.sport = incoming.sport }
        return out
    }
}

// MARK: - Weekly summary

public enum WeeklySummary {
    public struct Summary: Equatable {
        public var from: String
        public var to: String
        public var recovery: Double?
        public var hrv: Double?
        public var rhr: Double?
        public var sleepMinutes: Double?
        public var strain: Double?
        public var workouts: Int
        /// Same metrics for the previous week, for deltas.
        public var previousRecovery: Double?
        public var previousHRV: Double?
        public var previousSleep: Double?
        public var previousStrain: Double?

        public var text: String {
            var parts: [String] = []
            if let r = recovery { parts.append("recuperación media \(Int(r.rounded())) %\(delta(r, previousRecovery, "pts"))") }
            if let s = sleepMinutes { parts.append("sueño \(Int(s / 60)) h \(Int(s.truncatingRemainder(dividingBy: 60))) min\(delta(s, previousSleep, "min"))") }
            if let h = hrv { parts.append("VFC \(Int(h.rounded())) ms\(delta(h, previousHRV, "ms"))") }
            if let st = strain { parts.append(String(format: "esfuerzo %.1f", st) + delta(st, previousStrain, "")) }
            parts.append("\(workouts) entreno\(workouts == 1 ? "" : "s")")
            return parts.joined(separator: " · ")
        }

        private func delta(_ v: Double, _ p: Double?, _ unit: String) -> String {
            guard let p else { return "" }
            let d = v - p
            guard abs(d) >= 0.5 else { return "" }
            return String(format: " (%+.0f%@)", d, unit.isEmpty ? "" : " " + unit)
        }
    }

    /// The 7 days ending on `endDay` (inclusive) vs the 7 before.
    public static func compute(_ days: [DaySummary], endDay: String, calendar: Calendar = .current) -> Summary {
        let start = DayKey.shift(endDay, days: -6, calendar: calendar)
        let prevStart = DayKey.shift(endDay, days: -13, calendar: calendar)
        let prevEnd = DayKey.shift(endDay, days: -7, calendar: calendar)
        let week = days.filter { $0.day >= start && $0.day <= endDay }
        let prev = days.filter { $0.day >= prevStart && $0.day <= prevEnd }
        func m(_ list: [DaySummary], _ k: (DaySummary) -> Double?) -> Double? { Stats.mean(list.compactMap(k)) }
        return Summary(from: start, to: endDay,
                       recovery: m(week) { $0.recovery }, hrv: m(week) { $0.hrv }, rhr: m(week) { $0.rhr },
                       sleepMinutes: m(week) { $0.sleepMinutes }, strain: m(week) { $0.strain },
                       workouts: week.reduce(0) { $0 + $1.workoutCount },
                       previousRecovery: m(prev) { $0.recovery }, previousHRV: m(prev) { $0.hrv },
                       previousSleep: m(prev) { $0.sleepMinutes }, previousStrain: m(prev) { $0.strain })
    }
}
