import Foundation
import PulsoStore

/// Journal behaviours and their measured association with the next morning's recovery / HRV.
public enum JournalCatalog {
    public struct Item: Identifiable, Equatable {
        public var id: String { key }
        public let key: String
        public let label: String
        public let icon: String
    }

    public static let items: [Item] = [
        Item(key: "alcohol", label: "Alcohol", icon: "wineglass"),
        Item(key: "late_caffeine", label: "Cafeína después de las 14 h", icon: "cup.and.saucer"),
        Item(key: "late_meal", label: "Cena tarde / copiosa", icon: "fork.knife"),
        Item(key: "screens_bed", label: "Pantallas en la cama", icon: "iphone"),
        Item(key: "high_stress", label: "Día estresante", icon: "exclamationmark.triangle"),
        Item(key: "hard_training", label: "Entreno duro", icon: "figure.strengthtraining.traditional"),
        Item(key: "meditation", label: "Meditación / respiración", icon: "wind"),
        Item(key: "reading", label: "Lectura antes de dormir", icon: "book"),
        Item(key: "sick", label: "Me sentía enfermo", icon: "thermometer"),
        Item(key: "travel", label: "Viaje", icon: "airplane"),
        Item(key: "magnesium", label: "Magnesio", icon: "pills"),
        Item(key: "sauna", label: "Sauna / baño caliente", icon: "flame"),
        Item(key: "sunlight", label: "Luz solar por la mañana", icon: "sun.max"),
        Item(key: "shared_bed", label: "Cama compartida", icon: "bed.double"),
    ]

    public static func label(_ key: String) -> String {
        items.first { $0.key == key }?.label ?? key
    }
}

public struct Insight: Equatable, Identifiable {
    public var id: String { key }
    public var key: String
    public var label: String
    public var yesCount: Int
    public var noCount: Int
    /// Mean next-day recovery with vs without the behaviour (percentage points).
    public var recoveryDelta: Double
    public var hrvDeltaPercent: Double?
}

public enum Insights {
    /// A journal entry on day D describes that day's behaviour; its effect shows up in the recovery of D+1.
    public static func compute(journal: [JournalEntry], days: [DaySummary], minEach: Int = 5,
                               calendar: Calendar = .current) -> [Insight] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let loggedDays = Set(journal.map { $0.day })
        var out: [Insight] = []
        for item in JournalCatalog.items {
            var yes: [DaySummary] = [], no: [DaySummary] = []
            for day in loggedDays {
                guard let next = byDay[DayKey.shift(day, days: 1, calendar: calendar)], next.recovery != nil else { continue }
                let v = journal.first { $0.day == day && $0.key == item.key }?.value ?? 0
                if v > 0 { yes.append(next) } else { no.append(next) }
            }
            guard yes.count >= minEach, no.count >= minEach,
                  let ry = Stats.mean(yes.compactMap { $0.recovery }),
                  let rn = Stats.mean(no.compactMap { $0.recovery }) else { continue }
            var hrvDelta: Double?
            if let hy = Stats.mean(yes.compactMap { $0.hrv }), let hn = Stats.mean(no.compactMap { $0.hrv }), hn > 0 {
                hrvDelta = (hy - hn) / hn * 100
            }
            out.append(Insight(key: item.key, label: item.label, yesCount: yes.count, noCount: no.count,
                               recoveryDelta: ry - rn, hrvDeltaPercent: hrvDelta))
        }
        return out.sorted { abs($0.recoveryDelta) > abs($1.recoveryDelta) }
    }
}
