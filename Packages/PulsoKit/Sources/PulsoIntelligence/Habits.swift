import Foundation
import PulsoStore
import PulsoAnalytics

/// Personal association between logged habits and what happens next, with uncertainty.
/// Association, not causation: days with a habit can differ in other ways too.
public enum HabitImpact {
    public static let version = "1.0"

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

        /// The interval excludes zero.
        public var isClear: Bool { interval.lowerBound > 0 || interval.upperBound < 0 }

        public var summary: String {
            guard isClear else {
                return "\(label): sin efecto claro todavía (\(withCount) días con, \(withoutCount) sin)."
            }
            var s = String(format: "%@: %+.0f puntos de recuperación al día siguiente (entre %+.0f y %+.0f)", label, recoveryDelta,
                           interval.lowerBound, interval.upperBound)
            if let h = hrvDeltaPct, abs(h) >= 3 { s += String(format: ", VFC %+.0f %%", h) }
            if let n = nightsToNormal, n > 1.2 { s += String(format: "; tardas %.1f noches en normalizarte", n) }
            return s + "."
        }
    }

    static func welch(_ a: [Double], _ b: [Double]) -> (delta: Double, ci: ClosedRange<Double>)? {
        guard a.count >= 2, b.count >= 2, let ma = Num.mean(a), let mb = Num.mean(b), let sa = Num.sd(a), let sb = Num.sd(b) else { return nil }
        let va = sa * sa / Double(a.count), vb = sb * sb / Double(b.count)
        let se = (va + vb).squareRoot()
        let df = se > 0 ? pow(va + vb, 2) / (va * va / Double(a.count - 1) + vb * vb / Double(b.count - 1)) : 1
        let half = Num.tCritical(df: max(1, Int(df)), level: 0.9) * se
        let d = ma - mb
        return (d, (d - half)...(d + half))
    }

    /// `minEach` days with and without the habit are required.
    public static func analyze(journal: [JournalEntry], days: [DaySummary], deviation: [Deviation.Point], minEach: Int = 4) -> [Item] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let dev = Dictionary(deviation.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let logged = Set(journal.map { $0.day })
        var out: [Item] = []
        for item in JournalCatalog.items {
            var yes: [String] = [], no: [String] = []
            for day in logged {
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
                            interval: w.ci, hrvDeltaPct: hrv, deviationDelta: devDelta, nightsToNormal: Num.median(back)))
        }
        return out.sorted { ($0.isClear ? 1 : 0, abs($0.recoveryDelta)) > ($1.isClear ? 1 : 0, abs($1.recoveryDelta)) }
    }
}
