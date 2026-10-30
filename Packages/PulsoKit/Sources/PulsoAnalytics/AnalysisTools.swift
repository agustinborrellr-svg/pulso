import Foundation
import PulsoStore

/// «Por qué este %»: the recovery score as a waterfall from a normal day for you, one factor at a time.
public enum RecoveryWaterfall {
    public struct Step: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var label: String
        /// Points this factor adds (or takes away).
        public var points: Double
        /// Running total after this step.
        public var total: Double
    }

    /// The score of a day exactly at your baselines (all factors at zero).
    public static var neutral: Double { Recovery.curve(composite: 0) }

    /// Biggest factors first; the last total is the recovery % (before rounding).
    public static func steps(_ contributors: [Contributor]) -> [Step] {
        var composite = 0.0
        var total = neutral
        return contributors.sorted { abs($0.impact) > abs($1.impact) }.map { c in
            composite += c.impact
            let next = Recovery.curve(composite: composite)
            defer { total = next }
            return Step(key: c.key, label: c.label, points: next - total, total: next)
        }
    }
}

/// Explorer: how two of your metrics move together.
public enum Relation {
    public struct Result: Equatable, Sendable {
        public var n: Int
        /// Pearson r.
        public var r: Double
        /// y ≈ slope · x + intercept.
        public var slope: Double
        public var intercept: Double

        public var strength: String {
            let a = abs(r)
            if n < 10 { return "Pocos datos" }
            if a < 0.1 { return "Sin relación" }
            if a < 0.3 { return "Relación débil" }
            if a < 0.5 { return "Relación moderada" }
            return "Relación fuerte"
        }
    }

    /// Pairs with both values; `lag` = 1 compares x of one day with y of the next.
    public static func pairs(_ x: [Double?], _ y: [Double?], lag: Int = 0) -> [(x: Double, y: Double)] {
        guard x.count == y.count, lag >= 0, x.count > lag else { return [] }
        return (0..<(x.count - lag)).compactMap { i in
            guard let a = x[i], let b = y[i + lag], a.isFinite, b.isFinite else { return nil }
            return (a, b)
        }
    }

    /// Pairs by calendar date: x of day D with y of day D + `lagDays`. Gaps in the history never pair two days
    /// that aren't consecutive (pairing by list position did).
    public static func pairs(days: [String], _ x: [Double?], _ y: [Double?], lagDays: Int) -> [(x: Double, y: Double)] {
        guard days.count == x.count, days.count == y.count else { return [] }
        var yByDay: [String: Double] = [:]
        for (d, v) in zip(days, y) { if let v, v.isFinite { yByDay[d] = v } }
        return zip(days, x).compactMap { d, a in
            guard let a, a.isFinite, let b = yByDay[lagDays == 0 ? d : DayKey.shift(d, days: lagDays)] else { return nil }
            return (a, b)
        }
    }

    public static func fit(_ p: [(x: Double, y: Double)]) -> Result? {
        guard p.count >= 3 else { return nil }
        let n = Double(p.count)
        let mx = p.reduce(0) { $0 + $1.x } / n, my = p.reduce(0) { $0 + $1.y } / n
        var sxx = 0.0, syy = 0.0, sxy = 0.0
        for q in p {
            sxx += (q.x - mx) * (q.x - mx)
            syy += (q.y - my) * (q.y - my)
            sxy += (q.x - mx) * (q.y - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        let slope = sxy / sxx
        return Result(n: p.count, r: sxy / (sxx * syy).squareRoot(), slope: slope, intercept: my - slope * mx)
    }
}

/// Streaks and personal records.
public enum Records {
    public struct Streak: Equatable, Sendable {
        public var current: Int
        public var best: Int
        public var bestEnd: String?
    }

    /// Consecutive calendar days meeting `rule` (a day without data breaks the streak, except today if it
    /// has no data yet).
    public static func streak(_ days: [DaySummary], today: String, rule: (DaySummary) -> Bool?) -> Streak {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        guard let first = days.map(\.day).min() else { return Streak(current: 0, best: 0, bestEnd: nil) }
        var best = 0, run = 0
        var bestEnd: String?
        var day = first
        var guardCount = 0
        while day <= today && guardCount < 5000 {
            guardCount += 1
            if let d = byDay[day], rule(d) == true {
                run += 1
                if run > best { best = run; bestEnd = day }
            } else if !(day == today && (byDay[day].map(rule) ?? nil) == nil) {
                run = 0
            }
            day = DayKey.shift(day, days: 1)
        }
        return Streak(current: run, best: best, bestEnd: bestEnd)
    }

    public struct Record: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var value: Double
        public var day: String
    }

    public static func personalBests(_ days: [DaySummary]) -> [Record] {
        func best(_ title: String, _ v: (DaySummary) -> Double?, lowest: Bool = false) -> Record? {
            let vals = days.compactMap { d in v(d).map { (d.day, $0) } }
            guard let r = lowest ? vals.min(by: { $0.1 < $1.1 }) : vals.max(by: { $0.1 < $1.1 }) else { return nil }
            return Record(title: title, value: r.1, day: r.0)
        }
        return [
            best("Mejor recuperación", { $0.recovery }),
            best("VFC más alta", { $0.hrv }),
            best("FC en reposo más baja", { $0.rhr }, lowest: true),
            best("Día más exigente", { $0.strain }),
            best("Noche más larga", { $0.sleepMinutes }),
            best("Más pasos", { $0.steps.map(Double.init) }),
            best("VO₂ máx más alto (estimado)", { $0.vo2max }),
        ].compactMap { $0 }
    }
}

/// The monthly report (shown and exported as PDF).
public enum MonthlyReport {
    public struct Line: Equatable, Sendable, Identifiable {
        public var id: String { title }
        public var title: String
        public var unit: String
        public var value: Double?
        public var previous: Double?
        public var higherIsBetter: Bool
        public var delta: Double? { value.flatMap { v in previous.map { v - $0 } } }
    }

