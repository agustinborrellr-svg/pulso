import Foundation
import PulsoStore
import PulsoAnalytics

enum HRPeriod: String, CaseIterable, Identifiable {
    case hour, twoHours, day, week, month
    var id: String { rawValue }

    var label: String {
        switch self {
        case .hour: return "1 h"
        case .twoHours: return "2 h"
        case .day: return "24 h"
        case .week: return "Semana"
        case .month: return "Mes"
        }
    }

    var seconds: Int {
        switch self {
        case .hour: return 3600
        case .twoHours: return 7200
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        }
    }

    /// Bin width: about 60–180 points per chart.
    var binWidth: Int {
        switch self {
        case .hour, .twoHours: return 60
        case .day: return 600
        case .week: return 3600
        case .month: return 4 * 3600
        }
    }
}

/// The newest strap second with an activity class or a sleep flag.
struct ActivityReading {
    var ts: Int
    var activity: Int?
    var sleepState: Int?
    var off: Bool
}

/// Physiological monitor: heart-rate history and the newest reading of each metric.
extension AppModel {
    /// Strap history and the live stream binned for `period`, read off the main thread. Long periods are read
    /// in 6-hour slices so the shared database lock never blocks live inserts for long.
    func hrHistory(_ period: HRPeriod, now: Date = Date()) async -> HRHistory.Series {
        let db = self.db
        let to = Int(now.timeIntervalSince1970) + 1
        let from = to - period.seconds
        let width = period.binWidth
        let offset = TimeZone.current.secondsFromGMT(for: now)
        return await Task.detached(priority: .userInitiated) {
            func query(_ table: String, _ a: Int, _ b: Int) -> [HRHistory.Bin] {
                let extra = table == "samples" ? " AND off = 0" : ""
                let sql = """
                SELECT ((ts + ?) / ?) * ? - ?, COUNT(hr), SUM(hr), MIN(hr), MAX(hr) FROM \(table)
                WHERE ts >= ? AND ts < ? AND hr > 25 AND hr < 240\(extra) GROUP BY (ts + ?) / ?
                """
                let p: [SQLValue] = [.int(Int64(offset)), .int(Int64(width)), .int(Int64(width)), .int(Int64(offset)),
                                     .int(Int64(a)), .int(Int64(b)), .int(Int64(offset)), .int(Int64(width))]
                return (try? db.sql.query(sql, p) { r in
                    HRHistory.Bin(start: Int(r.int(0) ?? 0), seconds: Int(r.int(1) ?? 0), sum: r.double(2) ?? 0,
                                  min: Int(r.int(3) ?? 0), max: Int(r.int(4) ?? 0))
                }) ?? []
            }
            let slice = 6 * 3600
            var strap: [HRHistory.Bin] = [], live: [HRHistory.Bin] = []
            var a = HRHistory.binStart(from, width: width, offset: offset)
            while a < to {
                let b = min(to, a + slice)
                strap += query("samples", a, b)
                live += query("live_hr", a, b)
                a = b
            }
            // Slices may cut a bin in two: join the halves of each source before choosing between sources.
            let merged = HRHistory.merge(HRHistory.rebin(strap, width: width, offset: offset),
                                         HRHistory.rebin(live, width: width, offset: offset))
            return HRHistory.series(merged, from: from, to: to, width: width)
        }.value
    }

    /// Newest activity reading from the strap history of the last 12 hours.
    func latestActivity() async -> ActivityReading? {
        let db = self.db
        let since = Int(Date().timeIntervalSince1970) - 12 * 3600
        return await Task.detached(priority: .utility) {
            (try? db.sql.query("""
            SELECT ts, act, sstate, off FROM samples WHERE ts >= ? AND (act IS NOT NULL OR sstate IS NOT NULL OR off = 1)
            ORDER BY ts DESC LIMIT 1
            """, [.int(Int64(since))]) { r in
                ActivityReading(ts: Int(r.int(0) ?? 0), activity: r.int(1).map { Int($0) },
                                sleepState: r.int(2).map { Int($0) }, off: (r.int(3) ?? 0) != 0)
            })?.first
        }.value
    }

    /// The newest day (cycle in progress first) that has a value for `key`.
    func latestDay(with key: KeyPath<DaySummary, Double?>) -> (value: Double, day: DaySummary)? {
        let current = currentDayKey
        for d in days.reversed() where d.day <= current {
            if let v = d[keyPath: key] { return (v, d) }
        }
        return nil
    }

    var latestScan: LiveTestRecord? { liveTests.last { $0.kind == .scan } }
}
