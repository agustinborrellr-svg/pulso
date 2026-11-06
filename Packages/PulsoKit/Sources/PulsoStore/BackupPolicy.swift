import Foundation

/// Automatic copies kept in Documents/Copias de seguridad (visible in the Files app). The per-second data is
/// most of the size (~7 MB a day), so it is kept once instead of in every copy:
/// - a light copy every day (everything except the per-second data), the last `keepDaily` kept;
/// - an archive per closed calendar month with that month's per-second data, written once and never rotated
///   (rewritten only if the month later gets more seconds);
/// - a weekly copy with everything but only the current month's seconds, the last `keepWeekly` kept;
/// - a safety copy before anything that replaces or deletes data, the last `keepSafety` kept whatever they
///   hold (a full one is never dropped early: it may hold settings, journal or imports nothing else has).
/// Light copies go into the iPhone's own iCloud/computer backup; the big files don't (the live database,
/// which has every second, already does).
public enum BackupPolicy {
    public enum Kind: String, CaseIterable, Sendable {
        case daily = "diaria", weekly = "semanal", safety = "antes-de", archive = "segundos"
    }

    /// What a copy holds, written at the end of a safety copy's tag ("antes-de-borrar-completa").
    public enum Content: String, CaseIterable, Sendable {
        /// Everything except the per-second data.
        case light = "ligera"
        /// Everything plus the current month's per-second data (older months are in the archives).
        case month = "mes"
        /// Everything.
        case full = "completa"
    }

    public static let keepDaily = 14
    public static let keepWeekly = 2
    public static let keepSafety = 5
    public static let folderName = "Copias de seguridad"
    /// Weekly full copies written before the monthly archives existed: still listed, restorable and rotated
    /// with the new weekly copies.
    static let legacyWeeklyTag = "semanal-completa"

