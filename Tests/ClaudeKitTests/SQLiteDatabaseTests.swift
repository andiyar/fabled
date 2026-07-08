import XCTest
@testable import ClaudeKit

final class SQLiteDatabaseTests: XCTestCase {

    private func makeDB() throws -> SQLiteDatabase {
        try SQLiteDatabase(path: ":memory:")
    }

    func testExecPrepareBindStepRoundTrip() throws {
        let db = try makeDB()
        try db.exec("CREATE TABLE t(name TEXT, count INTEGER, ratio REAL, blobless TEXT)")
        let insert = try db.prepare("INSERT INTO t(name, count, ratio, blobless) VALUES(?, ?, ?, ?)")
        try insert.bind(1, "wombat")
        try insert.bind(2, Int64(42))
        try insert.bind(3, 0.5)
        try insert.bindNull(4)
        XCTAssertFalse(try insert.step()) // DONE, no row

        let select = try db.prepare("SELECT name, count, ratio, blobless FROM t")
        XCTAssertTrue(try select.step())
        XCTAssertEqual(select.columnText(0), "wombat")
        XCTAssertEqual(select.columnInt64(1), 42)
        XCTAssertEqual(select.columnDouble(2), 0.5)
        XCTAssertTrue(select.columnIsNull(3))
        XCTAssertFalse(try select.step())
    }

    func testResetAndRebind() throws {
        let db = try makeDB()
        try db.exec("CREATE TABLE t(v TEXT)")
        let insert = try db.prepare("INSERT INTO t(v) VALUES(?)")
        for value in ["a", "b"] {
            try insert.reset()
            try insert.bind(1, value)
            try insert.step()
        }
        let count = try db.prepare("SELECT COUNT(*) FROM t")
        XCTAssertTrue(try count.step())
        XCTAssertEqual(count.columnInt64(0), 2)
    }

    func testLastInsertRowID() throws {
        let db = try makeDB()
        try db.exec("CREATE TABLE t(id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT)")
        try db.exec("INSERT INTO t(v) VALUES('x')")
        XCTAssertEqual(db.lastInsertRowID, 1)
        try db.exec("INSERT INTO t(v) VALUES('y')")
        XCTAssertEqual(db.lastInsertRowID, 2)
    }

    func testInvalidSQLThrowsWithMessage() throws {
        let db = try makeDB()
        XCTAssertThrowsError(try db.exec("NOT REAL SQL")) { error in
            guard let sqliteError = error as? SQLiteError else { return XCTFail() }
            XCTAssertFalse(sqliteError.message.isEmpty)
        }
        XCTAssertThrowsError(try db.prepare("SELECT * FROM missing_table"))
    }

    func testFileBackedDatabasePersists() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudekit-sqlite-\(UUID().uuidString).db").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let db = try SQLiteDatabase(path: path)
            try db.exec("CREATE TABLE t(v TEXT); INSERT INTO t(v) VALUES('persisted')")
        }
        let reopened = try SQLiteDatabase(path: path)
        let select = try reopened.prepare("SELECT v FROM t")
        XCTAssertTrue(try select.step())
        XCTAssertEqual(select.columnText(0), "persisted")
    }

    /// Guards the plan's core assumption: the macOS system SQLite has FTS5,
    /// supports explicit-rowid inserts, rowid range deletes, MATCH + snippet.
    func testFTS5EndToEnd() throws {
        let db = try makeDB()
        try db.exec("CREATE VIRTUAL TABLE lines USING fts5(text, tokenize='unicode61 remove_diacritics 2')")
        let insert = try db.prepare("INSERT INTO lines(rowid, text) VALUES(?, ?)")
        let rows: [(Int64, String)] = [
            ((1 << 32) | 1, "the quick brown fox"),
            ((1 << 32) | 2, "jumped over the lazy dog"),
            ((2 << 32) | 1, "a fox in another file"),
        ]
        for (rowid, text) in rows {
            try insert.reset()
            try insert.bind(1, rowid)
            try insert.bind(2, text)
            try insert.step()
        }

        let search = try db.prepare("""
            SELECT rowid, snippet(lines, 0, '[', ']', '…', 8)
            FROM lines WHERE lines MATCH ? ORDER BY rank
            """)
        try search.bind(1, "fox")
        var hits: [(Int64, String)] = []
        while try search.step() {
            hits.append((search.columnInt64(0), search.columnText(1)))
        }
        XCTAssertEqual(hits.count, 2)
        XCTAssertTrue(hits.allSatisfy { $0.1.contains("[fox]") })

        // Range-delete file 1's rows, as the incremental indexer will.
        let delete = try db.prepare("DELETE FROM lines WHERE rowid >= ? AND rowid < ?")
        try delete.bind(1, Int64(1) << 32)
        try delete.bind(2, Int64(2) << 32)
        try delete.step()

        try search.reset()
        try search.bind(1, "fox")
        var remaining: [Int64] = []
        while try search.step() { remaining.append(search.columnInt64(0)) }
        XCTAssertEqual(remaining, [(2 << 32) | 1])
    }

    func testFTS5PrefixQuery() throws {
        let db = try makeDB()
        try db.exec("CREATE VIRTUAL TABLE lines USING fts5(text)")
        try db.exec("INSERT INTO lines(rowid, text) VALUES(1, 'Auto-updating bundles from GitHub')")
        let search = try db.prepare("SELECT rowid FROM lines WHERE lines MATCH ?")
        try search.bind(1, "\"auto\"*")
        XCTAssertTrue(try search.step())
    }
}
