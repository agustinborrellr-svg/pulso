import Foundation

/// Per-second counts of a stretch of data, to tell cheaply whether a month archive lacks rows or values the
/// live database got later (the strap offloading old data late, a restore bringing seconds back…).
public struct SecondsCount: Codable, Equatable, Sendable {
    public var rows = 0, hr = 0, rr = 0, motion = 0, temp = 0, spo2 = 0, steps = 0, live = 0
    public var last: Int?

    public init() {}

    /// True if these counts (the live database) show rows or values `archived` lacks. Fewer rows (seconds a
    /// retention limit pruned from the live database) never count: the archive keeps them.
    public func hasMoreThan(_ archived: SecondsCount) -> Bool {
        rows > archived.rows || hr > archived.hr || rr > archived.rr || motion > archived.motion || temp > archived.temp
            || spo2 > archived.spo2 || steps > archived.steps || live > archived.live || (last ?? .min) > (archived.last ?? .min)
    }
}

/// Written inside every month archive (kv "archive.month"): which month, the exact boundaries it was cut
/// with, and what it holds.
public struct MonthArchiveInfo: Codable, Equatable, Sendable {
    public var month: String
    public var from: Int
    public var to: Int
    public var counts: SecondsCount
    public var written: Int
}

extension PulsoDatabase {
    static let archiveInfoKey = "archive.month"
    private static let archiveLock = NSLock()
    public static let archiveTimeZoneKey = "backup.archiveTimeZone"
    static let secondsTables: Set<String> = ["samples", "live_hr"]
    static let sampleValueColumns = ["hr", "rr", "gx", "gy", "gz", "dyn", "temp", "spo2", "steps", "act", "sstate", "quality"]

