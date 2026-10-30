import Foundation
import PulsoStore

/// Whether last night is still missing from the cycle on screen. The open cycle stays yesterday's until a
/// main sleep is found (as in WHOOP), so after the usual wake-up time Inicio would keep showing yesterday's
/// recovery as if it were today's. This tells the UI to say so instead.
public enum NightStatus: Equatable, Sendable {
    /// Today's cycle exists, or it is still too early to expect it.
    case ok
    /// The strap data stops before the usual wake-up: last night hasn't been downloaded yet.
    case awaitingData
    /// The data covers the morning but no main sleep was found in it.
    case notDetected

    /// Minutes after the usual wake-up before a missing night is reported.
    public static let grace = 45
    /// Minutes of data past the usual wake-up needed to say the night is really not there.
    public static let coverage = 60

    public static func evaluate(now: Date, currentCycleDay: String, recentCycleStarts: [Int],
                                lastSampleTs: Int?, calendar: Calendar = .current) -> NightStatus {
        let today = DayKey.string(now, calendar: calendar)
        guard currentCycleDay < today else { return .ok }
        let wakeMinutes = recentCycleStarts.suffix(14).map { ts -> Int in
            let c = calendar.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
            return (c.hour ?? 0) * 60 + (c.minute ?? 0)
        }.filter { $0 < 16 * 60 }.sorted()
        let usualWake = wakeMinutes.isEmpty ? 8 * 60 : wakeMinutes[wakeMinutes.count / 2]
        let startOfToday = calendar.startOfDay(for: now)
        let expected = startOfToday.addingTimeInterval(TimeInterval((usualWake + grace) * 60))
        guard now >= expected else { return .ok }
        let covered = startOfToday.addingTimeInterval(TimeInterval((usualWake + coverage) * 60))
        guard let last = lastSampleTs, last >= Int(covered.timeIntervalSince1970) else { return .awaitingData }
        return .notDetected
    }
}
