import Foundation
#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String, sql: String)
    case step(String)

    public var description: String {
        switch self {
        case .open(let m): return "SQLite open: \(m)"
        case .prepare(let m, let sql): return "SQLite prepare: \(m) — \(sql)"
        case .step(let m): return "SQLite step: \(m)"
        }
    }
}

/// A value bindable to / readable from SQLite.
public enum SQLValue: Equatable {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob([UInt8])
}

private let SQLITE_TRANSIENT_PTR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal, lock-protected SQLite connection. All access is serialised through one recursive lock,
/// so it is safe to call from the Bluetooth queue and from analytics concurrently.
public final class SQLiteConnection {
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()
    public let path: String

    public init(path: String, readOnly: Bool = false) throws {
        self.path = path
        let flags = readOnly ? (SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX)
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX)
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            db = nil
            throw SQLiteError.open(msg)
        }
        if readOnly { return }
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    deinit {
        sqlite3_close(db)
    }

    private var errorMessage: String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
    }

    public func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(err)
            throw SQLiteError.step(msg)
        }
    }

    /// Runs `body` inside a transaction; rolls back if it throws.
    public func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try execute("BEGIN IMMEDIATE;")
        do {
            let r = try body()
            try execute("COMMIT;")
            return r
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// Executes a statement once per parameter row (prepared once).
    public func run(_ sql: String, _ rows: [[SQLValue]]) throws {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        for row in rows {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            bind(stmt, row)
            let rc = sqlite3_step(stmt)
            guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw SQLiteError.step(errorMessage) }
        }
    }

    public func run(_ sql: String, _ params: [SQLValue] = []) throws {
        try run(sql, [params])
    }

    /// Runs a query and maps each row.
    public func query<T>(_ sql: String, _ params: [SQLValue] = [], _ map: (Row) throws -> T) throws -> [T] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage, sql: sql)
        }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, params)
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append(try map(Row(stmt: stmt)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.step(errorMessage)
            }
        }
        return out
    }

    public func scalarInt(_ sql: String, _ params: [SQLValue] = []) throws -> Int64? {
        try query(sql, params) { $0.int(0) }.first ?? nil
    }

    private func bind(_ stmt: OpaquePointer?, _ values: [SQLValue]) {
        for (i, v) in values.enumerated() {
            let idx = Int32(i + 1)
            switch v {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let x): sqlite3_bind_int64(stmt, idx, x)
            case .double(let x): sqlite3_bind_double(stmt, idx, x)
            case .text(let s): sqlite3_bind_text(stmt, idx, s, -1, SQLITE_TRANSIENT_PTR)
            case .blob(let b):
                if b.isEmpty {
                    sqlite3_bind_zeroblob(stmt, idx, 0)
                } else {
                    b.withUnsafeBytes { raw in
                        _ = sqlite3_bind_blob(stmt, idx, raw.baseAddress, Int32(b.count), SQLITE_TRANSIENT_PTR)
                    }
                }
            }
        }
    }

    /// A read cursor over the current row.
    public struct Row {
        let stmt: OpaquePointer?

        public func isNull(_ i: Int) -> Bool { sqlite3_column_type(stmt, Int32(i)) == SQLITE_NULL }

        public func int(_ i: Int) -> Int64? {
            isNull(i) ? nil : sqlite3_column_int64(stmt, Int32(i))
        }

        public func double(_ i: Int) -> Double? {
            isNull(i) ? nil : sqlite3_column_double(stmt, Int32(i))
        }

        /// Reads a BLOB column as little-endian UInt16 values (used for packed R-R intervals).
        public func uint16s(_ i: Int) -> [Int] {
            guard !isNull(i), let p = sqlite3_column_blob(stmt, Int32(i)) else { return [] }
            let n = Int(sqlite3_column_bytes(stmt, Int32(i))) / 2
            guard n > 0 else { return [] }
            let bytes = p.assumingMemoryBound(to: UInt8.self)
            var out = [Int]()
            out.reserveCapacity(n)
            for k in 0..<n {
                out.append(Int(bytes[2 * k]) | (Int(bytes[2 * k + 1]) << 8))
            }
            return out
        }

        /// Reads a BLOB column as raw bytes.
        public func bytes(_ i: Int) -> [UInt8] {
            guard !isNull(i), let p = sqlite3_column_blob(stmt, Int32(i)) else { return [] }
            let n = Int(sqlite3_column_bytes(stmt, Int32(i)))
            guard n > 0 else { return [] }
            return Array(UnsafeBufferPointer(start: p.assumingMemoryBound(to: UInt8.self), count: n))
        }

        public func text(_ i: Int) -> String? {
            guard !isNull(i), let c = sqlite3_column_text(stmt, Int32(i)) else { return nil }
            return String(cString: c)
        }
    }
}

public extension SQLValue {
    static func from(_ v: Int?) -> SQLValue { v.map { .int(Int64($0)) } ?? .null }
    static func from(_ v: Double?) -> SQLValue {
        guard let v, v.isFinite else { return .null }
        return .double(v)
    }
    static func from(_ v: String?) -> SQLValue { v.map { .text($0) } ?? .null }
    static func from(_ v: Bool) -> SQLValue { .int(v ? 1 : 0) }
}
