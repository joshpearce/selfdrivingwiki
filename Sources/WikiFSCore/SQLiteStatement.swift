import Foundation
import SQLite3

/// `SQLITE_TRANSIENT` tells SQLite to copy bound text/blob immediately. We must
/// NEVER use `SQLITE_STATIC` for Swift `String` bytes: the temporary buffer the
/// `String` exposes can be freed before `sqlite3_step`, leaving SQLite reading
/// freed memory. The transient destructor is `(sqlite3_destructor_type)(-1)`.
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Thin wrapper over a prepared `sqlite3_stmt`. One instance per distinct SQL
/// string; reused across calls via `reset()` (which clears bindings). Owned and
/// finalized by `SQLiteWikiStore`.
final class SQLiteStatement {
    private let db: OpaquePointer
    private(set) var handle: OpaquePointer?

    init(db: OpaquePointer, sql: String) throws {
        self.db = db
        let rc = sqlite3_prepare_v2(db, sql, -1, &handle, nil)
        guard rc == SQLITE_OK, handle != nil else {
            throw WikiStoreError.sqlite(code: rc, message: Self.message(db))
        }
    }

    deinit {
        sqlite3_finalize(handle)
    }

    /// Reset the statement for reuse and drop previous bindings.
    func reset() {
        sqlite3_reset(handle)
        sqlite3_clear_bindings(handle)
    }

    // MARK: - Binding (1-based indexes, per the SQLite C API)

    func bind(_ value: String, at index: Int32) throws {
        let rc = sqlite3_bind_text(handle, index, value, -1, SQLITE_TRANSIENT)
        try check(rc)
    }

    func bind(_ value: Double, at index: Int32) throws {
        try check(sqlite3_bind_double(handle, index, value))
    }

    func bind(_ value: Int64, at index: Int32) throws {
        try check(sqlite3_bind_int64(handle, index, value))
    }

    // MARK: - Stepping

    /// Step once. Returns true on `SQLITE_ROW`, false on `SQLITE_DONE`.
    func step() throws -> Bool {
        let rc = sqlite3_step(handle)
        switch rc {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw WikiStoreError.sqlite(code: rc, message: Self.message(db))
        }
    }

    // MARK: - Column readers (0-based)

    func text(at column: Int32) -> String {
        guard let c = sqlite3_column_text(handle, column) else { return "" }
        return String(cString: c)
    }

    func double(at column: Int32) -> Double {
        sqlite3_column_double(handle, column)
    }

    func int(at column: Int32) -> Int64 {
        sqlite3_column_int64(handle, column)
    }

    private func check(_ rc: Int32) throws {
        guard rc == SQLITE_OK else {
            throw WikiStoreError.sqlite(code: rc, message: Self.message(db))
        }
    }

    static func message(_ db: OpaquePointer?) -> String {
        guard let db, let msg = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: msg)
    }
}
