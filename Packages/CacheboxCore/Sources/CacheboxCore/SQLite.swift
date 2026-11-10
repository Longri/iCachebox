import Foundation
import SQLite3

/// Error of the SQLite C API with its message.
public struct SQLiteError: LocalizedError, Sendable {
    public let code: Int32
    public let message: String
    public var errorDescription: String? { "SQLite \(code): \(message)" }
}

/// Thin wrapper around one SQLite connection. Not thread-safe: use a connection from one task at a time.
final class SQLiteConnection {
    private(set) var handle: OpaquePointer?

    init(url: URL, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let result = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_NOMUTEX, nil)
        guard result == SQLITE_OK else {
            let error = SQLiteError(code: result, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open")
            sqlite3_close(handle)
            throw error
        }
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var message: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &message)
        guard result == SQLITE_OK else {
            let text = message.map { String(cString: $0) } ?? "exec"
            sqlite3_free(message)
            throw SQLiteError(code: result, message: text)
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw lastError(result) }
        return Statement(statement, connection: self)
    }

    /// Runs `body` in a transaction; rolls back if it throws.
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var userVersion: Int {
        get { (try? prepare("PRAGMA user_version").first { $0.int(0) }) ?? 0 }
    }

    func lastError(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }

    var changes: Int { Int(sqlite3_changes(handle)) }

    /// A prepared statement. Parameters are 1-based like in SQLite, columns 0-based.
    final class Statement {
        private let statement: OpaquePointer
        private let connection: SQLiteConnection

        fileprivate init(_ statement: OpaquePointer, connection: SQLiteConnection) {
            self.statement = statement
            self.connection = connection
        }

        deinit { sqlite3_finalize(statement) }

        private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        @discardableResult
        func bind(_ values: [Any?]) -> Statement {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            for (offset, value) in values.enumerated() {
                let index = Int32(offset + 1)
                switch value {
                case nil: sqlite3_bind_null(statement, index)
                case let v as Int: sqlite3_bind_int64(statement, index, Int64(v))
                case let v as Int64: sqlite3_bind_int64(statement, index, v)
                case let v as Bool: sqlite3_bind_int(statement, index, v ? 1 : 0)
                case let v as Double: sqlite3_bind_double(statement, index, v)
                case let v as String: sqlite3_bind_text(statement, index, v, -1, Self.transient)
                case let v as Date: sqlite3_bind_double(statement, index, v.timeIntervalSince1970)
                default: sqlite3_bind_text(statement, index, "\(value!)", -1, Self.transient)
                }
            }
            return self
        }

        /// Executes a statement that returns no rows.
        func run(_ values: [Any?] = []) throws {
            bind(values)
            let result = sqlite3_step(statement)
            guard result == SQLITE_DONE || result == SQLITE_ROW else { throw connection.lastError(result) }
        }

        /// Steps through all rows.
        func rows<T>(_ values: [Any?] = [], _ map: (Row) throws -> T) throws -> [T] {
            bind(values)
            var result: [T] = []
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw connection.lastError(step) }
                result.append(try map(Row(statement: statement)))
            }
            return result
        }

        func first<T>(_ values: [Any?] = [], _ map: (Row) throws -> T) throws -> T? {
            bind(values)
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return nil }
            guard step == SQLITE_ROW else { throw connection.lastError(step) }
            return try map(Row(statement: statement))
        }
    }

    struct Row {
        let statement: OpaquePointer

        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(statement, i) == SQLITE_NULL }
        func int(_ i: Int32) -> Int { Int(sqlite3_column_int64(statement, i)) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(statement, i) }
        func bool(_ i: Int32) -> Bool { sqlite3_column_int(statement, i) != 0 }
        func string(_ i: Int32) -> String {
            sqlite3_column_text(statement, i).map { String(cString: $0) } ?? ""
        }
        func optionalString(_ i: Int32) -> String? { isNull(i) ? nil : string(i) }
        func optionalDouble(_ i: Int32) -> Double? { isNull(i) ? nil : double(i) }
        func date(_ i: Int32) -> Date? { isNull(i) ? nil : Date(timeIntervalSince1970: double(i)) }
    }
}
