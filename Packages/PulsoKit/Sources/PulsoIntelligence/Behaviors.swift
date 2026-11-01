import Foundation
import PulsoStore
import PulsoAnalytics

/// «Información sobre comportamientos»: how each behaviour moves your recovery, as a % of the recovery you get
/// without it. Two kinds:
/// - automatic ones Pulso detects from your own data (good sleep, regular schedule, early/late training, high stress,
///   a hard day), split at your own median so both groups fill up;
/// - the journal questions you answer.
/// Each one unlocks with at least `minEach` days with it and `minEach` without. Association, not causation.
public enum Behaviors {
    public static let minEach = 5

    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var label: String
        public var automatic: Bool
        public var yes: Int
        public var no: Int
        /// (mean recovery with − without) / without × 100. Nil until unlocked.
        public var impactPct: Double?
        /// Mean recovery with / without (points), for the detail.
        public var withMean: Double?
        public var withoutMean: Double?

        public var unlocked: Bool { yes >= Behaviors.minEach && no >= Behaviors.minEach && impactPct != nil }
        /// Within ±2 % it is not telling anything.
        public var helps: Bool? {
            guard let p = impactPct, abs(p) >= 2 else { return nil }
            return p > 0
        }
    }

    public struct Report: Equatable, Sendable {
        /// Unlocked, sorted from what helps most to what hurts most.
        public var impact: [Item]
        /// Still collecting days, the closest to unlocking first.
        public var locked: [Item]
    }

    /// `label` names journal keys. Journal answers and daytime behaviours act on the next day's recovery;
    /// sleep behaviours act on the same day's.
    public static func analyze(days: [DaySummary], workouts: [Workout], journal: [JournalEntry],
                               label: (String) -> String, calendar: Calendar = .current) -> Report {
        let sorted = days.sorted { $0.day < $1.day }
        let byDay = Dictionary(sorted.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        var items: [Item] = []

        func item(_ key: String, _ label: String, automatic: Bool, lag: Int, flags: [String: Bool]) -> Item {
            var with: [Double] = [], without: [Double] = []
            for (day, on) in flags {
                guard let r = byDay[DayKey.shift(day, days: lag, calendar: calendar)]?.recovery else { continue }
                if on { with.append(r) } else { without.append(r) }
            }
            var it = Item(key: key, label: label, automatic: automatic, yes: with.count, no: without.count)
            if with.count >= minEach, without.count >= minEach, let a = Stats.mean(with), let b = Stats.mean(without), b > 0 {
                it.impactPct = (a - b) / b * 100
                it.withMean = a
                it.withoutMean = b
            }
            return it
        }

        // Sleep score at or above your usual.
        let perf = sorted.compactMap { $0.sleepPerformance.map { $0 * 100 } }
        if let med = Stats.median(perf) {
            let t = Int(med.rounded())
            var f: [String: Bool] = [:]
            for d in sorted { if let p = d.sleepPerformance { f[d.day] = p * 100 >= Double(t) } }
            items.append(item("auto.sleepScore", "\(t) %+ calificación del sueño", automatic: true, lag: 0, flags: f))
        }

        // Consistent wake / bed time: within 30 min of your median of the previous 14 nights.
        func clockMinutes(_ ts: Int) -> Double {
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            var m = Double((c.hour ?? 0) * 60 + (c.minute ?? 0))
            if m < 12 * 60 { m += 24 * 60 } // bedtimes after midnight stay after the evening ones
            return m
        }
        func consistency(_ pick: (DaySummary) -> Int?, wrapEvening: Bool) -> [String: Bool] {
            var f: [String: Bool] = [:]
            for (i, d) in sorted.enumerated() {
                guard let ts = pick(d) else { continue }
                let prev = sorted[max(0, i - 14)..<i].compactMap(pick)
                guard prev.count >= 5 else { continue }
                let v = wrapEvening ? clockMinutes(ts) : clockMinutes(ts).truncatingRemainder(dividingBy: 24 * 60)
                let ref = prev.map { wrapEvening ? clockMinutes($0) : clockMinutes($0).truncatingRemainder(dividingBy: 24 * 60) }
                if let m = Stats.median(ref) { f[d.day] = abs(v - m) <= 30 }
            }
            return f
        }
        items.append(item("auto.wakeConsistent", "Hora de despertar constante", automatic: true, lag: 0,
                          flags: consistency({ $0.sleepEnd }, wrapEvening: false)))
        items.append(item("auto.bedConsistent", "Hora de dormir constante", automatic: true, lag: 0,
                          flags: consistency({ $0.sleepStart }, wrapEvening: true)))

        // Training early (starts before 12:00) / late (starts from 19:00), against every other day.
        let measured = Set(sorted.filter { $0.recovery != nil || $0.strain != nil }.map(\.day))
        var early: [String: Bool] = [:], late: [String: Bool] = [:]
        for day in measured { early[day] = false; late[day] = false }
        for w in workouts where w.source != .auto || w.strain >= 4 {
            let day = DayKey.string(ts: w.start, calendar: calendar)
            guard measured.contains(day) else { continue }
            let h = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(w.start)))
            if h < 12 { early[day] = true }
            if h >= 19 { late[day] = true }
        }
        items.append(item("auto.earlyWorkout", "Entrenamiento temprano", automatic: true, lag: 1, flags: early))
        items.append(item("auto.lateWorkout", "Entrenamiento tardío", automatic: true, lag: 1, flags: late))

        // Share of the worn day in high stress at or above your usual.
        let stressPct: [(String, Double)] = sorted.compactMap { d in
            guard let m = d.stressHighMinutes, d.wornMinutes >= 600 else { return nil }
            return (d.day, m / d.wornMinutes * 100)
        }
        if let med = Stats.median(stressPct.map(\.1)), med > 0 {
            let t = max(1, Int(med.rounded()))
            var f: [String: Bool] = [:]
            for (day, p) in stressPct { f[day] = p >= Double(t) }
            items.append(item("auto.highStress", "\(t) %+ del día en estrés alto", automatic: true, lag: 1, flags: f))
        }

        // A demanding day: strain at or above your usual.
        let strains = sorted.compactMap(\.strain)
        if let med = Stats.median(strains) {
            let t = max(1, Int(med.rounded()))
            var f: [String: Bool] = [:]
            for d in sorted { if let s = d.strain { f[d.day] = s >= Double(t) } }
            items.append(item("auto.strain", "\(t)+ de esfuerzo", automatic: true, lag: 1, flags: f))
        }

        // Journal: explicit answers; on a day logged in Pulso every unticked habit counts as «no».
        let entriesByDay = Dictionary(grouping: journal, by: \.day)
        let importedDays = Set(entriesByDay.filter { _, e in e.contains { $0.value == 0 || $0.key.hasPrefix("whoop:") } }.keys)
        let pulsoDays = Set(entriesByDay.keys).subtracting(importedDays)
        let keys = Set(journal.map(\.key))
        for key in keys.sorted() {
            let explicit = key.hasPrefix("whoop:") || !JournalCatalog.items.contains { $0.key == key }
            let asked = Set(journal.filter { $0.key == key }.map(\.day))
            let answered = explicit ? asked : asked.union(pulsoDays)
            var f: [String: Bool] = [:]
            for day in answered { f[day] = journal.contains { $0.day == day && $0.key == key && $0.value > 0 } }
            items.append(item(key, label(key), automatic: false, lag: 1, flags: f))
        }

        let impact = items.filter(\.unlocked).sorted { ($0.impactPct ?? 0) > ($1.impactPct ?? 0) }
        let locked = items.filter { !$0.unlocked }.sorted {
            let a = min($0.yes, minEach) + min($0.no, minEach), b = min($1.yes, minEach) + min($1.no, minEach)
            return a != b ? a > b : $0.label < $1.label
        }
        return Report(impact: impact, locked: locked)
    }
}
