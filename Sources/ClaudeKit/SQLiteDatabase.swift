import Foundation
import SQLite3

/// sqlite3_bind_text needs a destructor sentinel telling SQLite to copy the
/// buffer; the C macro SQLITE_TRANSIENT (-1) doesn't import into Swift.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct SQLiteError: Error, Sendable, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

/// Minimal wrapper over the system SQLite3 C API — open/exec/prepare/bind/
/// step/columns, nothing else. NOT thread-safe: confine each instance to a
/// single actor (SearchIndex owns one). Internal by design; the public
/// surface of ClaudeKit is SearchIndex.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(path)"
            sqlite3_close_v2(db)
            throw SQLiteError(code: SQLITE_CANTOPEN, message: message)
        }
        self.handle = db
    }

    deinit {
        // close_v2 defers the close until outstanding statements finalize,
        // so Statement deinit order doesn't matter.
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }

    func exec(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "exec failed"
            sqlite3_free(errorMessage)
            throw SQLiteError(code: sqlite3_errcode(handle), message: message)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw SQLiteError(
                code: sqlite3_errcode(handle),
                message: String(cString: sqlite3_errmsg(handle)))
        }
        return Statement(statement: statement, database: handle)
    }

    final class Statement {
        private let statement: OpaquePointer
        private let database: OpaquePointer?

        init(statement: OpaquePointer, database: OpaquePointer?) {
            self.statement = statement
            self.database = database
        }

        deinit { sqlite3_finalize(statement) }

        private func check(_ code: Int32) throws {
            guard code == SQLITE_OK else {
                throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
            }
        }

        func bind(_ index: Int32, _ value: String) throws {
            try check(sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT))
        }
        func bind(_ index: Int32, _ value: Int64) throws {
            try check(sqlite3_bind_int64(statement, index, value))
        }
        func bind(_ index: Int32, _ value: Double) throws {
            try check(sqlite3_bind_double(statement, index, value))
        }
        func bindNull(_ index: Int32) throws {
            try check(sqlite3_bind_null(statement, index))
        }

        /// Advances one row. Returns true while a row is available, false at DONE.
        @discardableResult
        func step() throws -> Bool {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: return true
            case SQLITE_DONE: return false
            case let code:
                throw SQLiteError(code: code, message: String(cString: sqlite3_errmsg(database)))
            }
        }

        /// Rewinds for re-execution. Bindings survive a reset — rebind anyway
        /// when looping, for clarity.
        func reset() throws {
            try check(sqlite3_reset(statement))
        }

        func columnText(_ index: Int32) -> String {
            sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
        }
        func columnInt64(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
        func columnDouble(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
        func columnIsNull(_ index: Int32) -> Bool {
            sqlite3_column_type(statement, index) == SQLITE_NULL
        }
    }
}