    /// Calendar month archives and weekly copies are cut with: the local time zone of the first time it is
    /// asked (kept in kv), so travelling never moves a month's boundaries and leaves seconds between two
    /// archives.
    public func archiveCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        let id = get(String.self, for: Self.archiveTimeZoneKey) ?? {
            let id = TimeZone.current.identifier
            try? set(id, for: Self.archiveTimeZoneKey)
            return id
        }()
        cal.timeZone = TimeZone(identifier: id) ?? .current
        return cal
    }

    // MARK: - Partial copies

    enum Slice {
        /// Everything except the per-second data.
        case light
        /// Everything, with per-second data only from this second on.
        case since(Int)
        /// Only the per-second data in [from, to) (every table exists, the others empty).
        case seconds(from: Int, to: Int)

        /// WHERE clause for `table`'s rows ("" = all of them), nil to leave the table empty.
        func filter(_ table: String) -> String? {
            let isSeconds = PulsoDatabase.secondsTables.contains(table)
            switch self {
            case .light: return isSeconds ? nil : ""
            case .since(let t): return isSeconds ? "WHERE ts >= \(t)" : ""
            case .seconds(let a, let b):
                if isSeconds { return "WHERE ts >= \(a) AND ts < \(b)" }
                return table == "undecoded_records" ? "WHERE received >= \(a) AND received < \(b)" : nil
            }
        }
    }

    /// Everything plus only the per-second data from `since` on: the weekly copy and the one taken before a
    /// restore (older months live in their archives).
    public func backupRecent(to path: String, since: Int) throws {
        try writeSlice(.since(since), to: path)
    }

    /// Builds a copy table by table on its own connection, with the live database attached read-only in a
    /// single read transaction (a consistent snapshot that, in WAL mode, never blocks the app's writes).
    /// Same schema and `user_version` as the live database, so it opens and restores like any copy. With
    /// `keeping`, the per-second rows of that older file are merged in (a month archive being refreshed never
    /// loses a second). `info` stamps a month archive with what it holds.
    func writeSlice(_ slice: Slice, to path: String, keeping old: String? = nil,
                    info: ((SecondsCount) -> MonthArchiveInfo)? = nil) throws {
        let source = sql.path
        try writeCopy(to: path) { tmp in
            let c = try SQLiteConnection(path: tmp)
            try c.run("ATTACH DATABASE ? AS src", [.text(source)])
            if let old { try c.run("ATTACH DATABASE ? AS prev", [.text(old)]) }
            let schema = try c.query("SELECT type, name, sql FROM src.sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY rowid") {
                (type: $0.text(0) ?? "", name: $0.text(1) ?? "", sql: $0.text(2) ?? "")
            }
            for t in schema where t.type == "table" { try c.execute(t.sql) }
            let version = try c.scalarInt("PRAGMA src.user_version;") ?? 0
            try c.execute("PRAGMA user_version = \(version);")
            // Plain BEGIN, not IMMEDIATE: that would also take the live database's write lock.
            try c.execute("BEGIN;")
            do {
                for t in schema where t.type == "table" {
                    guard let filter = slice.filter(t.name) else { continue }
                    try c.execute("INSERT INTO main.\"\(t.name)\" SELECT * FROM src.\"\(t.name)\" \(filter);")
                }
                if old != nil {
                    let prevTables = Set(try c.query("SELECT name FROM prev.sqlite_master WHERE type='table'") { $0.text(0) ?? "" })
                    try Self.mergeSeconds(into: c, from: "prev", tables: prevTables, where: "WHERE 1")
                }
                if let info {
                    let stamp = info(try Self.countSeconds(c, schema: "main", from: nil, to: nil))
                    let json = String(decoding: try JSONEncoder().encode(stamp), as: UTF8.self)
                    try c.run("INSERT OR REPLACE INTO main.kv(key,value) VALUES(?,?)", [.text(Self.archiveInfoKey), .text(json)])
                }
                try c.execute("COMMIT;")
            } catch {
                try? c.execute("ROLLBACK;")
                throw error
            }
            // Indexes after the rows: faster than keeping them up to date row by row.
            for t in schema where t.type == "index" { try c.execute(t.sql) }
            try c.execute("DETACH DATABASE src;")
            if old != nil { try c.execute("DETACH DATABASE prev;") }
            // A single self-contained file (no -wal next to it) before it is checked and named.
            try c.execute("PRAGMA journal_mode=DELETE;")
        }
    }

    // MARK: - Month archives

    /// What `[from, to)` holds in the live database.
    public func secondsCount(from: Int, to: Int) throws -> SecondsCount {
        try Self.countSeconds(sql, schema: "main", from: from, to: to)
    }

    static func countSeconds(_ c: SQLiteConnection, schema: String, from: Int?, to: Int?) throws -> SecondsCount {
        let filter = from.map { "WHERE ts >= \($0) AND ts < \(to ?? Int.max)" } ?? ""
        var n = SecondsCount()
        _ = try c.query("SELECT COUNT(*), COUNT(hr), COUNT(rr), COUNT(gx), COUNT(temp), COUNT(spo2), COUNT(steps), MAX(ts) FROM \(schema).samples \(filter)") { r in
            n.rows = Int(r.int(0) ?? 0); n.hr = Int(r.int(1) ?? 0); n.rr = Int(r.int(2) ?? 0); n.motion = Int(r.int(3) ?? 0)
            n.temp = Int(r.int(4) ?? 0); n.spo2 = Int(r.int(5) ?? 0); n.steps = Int(r.int(6) ?? 0); n.last = r.int(7).map(Int.init)
        }
        n.live = Int(try c.scalarInt("SELECT COUNT(*) FROM \(schema).live_hr \(filter)") ?? 0)
        return n
    }

    func hasSeconds(from: Int, to: Int) throws -> Bool {
        let args: [SQLValue] = [.int(Int64(from)), .int(Int64(to))]
        if (try sql.scalarInt("SELECT EXISTS(SELECT 1 FROM samples WHERE ts >= ? AND ts < ?)", args) ?? 0) != 0 { return true }
        return (try sql.scalarInt("SELECT EXISTS(SELECT 1 FROM live_hr WHERE ts >= ? AND ts < ?)", args) ?? 0) != 0
    }

    /// The stamp inside a month archive; nil for any other file.
    public static func monthArchiveInfo(path: String) -> MonthArchiveInfo? {
        guard let c = try? SQLiteConnection(path: path, readOnly: true),
              let json = (try? c.query("SELECT value FROM kv WHERE key = ?", [.text(archiveInfoKey)]) { $0.text(0) })?.first ?? nil
        else { return nil }
        return try? JSONDecoder().decode(MonthArchiveInfo.self, from: Data(json.utf8))
    }

    /// Writes (or refreshes) the archive of `month`'s per-second data at `path`: temp file, integrity check,
    /// rename. An archive already there is merged in, never replaced by less; a damaged one is set aside
    /// under a name the rotation ignores ("…-revisar-….sqlite"), never deleted.
    public func writeMonthArchive(month: String, calendar: Calendar, to path: String) throws {
        guard let r = BackupPolicy.monthRange(month, calendar: calendar) else { return }
        // One writer at a time (the daily pass on the analysis queue and «Borrar todo» on the main thread can
        // reach the same month): two writers share the temporary name and could rename each other's half file.
        Self.archiveLock.lock(); defer { Self.archiveLock.unlock() }
        let fm = FileManager.default
        var keep: String?
        if fm.fileExists(atPath: path) {
            if Self.isIntactCopy(path: path) {
                keep = path
            } else {
                let aside = String(path.dropLast(".sqlite".count)) + "-revisar-\(Int(Date().timeIntervalSince1970)).sqlite"
                try fm.moveItem(atPath: path, toPath: aside)
            }
        }
        try writeSlice(.seconds(from: r.from, to: r.to), to: path, keeping: keep) { counts in
            MonthArchiveInfo(month: month, from: r.from, to: r.to, counts: counts, written: Int(Date().timeIntervalSince1970))
        }
    }

    /// Writes the oldest missing archive of a closed month, or (with `refresh`) rewrites one whose month got
    /// more seconds in the live database since it was written. At most one per call, so a first run with a
    /// year of data catches up a month at a time. Returns the month written, nil if all are up to date.
    @discardableResult
    public func archiveNextMonth(in folder: String, now: Date = Date(), calendar: Calendar, refresh: Bool) throws -> String? {
        let firsts = [try sql.scalarInt("SELECT MIN(ts) FROM samples"), try sql.scalarInt("SELECT MIN(ts) FROM live_hr")]
        guard let first = firsts.compactMap({ $0 }).min() else { return nil }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
        let archived = Set(names.compactMap(BackupPolicy.parse).filter { $0.kind == .archive }.compactMap(\.month))
        let months = BackupPolicy.closedMonths(firstSecond: Int(first), now: now, calendar: calendar)
        func path(_ m: String) -> String { (folder as NSString).appendingPathComponent(BackupPolicy.archiveName(month: m)) }
        for m in months where !archived.contains(m) {
            guard let r = BackupPolicy.monthRange(m, calendar: calendar), try hasSeconds(from: r.from, to: r.to) else { continue }
            try writeMonthArchive(month: m, calendar: calendar, to: path(m))
            return m
        }
        guard refresh else { return nil }
        for m in months.reversed() where archived.contains(m) {
            guard let r = BackupPolicy.monthRange(m, calendar: calendar) else { continue }
            let live = try secondsCount(from: r.from, to: r.to)
            guard live.rows > 0 || live.live > 0 else { continue }
            if let stored = Self.monthArchiveInfo(path: path(m)), stored.from == r.from, stored.to == r.to,
               !live.hasMoreThan(stored.counts) { continue }
            try writeMonthArchive(month: m, calendar: calendar, to: path(m))
            return m
        }
        return nil
    }

    /// Before erasing everything: every month with seconds in the live database, the current one included,
    /// gets an up-to-date archive (written, or refreshed by merging), so no second depends on a safety copy
    /// the rotation may drop later. The current month's archive is refreshed like any other once it closes
    /// (`archiveNextMonth`, the live database then has later seconds). Throws on the first failure (no space):
    /// the caller must not erase.
    public func archiveAllMonths(in folder: String, now: Date = Date(), calendar: Calendar) throws {
        let firsts = [try sql.scalarInt("SELECT MIN(ts) FROM samples"), try sql.scalarInt("SELECT MIN(ts) FROM live_hr")]
        guard let first = firsts.compactMap({ $0 }).min() else { return }
        let current = BackupPolicy.monthKey(now, calendar: calendar)
        var months = BackupPolicy.closedMonths(firstSecond: Int(first), now: now, calendar: calendar)
        if !months.contains(current) { months.append(current) }
        for m in months {
            guard let r = BackupPolicy.monthRange(m, calendar: calendar), try hasSeconds(from: r.from, to: r.to) else { continue }
            let path = (folder as NSString).appendingPathComponent(BackupPolicy.archiveName(month: m))
            let live = try secondsCount(from: r.from, to: r.to)
            if let stored = Self.monthArchiveInfo(path: path), stored.from == r.from, stored.to == r.to,
               !live.hasMoreThan(stored.counts) { continue }
            try writeMonthArchive(month: m, calendar: calendar, to: path)
        }
    }

    /// kv key: unix second before which every per-second row has its month archive (`pruneSamples` never
    /// deletes past it).
    public static let prunableBeforeKey = "archive.prunableBefore"

    /// Records how far back the month archives in `folder` cover the live database: every closed month, from
    /// the oldest second on, that still has seconds here must have its archive (cut with the same boundaries).
    /// The retention limit (`pruneSamples`) stops at the first month without one, so a second is never deleted
    /// before it is archived. Cheap (an index probe per month and the archive's stamp). Late seconds of an
    /// archived month are copied at the next daily refresh; the strap keeps only days, far less than any
    /// retention limit, so they are never pruned first.
    @discardableResult
    public func updateArchiveCoverage(in folder: String, now: Date = Date(), calendar: Calendar) throws -> Int? {
        let firsts = [try sql.scalarInt("SELECT MIN(ts) FROM samples"), try sql.scalarInt("SELECT MIN(ts) FROM live_hr")]
        guard let first = firsts.compactMap({ $0 }).min() else { return nil }
        var covered = Int(first)
        for m in BackupPolicy.closedMonths(firstSecond: Int(first), now: now, calendar: calendar) {
            guard let r = BackupPolicy.monthRange(m, calendar: calendar) else { break }
            if try hasSeconds(from: r.from, to: r.to) {
                let path = (folder as NSString).appendingPathComponent(BackupPolicy.archiveName(month: m))
                guard let info = Self.monthArchiveInfo(path: path), info.from == r.from, info.to == r.to else { break }
            }
            covered = r.to
        }
        try set(covered, for: Self.prunableBeforeKey)
        return covered
    }

    // MARK: - Merging seconds back (restore)

    /// Adds the per-second data of another Pulso file (a month archive, the database a restore set aside)
    /// that this one lacks: missing seconds are inserted and empty fields of existing ones filled, but a value
    /// already here is never replaced (the restored copy wins; raw seconds are facts, so nothing is lost
    /// either way). A day at a time, so the database is never held for long. Returns the first second of the
    /// earliest stretch that changed, nil if nothing did.
    @discardableResult
    public func mergeSeconds(from path: String) throws -> Int? {
        let alias = "merge_src"
        try sql.run("ATTACH DATABASE ? AS \(alias)", [.text(path)])
        defer { try? sql.execute("DETACH DATABASE \(alias);") }
        let tables = Set(try sql.query("SELECT name FROM \(alias).sqlite_master WHERE type='table'") { $0.text(0) ?? "" })
        var earliest: Int?
        if tables.contains("samples"),
           let lo = try sql.scalarInt("SELECT MIN(ts) FROM \(alias).samples"),
           let hi = try sql.scalarInt("SELECT MAX(ts) FROM \(alias).samples") {
            let fill = Self.fillSamplesSQL(from: alias, where: "WHERE ts >= ? AND ts < ?")
            var start = Int(lo)
            while start <= Int(hi) {
                let end = start + 86400
                let changed = try sql.transaction { () -> Bool in
                    let before = sql.totalChanges
                    try sql.run(fill, [.int(Int64(start)), .int(Int64(end))])
                    return sql.totalChanges != before
                }
                if changed, earliest == nil { earliest = start }
                start = end
            }
        }
        try sql.transaction { try Self.mergeSeconds(into: sql, from: alias, tables: tables.subtracting(["samples"]), where: "") }
        return earliest
    }

    /// Merges `from`'s per-second tables into `c`'s main ones (only those in `tables`).
    static func mergeSeconds(into c: SQLiteConnection, from alias: String, tables: Set<String>, where clause: String) throws {
        if tables.contains("samples") { try c.execute(fillSamplesSQL(from: alias, where: clause)) }
        if tables.contains("live_hr") {
            try c.execute("INSERT OR IGNORE INTO main.live_hr(ts,hr,rr) SELECT ts,hr,rr FROM \(alias).live_hr;")
        }
        if tables.contains("undecoded_records") {
            // Without the id: two files number their frames independently; the frame itself is unique.
            try c.execute("INSERT OR IGNORE INTO main.undecoded_records(received,version,frame) SELECT received,version,frame FROM \(alias).undecoded_records;")
        }
    }

    /// The mirror image of `insert`'s UPSERT: the row already here keeps every value it has and only its
    /// empty fields are filled from `alias` (COALESCE the other way round); poor/off follow the pulse, as
    /// there. Rows with nothing to fill are left alone (no write). `where` must be non-empty
    /// (an upsert after a bare SELECT is ambiguous to the parser).
    static func fillSamplesSQL(from alias: String, where clause: String) -> String {
        let cols = (["ts"] + sampleValueColumns + ["poor", "off"]).joined(separator: ",")
        let sets = sampleValueColumns.map { "\($0) = COALESCE(samples.\($0), excluded.\($0))" }.joined(separator: ", ")
        let gaps = sampleValueColumns.map { "(samples.\($0) IS NULL AND excluded.\($0) IS NOT NULL)" }.joined(separator: " OR ")
        return """
        INSERT INTO samples(\(cols)) SELECT \(cols) FROM \(alias).samples \(clause.isEmpty ? "WHERE 1" : clause)
        ON CONFLICT(ts) DO UPDATE SET \(sets),
            poor = CASE WHEN samples.hr IS NULL AND excluded.hr IS NOT NULL THEN excluded.poor ELSE samples.poor END,
            off = CASE WHEN samples.hr IS NULL AND excluded.hr IS NOT NULL THEN excluded.off ELSE samples.off END
        WHERE \(gaps);
        """
    }

    // MARK: - Small helpers for the app

    /// Latest day with a summary ("2026-11-05"), nil if none.
    public func latestDay() throws -> String? {
        try sql.query("SELECT MAX(day) FROM days") { $0.text(0) }.first ?? nil
    }

    /// True if there is anything a person would miss (seconds, days, sleeps, workouts, imports, journal, ECG).
    public func holdsData() throws -> Bool {
        for t in ["samples", "live_hr", "days", "imported_days", "sleeps", "workouts", "journal", "ecg"] {
            if (try sql.scalarInt("SELECT EXISTS(SELECT 1 FROM \(t) LIMIT 1)") ?? 0) != 0 { return true }
        }
        return false
    }
}