    public struct Copy: Equatable, Sendable {
        public let name: String
        public let kind: Kind
        public let date: Date
        /// nil for a month archive (it only holds per-second data).
        public var content: Content?
        /// "2026-10" for a month archive.
        public var month: String?
    }

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }

    /// "Pulso-diaria-2026-10-27_081500.sqlite", "Pulso-semanal-…", "Pulso-antes-de-borrar-completa-…".
    /// A safety copy says what it holds; daily copies are always light and weekly ones always `.month`.
    public static func fileName(_ kind: Kind, reason: String? = nil, content: Content = .full, at date: Date) -> String {
        let tag: String
        switch kind {
        case .safety: tag = "antes-de-\(reason ?? "cambiar")-\(content.rawValue)"
        case .archive: return archiveName(month: monthKey(date, calendar: Calendar(identifier: .gregorian)))
        default: tag = kind.rawValue
        }
        return "Pulso-\(tag)-\(formatter().string(from: date)).sqlite"
    }

    /// "Pulso-segundos-2026-10.sqlite": one per month, never rotated.
    public static func archiveName(month: String) -> String { "Pulso-segundos-\(month).sqlite" }

    /// A copy still being written (`PulsoDatabase.temporaryPath`) or left half-written by a crash: hidden,
    /// never listed, restored or counted as a copy.
    public static func isUnfinished(_ name: String) -> Bool {
        name.hasPrefix(".Pulso-") && name.contains(".sqlite.tmp")
    }

    public static func parse(_ name: String) -> Copy? {
        guard name.hasPrefix("Pulso-"), name.hasSuffix(".sqlite") else { return nil }
        let core = String(name.dropFirst("Pulso-".count).dropLast(".sqlite".count))
        let archivePrefix = Kind.archive.rawValue + "-"
        if core.hasPrefix(archivePrefix) {
            let month = String(core.dropFirst(archivePrefix.count))
            guard let range = monthRange(month, calendar: utcCalendar) else { return nil }
            return Copy(name: name, kind: .archive, date: Date(timeIntervalSince1970: TimeInterval(range.from)), content: nil, month: month)
        }
        guard core.count > 18, let date = formatter().date(from: String(core.suffix(17))) else { return nil }
        let tag = String(core.dropLast(18))
        if tag == Kind.daily.rawValue { return Copy(name: name, kind: .daily, date: date, content: .light) }
        if tag == Kind.weekly.rawValue { return Copy(name: name, kind: .weekly, date: date, content: .month) }
        if tag == legacyWeeklyTag { return Copy(name: name, kind: .weekly, date: date, content: .full) }
        if tag.hasPrefix(Kind.safety.rawValue) {
            // Safety copies written before the archives existed carry no content tag: they were all full.
            let content = Content.allCases.first { tag.hasSuffix("-" + $0.rawValue) } ?? .full
            return Copy(name: name, kind: .safety, date: date, content: content)
        }
        return nil
    }

    /// Kept out of the iPhone's iCloud/computer backup: everything bigger than a light copy. The live database
    /// is in that backup with every second, so nothing is lost if the phone is.
    public static func excludedFromDeviceBackup(_ copy: Copy) -> Bool {
        copy.content != .light
    }

    public struct Plan: Equatable, Sendable {
        public var makeDaily: Bool
        public var makeWeekly: Bool
        public var delete: [String]
    }

    /// What to do now given the files in the folder. Unknown files (the user's own) and month archives are
    /// never touched.
    public static func plan(existing names: [String], now: Date) -> Plan {
        let copies = names.compactMap(parse)
        func latest(_ k: Kind) -> Date? { copies.filter { $0.kind == k }.map(\.date).max() }
        let makeDaily = latest(.daily).map { now.timeIntervalSince($0) >= 20 * 3600 } ?? true
        let makeWeekly = latest(.weekly).map { now.timeIntervalSince($0) >= 6.5 * 86400 } ?? true
        var delete: [String] = []
        // Counting the copy about to be made, so the folder never holds more than the limit.
        for (kind, keep, adding) in [(Kind.daily, keepDaily, makeDaily), (.weekly, keepWeekly, makeWeekly), (.safety, keepSafety, false)] {
            let sorted = copies.filter { $0.kind == kind }.sorted { $0.date > $1.date }
            let room = max(keep - (adding ? 1 : 0), 1)
            delete += sorted.dropFirst(room).map(\.name)
        }
        return Plan(makeDaily: makeDaily, makeWeekly: makeWeekly, delete: delete)
    }

    // MARK: - Calendar months (month archives, weekly copies)

    private static var utcCalendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    /// "2026-10" for `date` in `calendar`'s time zone.
    public static func monthKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    /// [first second of the month, first second of the next one) in `calendar`'s time zone, as unix seconds.
    /// Calendar arithmetic, so a month that starts or ends on a daylight-saving change is still exact.
    public static func monthRange(_ key: String, calendar: Calendar) -> (from: Int, to: Int)? {
        let parts = key.split(separator: "-")
        guard key.count == 7, parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m), y >= 2000,
              let start = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return (Int(start.timeIntervalSince1970), Int(end.timeIntervalSince1970))
    }

    /// First second of the month `date` is in.
    public static func monthStart(_ date: Date, calendar: Calendar) -> Int {
        monthRange(monthKey(date, calendar: calendar), calendar: calendar)?.from ?? Int(date.timeIntervalSince1970)
    }

    /// Calendar months already over at `now`, oldest first, from the one holding `firstSecond`.
    public static func closedMonths(firstSecond: Int, now: Date, calendar: Calendar) -> [String] {
        let current = monthKey(now, calendar: calendar)
        var key = monthKey(Date(timeIntervalSince1970: TimeInterval(firstSecond)), calendar: calendar)
        var out: [String] = []
        while key < current, let range = monthRange(key, calendar: calendar) {
            out.append(key)
            key = monthKey(Date(timeIntervalSince1970: TimeInterval(range.to)), calendar: calendar)
        }
        return out
    }
}
