import Foundation
import WhoopProtocol

/// The app's on-device database: raw per-second strap data plus every derived summary.
/// Nothing leaves the phone.
public final class PulsoDatabase {
    public let sql: SQLiteConnection
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(path: String) throws {
        sql = try SQLiteConnection(path: path)
        try migrate()
    }

    /// Default location: Application Support/Pulso/pulso.sqlite
    public static func defaultPath() throws -> String {
        let fm = FileManager.default
        let base = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Pulso", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("pulso.sqlite").path
    }

    /// Schema version this build writes (`PRAGMA user_version`).
    public static let schemaVersion = 1

    /// Ordered schema changes. Append, never edit: each one runs once, in its own transaction, on databases
    /// created by older versions. Version 0 is the original schema below.
    static let migrations: [(version: Int, sql: String)] = [
        (1, "CREATE INDEX IF NOT EXISTS days_updated ON days(updated); CREATE INDEX IF NOT EXISTS sleeps_end ON sleeps(end);"),
    ]

    /// Version found on disk after opening (newer than `schemaVersion` if a newer build wrote it).
    public private(set) var diskSchemaVersion = 0

    private func migrate() throws {
        try createBaseSchema()
        var v = Int(try sql.scalarInt("PRAGMA user_version;") ?? 0)
        for m in Self.migrations where m.version > v {
            _ = try sql.transaction { () -> Int in
                try sql.execute(m.sql)
                try sql.execute("PRAGMA user_version = \(m.version);")
                return m.version
            }
            v = m.version
        }
        diskSchemaVersion = v
    }

    private func createBaseSchema() throws {
        try sql.execute("""
        CREATE TABLE IF NOT EXISTS samples(
            ts INTEGER PRIMARY KEY,
            hr INTEGER, rr BLOB,
            gx REAL, gy REAL, gz REAL, dyn REAL,
            temp REAL, spo2 INTEGER, steps INTEGER,
            act INTEGER, sstate INTEGER, quality INTEGER,
            poor INTEGER NOT NULL DEFAULT 0, off INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS live_hr(ts INTEGER PRIMARY KEY, hr INTEGER NOT NULL, rr TEXT);
        CREATE TABLE IF NOT EXISTS sleeps(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start INTEGER NOT NULL, end INTEGER NOT NULL,
            is_nap INTEGER NOT NULL DEFAULT 0, manual INTEGER NOT NULL DEFAULT 0,
            json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS sleeps_start ON sleeps(start);
        CREATE TABLE IF NOT EXISTS days(day TEXT PRIMARY KEY, json TEXT NOT NULL, updated INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS workouts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start INTEGER NOT NULL, end INTEGER NOT NULL,
            source TEXT NOT NULL, json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS workouts_start ON workouts(start);
        CREATE TABLE IF NOT EXISTS journal(day TEXT NOT NULL, key TEXT NOT NULL, value REAL NOT NULL, PRIMARY KEY(day, key));
        CREATE TABLE IF NOT EXISTS events(ts INTEGER NOT NULL, kind INTEGER NOT NULL, value REAL);
        CREATE INDEX IF NOT EXISTS events_ts ON events(ts);
        CREATE TABLE IF NOT EXISTS imported_days(day TEXT PRIMARY KEY, json TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS kv(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS ecg(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start INTEGER NOT NULL, source TEXT NOT NULL, external_id TEXT,
            rate REAL NOT NULL, samples BLOB NOT NULL, json TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS ecg_start ON ecg(start);
        """)
    }

    // MARK: - Raw samples