    public struct Report: Equatable, Sendable {
        public var month: String
        public var daysWithData: Int
        public var lines: [Line]
        public var workouts: Int
        public var workoutMinutes: Double
        public var topSports: [(name: String, count: Int)]
        public var bestDay: String?
        public var worstDay: String?
        public var greenDays: Int
        public var redDays: Int

        public static func == (a: Report, b: Report) -> Bool {
            a.month == b.month && a.lines == b.lines && a.workouts == b.workouts && a.daysWithData == b.daysWithData
        }
    }

    /// `month` as "yyyy-MM".
    public static func build(month: String, days: [DaySummary], workouts: [Workout], calendar: Calendar = .current) -> Report {
        let prevMonth = shiftMonth(month, -1)
        let cur = days.filter { $0.day.hasPrefix(month) }
        let prev = days.filter { $0.day.hasPrefix(prevMonth) }
        func avg(_ ds: [DaySummary], _ v: (DaySummary) -> Double?) -> Double? { Stats.mean(ds.compactMap(v)) }
        func line(_ t: String, _ u: String, _ hib: Bool, _ v: @escaping (DaySummary) -> Double?) -> Line {
            Line(title: t, unit: u, value: avg(cur, v), previous: avg(prev, v), higherIsBetter: hib)
        }
        let lines = [
            line("Recuperación media", "%", true) { $0.recovery },
            line("VFC", "ms", true) { $0.hrv },
            line("FC en reposo", "lpm", false) { $0.rhr },
            line("Horas de sueño", "h", true) { $0.sleepMinutes.map { $0 / 60 } },
            line("Calificación del sueño", "%", true) { $0.sleepPerformance.map { $0 * 100 } },
            line("Regularidad", "%", true) { $0.sleepConsistency },
            line("Esfuerzo diario", "", true) { $0.strain },
            line("Pasos", "", true) { $0.steps.map(Double.init) },
            line("Estrés diurno", "/3", false) { $0.stressAvg },
            line("VO₂ máx", "", true) { $0.vo2max },
        ]
        let ws = workouts.filter { DayKey.string(ts: $0.start, calendar: calendar).hasPrefix(month) }
        var counts: [String: Int] = [:]
        for w in ws { counts[w.sport, default: 0] += 1 }
        let top = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map { (name: $0.key, count: $0.value) }
        let scored = cur.filter { $0.recovery != nil }
        return Report(month: month, daysWithData: cur.count, lines: lines, workouts: ws.count,
                      workoutMinutes: ws.reduce(0) { $0 + Double($1.end - $1.start) / 60 }, topSports: Array(top),
                      bestDay: scored.max { $0.recovery! < $1.recovery! }?.day, worstDay: scored.min { $0.recovery! < $1.recovery! }?.day,
                      greenDays: scored.filter { $0.recovery! >= 67 }.count, redDays: scored.filter { $0.recovery! < 34 }.count)
    }

    public static func shiftMonth(_ month: String, _ by: Int) -> String {
        let parts = month.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return month }
        let idx = parts[0] * 12 + (parts[1] - 1) + by
        return String(format: "%04d-%02d", idx / 12, idx % 12 + 1)
    }
}
