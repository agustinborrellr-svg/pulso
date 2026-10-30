import Foundation
import PulsoStore
import PulsoAnalytics

/// Personal association between logged habits and what happens next, with uncertainty.
/// Association, not causation: days with a habit can differ in other ways too.
public enum HabitImpact {
    public static let version = "1.1"
    public static let fdr = 0.10

    public struct Item: Equatable, Sendable, Identifiable {
        public var id: String { key }
        public var key: String
        public var label: String
        public var withCount: Int
        public var withoutCount: Int
        /// Mean next-day recovery with − without (points) and its 90 % interval (Welch).
        public var recoveryDelta: Double
        public var interval: ClosedRange<Double>
        public var hrvDeltaPct: Double?
        /// Mean adverse deviation (σ) of the next night, with − without.
        public var deviationDelta: Double?
        /// Median nights until the deviation is back under 1 σ after a night with the habit.
        public var nightsToNormal: Double?
        /// Welch two-sided p-value, and its Benjamini–Hochberg q-value across every habit compared.
        public var pValue: Double = 1
        public var qValue: Double = 1

        public var n: Int { withCount + withoutCount }
        public var intervalExcludesZero: Bool { interval.lowerBound > 0 || interval.upperBound < 0 }
        /// Clear only if it survives the multiple-comparisons correction too (FDR 10 %).
        public var isClear: Bool { intervalExcludesZero && qValue < HabitImpact.fdr }
        public var confidence: MetricResult.Confidence { .from(samples: min(withCount, withoutCount), medium: 8, high: 15) }

        public var summary: String {
            guard isClear else {
                let why = intervalExcludesZero ? "no supera la corrección por comparaciones múltiples" : "el intervalo incluye 0"
                return "\(label): sin efecto claro todavía (\(withCount) días con, \(withoutCount) sin; \(why))."
            }
            var s = String(format: "%@ se asocia a %+.0f puntos de recuperación al día siguiente (IC 90 %% %+.0f a %+.0f; %d días con, %d sin)", locale: Num.spanish,
                           label, recoveryDelta, interval.lowerBound, interval.upperBound, withCount, withoutCount)
            if let h = hrvDeltaPct, abs(h) >= 3 { s += String(format: ", VFC %+.0f %%", locale: Num.spanish, h) }
            if let n = nightsToNormal, n > 1.2 { s += String(format: "; tardas %.1f noches en normalizarte", locale: Num.spanish, n) }
            return s + "."
        }
    }

    static func welch(_ a: [Double], _ b: [Double]) -> (delta: Double, ci: ClosedRange<Double>, p: Double)? {
        guard a.count >= 2, b.count >= 2, let ma = Num.mean(a), let mb = Num.mean(b), let sa = Num.sd(a), let sb = Num.sd(b) else { return nil }
        let va = sa * sa / Double(a.count), vb = sb * sb / Double(b.count)
        let se = (va + vb).squareRoot()
        let df = se > 0 ? pow(va + vb, 2) / (va * va / Double(a.count - 1) + vb * vb / Double(b.count - 1)) : 1
        let half = Num.tCritical(df: max(1, Int(df)), level: 0.9) * se
        let d = ma - mb
        let p = se > 0 ? Num.tTwoSidedP(d / se, df: df) : (d == 0 ? 1 : 0)
        return (d, (d - half)...(d + half), p)
    }

    /// `minEach` days with and without the habit are required.
    public static func analyze(journal: [JournalEntry], days: [DaySummary], deviation: [Deviation.Point], minEach: Int = 4) -> [Item] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let dev = Dictionary(deviation.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        // Pulso stores only "yes" (unticking deletes), so on a day logged in Pulso every absent habit is a "no".
        // An imported day only asked its own questions: it leaves explicit 0s or questions Pulso doesn't have,
        // and a Pulso habit it never asked about is unknown there, not "no".
        let byDayEntries = Dictionary(grouping: journal, by: \.day)
        let importedDays = Set(byDayEntries.filter { _, e in e.contains { $0.value == 0 || $0.key.hasPrefix("whoop:") } }.keys)
        let pulsoDays = Set(byDayEntries.keys).subtracting(importedDays)
        var out: [Item] = []
        // Pulso's own habits, plus any other question answered in the journal (e.g. imported from WHOOP):
        // for those, "without" means an explicit "no", not just a day it wasn't asked.
        let catalog = JournalCatalog.items.map { (key: $0.key, label: $0.label, explicit: false) }
        let known = Set(catalog.map(\.key))
        let others = Set(journal.map(\.key)).subtracting(known).sorted().map {
            (key: $0, label: $0.replacingOccurrences(of: "whoop:", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "¿? ")), explicit: true)
        }
        for item in catalog + others {
            var yes: [String] = [], no: [String] = []
            let asked = Set(journal.filter { $0.key == item.key }.map(\.day))
            let answered = item.explicit ? asked : asked.union(pulsoDays)
            for day in answered {
                guard byDay[LoadResponse.shift(day, 1)]?.recovery != nil else { continue }
                let on = journal.contains { $0.day == day && $0.key == item.key && $0.value > 0 }
                if on { yes.append(day) } else { no.append(day) }
            }
            guard yes.count >= minEach, no.count >= minEach else { continue }
            let next = { (d: String) in byDay[LoadResponse.shift(d, 1)] }
            guard let w = welch(yes.compactMap { next($0)?.recovery }, no.compactMap { next($0)?.recovery }) else { continue }
            var hrv: Double?
            if let hy = Num.mean(yes.compactMap { next($0)?.hrv }), let hn = Num.mean(no.compactMap { next($0)?.hrv }), hn > 0 {
                hrv = (hy / hn - 1) * 100
            }
            var devDelta: Double?
            let dy = yes.compactMap { dev[LoadResponse.shift($0, 1)]?.strain }, dn = no.compactMap { dev[LoadResponse.shift($0, 1)]?.strain }
            if let a = Num.mean(dy), let b = Num.mean(dn), dy.count >= 2, dn.count >= 2 { devDelta = a - b }
            // Nights until back in range after a habit night.
            let back = yes.compactMap { d -> Double? in
                for n in 1...4 {
                    guard let p = dev[LoadResponse.shift(d, n)] else { return nil }
                    if p.strain <= LoadResponse.threshold { return Double(n) }
                }
                return 5
            }
            out.append(Item(key: item.key, label: item.label, withCount: yes.count, withoutCount: no.count, recoveryDelta: w.delta,
                            interval: w.ci, hrvDeltaPct: hrv, deviationDelta: devDelta, nightsToNormal: Num.median(back), pValue: w.p))
        }
        let q = Num.benjaminiHochberg(out.map(\.pValue))
        for i in out.indices { out[i].qValue = q[i] }
        return out.sorted { ($0.isClear ? 1 : 0, abs($0.recoveryDelta)) > ($1.isClear ? 1 : 0, abs($1.recoveryDelta)) }
    }
}