    public func insert(_ samples: [HistorySample]) throws {
        guard !samples.isEmpty else { return }
        let rows: [[SQLValue]] = samples.map { s in
            [
                .int(Int64(s.unix)),
                .from(s.heartRate.map { Int($0) }),
                s.rr.isEmpty ? .null : .blob(s.rr.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }),
                .from(s.gravity.map { Double($0.x) }),
                .from(s.gravity.map { Double($0.y) }),
                .from(s.gravity.map { Double($0.z) }),
                .from(s.dynamicAccelG.map { Double($0) }),
                .from(s.skinTempC.map { Double($0) }),
                .from(s.spo2.map { Int($0) }),
                .from(s.steps.map { Int($0) }),
                .from(s.activityClass.map { Int($0) }),
                .from(s.sleepState.map { Int($0) }),
                .from(s.signalQuality.map { Int($0) }),
                .from(s.signalPoor),
                .from(s.offWrist),
            ]
        }
        try sql.transaction {
            try sql.run("""
            INSERT OR REPLACE INTO samples(ts,hr,rr,gx,gy,gz,dyn,temp,spo2,steps,act,sstate,quality,poor,off)
            VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
            """, rows)
        }
    }

    public func samples(from: Int, to: Int) throws -> [Sample] {
        try sql.query("""
        SELECT ts,hr,rr,gx,gy,gz,dyn,temp,spo2,steps,act,sstate,quality,poor,off
        FROM samples WHERE ts >= ? AND ts < ? ORDER BY ts
        """, [.int(Int64(from)), .int(Int64(to))]) { r in
            Sample(
                ts: Int(r.int(0) ?? 0),
                hr: r.int(1).map { Int($0) },
                rr: r.uint16s(2),
                gx: r.double(3), gy: r.double(4), gz: r.double(5),
                dyn: r.double(6), temp: r.double(7),
                spo2: r.int(8).map { Int($0) }, steps: r.int(9).map { Int($0) },
                activity: r.int(10).map { Int($0) }, sleepState: r.int(11).map { Int($0) },
                quality: r.int(12).map { Int($0) },
                poor: (r.int(13) ?? 0) != 0, off: (r.int(14) ?? 0) != 0
            )
        }
    }

    public func sampleBounds() throws -> (first: Int, last: Int)? {
        let rows = try sql.query("SELECT MIN(ts), MAX(ts), COUNT(*) FROM samples") { r in
            (r.int(0), r.int(1), r.int(2) ?? 0)
        }
        guard let row = rows.first, row.2 > 0, let a = row.0, let b = row.1 else { return nil }
        return (Int(a), Int(b))
    }

    /// Cheap existence check (no table scan).
    public func hasSamples() throws -> Bool {
        (try sql.scalarInt("SELECT EXISTS(SELECT 1 FROM samples LIMIT 1)") ?? 0) != 0
    }

    public func sampleCount() throws -> Int {
        Int(try sql.scalarInt("SELECT COUNT(*) FROM samples") ?? 0)
    }

    /// Deletes raw seconds older than `ts` (summaries are kept).
    public func pruneSamples(olderThan ts: Int) throws {
        try sql.run("DELETE FROM samples WHERE ts < ?", [.int(Int64(ts))])
        try sql.run("DELETE FROM live_hr WHERE ts < ?", [.int(Int64(ts))])
    }

    // MARK: - Live HR

    public func insertLive(ts: Int, hr: Int, rr: [Int]) throws {
        try sql.run("INSERT OR REPLACE INTO live_hr(ts,hr,rr) VALUES(?,?,?)",
                    [.int(Int64(ts)), .int(Int64(hr)), rr.isEmpty ? .null : .text(rr.map(String.init).joined(separator: ","))])
    }

    public func liveHR(from: Int, to: Int) throws -> [(ts: Int, hr: Int, rr: [Int])] {
        try sql.query("SELECT ts,hr,rr FROM live_hr WHERE ts >= ? AND ts < ? ORDER BY ts",
                      [.int(Int64(from)), .int(Int64(to))]) { r in
            (Int(r.int(0) ?? 0), Int(r.int(1) ?? 0), (r.text(2) ?? "").split(separator: ",").compactMap { Int($0) })
        }
    }

    // MARK: - Sleeps

    public func sleeps(from: Int, to: Int) throws -> [SleepSession] {
        try sql.query("SELECT id,json FROM sleeps WHERE end > ? AND start < ? ORDER BY start",
                      [.int(Int64(from)), .int(Int64(to))]) { r -> SleepSession? in
            guard let json = r.text(1), var s = try? decoder.decode(SleepSession.self, from: Data(json.utf8)) else { return nil }
            s.id = r.int(0)
            return s
        }.compactMap { $0 }
    }

    public func sleep(id: Int64) throws -> SleepSession? {
        try sql.query("SELECT id,json FROM sleeps WHERE id = ?", [.int(id)]) { r -> SleepSession? in
            guard let json = r.text(1), var s = try? decoder.decode(SleepSession.self, from: Data(json.utf8)) else { return nil }
            s.id = r.int(0)
            return s
        }.first ?? nil
    }

    @discardableResult
    public func save(_ s: SleepSession) throws -> Int64 {
        let json = String(decoding: try encoder.encode(s), as: UTF8.self)
        if let id = s.id {
            try sql.run("UPDATE sleeps SET start=?, end=?, is_nap=?, manual=?, json=? WHERE id=?",
                        [.int(Int64(s.start)), .int(Int64(s.end)), .from(s.isNap), .from(s.manual), .text(json), .int(id)])
            return id
        }
        return try sql.transaction {
            try sql.run("INSERT INTO sleeps(start,end,is_nap,manual,json) VALUES(?,?,?,?,?)",
                        [.int(Int64(s.start)), .int(Int64(s.end)), .from(s.isNap), .from(s.manual), .text(json)])
            return try sql.scalarInt("SELECT last_insert_rowid()") ?? 0
        }
    }

    /// Removes automatically detected sleeps overlapping [from, to) (manual edits are preserved).
    public func deleteAutoSleeps(from: Int, to: Int) throws {
        try sql.run("DELETE FROM sleeps WHERE manual = 0 AND end > ? AND start < ?", [.int(Int64(from)), .int(Int64(to))])
    }

    public func deleteSleep(id: Int64) throws {
        try sql.run("DELETE FROM sleeps WHERE id = ?", [.int(id)])
    }

    // MARK: - Days

    public func save(_ d: DaySummary) throws {
        let json = String(decoding: try encoder.encode(d), as: UTF8.self)
        try sql.run("INSERT OR REPLACE INTO days(day,json,updated) VALUES(?,?,?)",
                    [.text(d.day), .text(json), .int(Int64(Date().timeIntervalSince1970))])
    }

    public func day(_ key: String) throws -> DaySummary? {
        try sql.query("SELECT json FROM days WHERE day = ?", [.text(key)]) { r in
            r.text(0).flatMap { try? decoder.decode(DaySummary.self, from: Data($0.utf8)) }
        }.first ?? nil
    }

    /// Days in [from, to] inclusive (keys are yyyy-MM-dd so string order is date order).
    public func days(from: String, to: String) throws -> [DaySummary] {
        try sql.query("SELECT json FROM days WHERE day >= ? AND day <= ? ORDER BY day", [.text(from), .text(to)]) { r in
            r.text(0).flatMap { try? decoder.decode(DaySummary.self, from: Data($0.utf8)) }
        }.compactMap { $0 }
    }

    // MARK: - Daytime sleep decisions

    static let sleepDecisionsKey = "sleep.decisions"

    public func sleepDecisions() -> [SleepDecision] {
        get([SleepDecision].self, for: Self.sleepDecisionsKey) ?? []
    }

    /// Saves the answer for a daytime sleep, replacing an earlier answer for the same sleep.
    public func saveSleepDecision(_ d: SleepDecision) throws {
        var all = sleepDecisions().filter { SleepDecision.overlapFraction($0.start, $0.end, d.start, d.end) < 0.5 }
        all.append(d)
        try set(all.suffix(400), for: Self.sleepDecisionsKey)
    }

    /// The answer given for a sleep that overlaps this one by at least half (detection moves edges a little).
    public func sleepDecision(start: Int, end: Int) -> SleepDecision? {
        sleepDecisions().last { SleepDecision.overlapFraction($0.start, $0.end, start, end) >= 0.5 }
    }

    public func deleteDay(_ day: String) throws {
        try sql.run("DELETE FROM days WHERE day = ?", [.text(day)])
    }

    public func allDays() throws -> [DaySummary] {
        try days(from: "0000-00-00", to: "9999-99-99")
    }

    // MARK: - Imported (WHOOP CSV) days, used to seed baselines

    public func saveImported(_ d: DaySummary) throws {
        let json = String(decoding: try encoder.encode(d), as: UTF8.self)
        try sql.run("INSERT OR REPLACE INTO imported_days(day,json) VALUES(?,?)", [.text(d.day), .text(json)])
    }

    public func importedDays() throws -> [DaySummary] {
        try sql.query("SELECT json FROM imported_days ORDER BY day") { r in
            r.text(0).flatMap { try? decoder.decode(DaySummary.self, from: Data($0.utf8)) }
        }.compactMap { $0 }
    }

    // MARK: - Workouts

    public func workouts(from: Int, to: Int) throws -> [Workout] {
        try sql.query("SELECT id,json FROM workouts WHERE end > ? AND start < ? ORDER BY start",
                      [.int(Int64(from)), .int(Int64(to))]) { r -> Workout? in
            guard let json = r.text(1), var w = try? decoder.decode(Workout.self, from: Data(json.utf8)) else { return nil }
            w.id = r.int(0)
            return w
        }.compactMap { $0 }
    }

    @discardableResult
    public func save(_ w: Workout) throws -> Int64 {
        let json = String(decoding: try encoder.encode(w), as: UTF8.self)
        if let id = w.id {
            try sql.run("UPDATE workouts SET start=?, end=?, source=?, json=? WHERE id=?",
                        [.int(Int64(w.start)), .int(Int64(w.end)), .text(w.source.rawValue), .text(json), .int(id)])
            return id
        }
        return try sql.transaction {
            try sql.run("INSERT INTO workouts(start,end,source,json) VALUES(?,?,?,?)",
                        [.int(Int64(w.start)), .int(Int64(w.end)), .text(w.source.rawValue), .text(json)])
            return try sql.scalarInt("SELECT last_insert_rowid()") ?? 0
        }
    }

    public func deleteWorkout(id: Int64) throws {
        try sql.run("DELETE FROM workouts WHERE id = ?", [.int(id)])
    }

    public func deleteAutoWorkouts(from: Int, to: Int) throws {
        try sql.run("DELETE FROM workouts WHERE source = 'auto' AND end > ? AND start < ?", [.int(Int64(from)), .int(Int64(to))])
    }

    /// The workout already linked to `id` in `service` (e.g. a Strava activity), if any.
    public func workout(externalID id: String, service: String) throws -> Workout? {
        let needle = "%\"\(service)\":\"\(id)\"%"
        return try sql.query("SELECT id,json FROM workouts WHERE json LIKE ?", [.text(needle)]) { r -> Workout? in
            guard let json = r.text(1), var w = try? decoder.decode(Workout.self, from: Data(json.utf8)) else { return nil }
            w.id = r.int(0)
            return w
        }.compactMap { $0 }.first { $0.externalID(service) == id }
    }

    // MARK: - ECG

    private struct ECGMeta: Codable {
        var rhythm: String?
        var avgHR: Double?
        var notes: String
    }

    @discardableResult
    public func save(_ e: ECGRecording) throws -> Int64 {
        let meta = String(decoding: try encoder.encode(ECGMeta(rhythm: e.rhythm, avgHR: e.avgHR, notes: e.notes)), as: UTF8.self)
        var blob = [UInt8]()
        blob.reserveCapacity(e.samples.count * 4)
        for v in e.samples { blob += LE.bytes(v.bitPattern) }
        if let id = e.id {
            try sql.run("UPDATE ecg SET start=?, source=?, external_id=?, rate=?, samples=?, json=? WHERE id=?",
                        [.int(Int64(e.start)), .text(e.source.rawValue), .from(e.externalID), .double(e.sampleRate),
                         .blob(blob), .text(meta), .int(id)])
            return id
        }
        return try sql.transaction {
            try sql.run("INSERT INTO ecg(start,source,external_id,rate,samples,json) VALUES(?,?,?,?,?,?)",
                        [.int(Int64(e.start)), .text(e.source.rawValue), .from(e.externalID), .double(e.sampleRate),
                         .blob(blob), .text(meta)])
            return try sql.scalarInt("SELECT last_insert_rowid()") ?? 0
        }
    }

    /// Recordings newest first. `withSamples: false` skips the waveform (cheap list view).
    public func ecgRecordings(withSamples: Bool = true) throws -> [ECGRecording] {
        try ecgRecordings(withSamples: withSamples, id: nil)
    }

    private func ecgRecordings(withSamples: Bool, id: Int64?) throws -> [ECGRecording] {
        let cols = withSamples ? "samples" : "NULL"
        let filter = id == nil ? "" : " WHERE id = ?"
        return try sql.query("SELECT id,start,source,external_id,rate,\(cols),json FROM ecg\(filter) ORDER BY start DESC",
                             id.map { [.int($0)] } ?? []) { r -> ECGRecording? in
            guard let source = ECGSource(rawValue: r.text(2) ?? "") else { return nil }
            let meta = r.text(6).flatMap { try? decoder.decode(ECGMeta.self, from: Data($0.utf8)) }
            let raw = r.bytes(5)
            var samples = [Float]()
            samples.reserveCapacity(raw.count / 4)
            var i = 0
            while i + 4 <= raw.count {
                if let bits = LE.u32(raw, i) { samples.append(Float(bitPattern: bits)) }
                i += 4
            }
            return ECGRecording(id: r.int(0), start: Int(r.int(1) ?? 0), sampleRate: r.double(4) ?? 0, samples: samples,
                                source: source, rhythm: meta?.rhythm, avgHR: meta?.avgHR, notes: meta?.notes ?? "",
                                externalID: r.text(3))
        }.compactMap { $0 }
    }

    public func ecgRecording(id: Int64) throws -> ECGRecording? {
        try ecgRecordings(withSamples: true, id: id).first
    }

    public func hasECG(externalID: String) throws -> Bool {
        (try sql.scalarInt("SELECT COUNT(*) FROM ecg WHERE external_id = ?", [.text(externalID)]) ?? 0) > 0
    }

    public func deleteECG(id: Int64) throws {
        try sql.run("DELETE FROM ecg WHERE id = ?", [.int(id)])
    }

    // MARK: - Backup

    /// Writes a consistent, compacted copy of the whole database to `path` (overwrites it).
    public func backup(to path: String) throws {
        if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        try sql.run("VACUUM INTO ?", [.text(path)])
    }

    /// True if `path` is a readable Pulso database (used before restoring a backup over the live one).
    public static func isValidBackup(path: String) -> Bool {
        guard let c = try? SQLiteConnection(path: path, readOnly: true) else { return false }
        let tables = (try? c.query("SELECT name FROM sqlite_master WHERE type='table'") { $0.text(0) ?? "" }) ?? []
        return ["samples", "days", "sleeps", "workouts", "kv"].allSatisfy(tables.contains)
    }

    // MARK: - Journal

    public func setJournal(day: String, key: String, value: Double?) throws {
        if let value {
            try sql.run("INSERT OR REPLACE INTO journal(day,key,value) VALUES(?,?,?)", [.text(day), .text(key), .double(value)])
        } else {
            try sql.run("DELETE FROM journal WHERE day = ? AND key = ?", [.text(day), .text(key)])
        }
    }

    public func journal(day: String) throws -> [String: Double] {
        let rows = try sql.query("SELECT key,value FROM journal WHERE day = ?", [.text(day)]) { r in
            (r.text(0) ?? "", r.double(1) ?? 0)
        }
        return Dictionary(rows, uniquingKeysWith: { a, _ in a })
    }

    public func allJournal() throws -> [JournalEntry] {
        try sql.query("SELECT day,key,value FROM journal ORDER BY day") { r in
            JournalEntry(day: r.text(0) ?? "", key: r.text(1) ?? "", value: r.double(2) ?? 0)
        }
    }

    // MARK: - Events

    public func insertEvent(_ e: StoredEvent) throws {
        try sql.run("INSERT INTO events(ts,kind,value) VALUES(?,?,?)", [.int(Int64(e.ts)), .int(Int64(e.kind)), .from(e.value)])
    }

    public func events(kind: Int, since: Int) throws -> [StoredEvent] {
        try sql.query("SELECT ts,kind,value FROM events WHERE kind = ? AND ts >= ? ORDER BY ts",
                      [.int(Int64(kind)), .int(Int64(since))]) { r in
            StoredEvent(ts: Int(r.int(0) ?? 0), kind: Int(r.int(1) ?? 0), value: r.double(2))
        }
    }

    // MARK: - Key/value (profile, device, sync state)

    public func set<T: Encodable>(_ value: T, for key: String) throws {
        let json = String(decoding: try encoder.encode(value), as: UTF8.self)
        try sql.run("INSERT OR REPLACE INTO kv(key,value) VALUES(?,?)", [.text(key), .text(json)])
    }

    public func get<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        let rows = (try? sql.query("SELECT value FROM kv WHERE key = ?", [.text(key)]) { $0.text(0) }) ?? []
        guard let json = rows.first ?? nil else { return nil }
        return try? decoder.decode(T.self, from: Data(json.utf8))
    }

    public var profile: Profile {
        get { get(Profile.self, for: "profile") ?? Profile() }
        set { try? set(newValue, for: "profile") }
    }

    /// Wipes every table (used by "Borrar todos mis datos").
    public func eraseAll() throws {
        try sql.execute("""
        DELETE FROM samples; DELETE FROM live_hr; DELETE FROM sleeps; DELETE FROM days;
        DELETE FROM workouts; DELETE FROM journal; DELETE FROM events; DELETE FROM imported_days; DELETE FROM kv;
        DELETE FROM ecg;
        """)
        try sql.execute("VACUUM;")
    }
}
