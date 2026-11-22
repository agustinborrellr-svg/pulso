import XCTest
@testable import PulsoStore

final class TransactionTests: XCTestCase {
    private struct Boom: Error {}

    private func count(_ c: SQLiteConnection) throws -> Int {
        try c.query("SELECT COUNT(*) FROM t") { Int($0.int(0) ?? 0) }.first ?? 0
    }

    func testANestedTransactionIsASavepoint() throws {
        let path = NSTemporaryDirectory() + "tx-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let c = try SQLiteConnection(path: path)
        try c.execute("CREATE TABLE t (v INTEGER);")
        // Inner failure rolls back only the inner part; the outer one commits.
        try c.transaction {
            try c.execute("INSERT INTO t VALUES (1);")
            XCTAssertThrowsError(try c.transaction { try c.execute("INSERT INTO t VALUES (2);"); throw Boom() })
            try c.transaction { try c.execute("INSERT INTO t VALUES (3);") }
        }
        XCTAssertEqual(try count(c), 2)
        // Outer failure rolls back everything, inner commits included.
        XCTAssertThrowsError(try c.transaction {
            try c.transaction { try c.execute("INSERT INTO t VALUES (4);") }
            throw Boom()
        })
        XCTAssertEqual(try count(c), 2)
        // And the connection is usable afterwards.
        try c.transaction { try c.execute("INSERT INTO t VALUES (5);") }
        XCTAssertEqual(try count(c), 3)
    }
}
