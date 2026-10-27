import Foundation

/// Automatic copies kept in Documents/Copias de seguridad (visible in the Files app and included in the
/// iPhone's own iCloud/computer backup):
/// - a light copy every day (everything except the per-second data), the last `keepDaily` kept;
/// - a full copy every week, the last `keepWeekly` kept;
/// - a safety copy before anything that replaces or deletes data, the last `keepSafety` kept.
public enum BackupPolicy {
    public enum Kind: String, CaseIterable, Sendable {
        case daily = "diaria", weekly = "semanal-completa", safety = "antes-de"
    }

    public static let keepDaily = 14
    public static let keepWeekly = 3
    public static let keepSafety = 5
    public static let folderName = "Copias de seguridad"

    public struct Copy: Equatable, Sendable {
        public let name: String
        public let kind: Kind
        public let date: Date
    }

    private static func formatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f
    }

    /// "Pulso-diaria-2026-10-27_081500.sqlite", "Pulso-antes-de-borrar-2026-10-27_081500.sqlite"…
    public static func fileName(_ kind: Kind, reason: String? = nil, at date: Date) -> String {
        let tag = kind == .safety ? "antes-de-\(reason ?? "cambiar")" : kind.rawValue
        return "Pulso-\(tag)-\(formatter().string(from: date)).sqlite"
    }

    public static func parse(_ name: String) -> Copy? {
        guard name.hasPrefix("Pulso-"), name.hasSuffix(".sqlite") else { return nil }
        let core = name.dropFirst("Pulso-".count).dropLast(".sqlite".count)
        guard core.count > 18, let date = formatter().date(from: String(core.suffix(17))) else { return nil }
        let tag = core.dropLast(18)
        let kind: Kind
        if tag == Kind.daily.rawValue { kind = .daily }
        else if tag == Kind.weekly.rawValue { kind = .weekly }
        else if tag.hasPrefix(Kind.safety.rawValue) { kind = .safety }
        else { return nil }
        return Copy(name: name, kind: kind, date: date)
    }

    public struct Plan: Equatable, Sendable {
        public var makeDaily: Bool
        public var makeWeekly: Bool
        public var delete: [String]
    }

    /// What to do now given the files in the folder. Unknown files (the user's own) are never touched.
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
}
