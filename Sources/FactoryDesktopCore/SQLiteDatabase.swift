import CSQLite
import Foundation

public enum SQLiteValue {
    case text(String?)
    case int(Int)
    case double(Double)
    case null
}

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    public let url: URL

    public init(url: URL) throws {
        self.url = url
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        if sqlite3_open_v2(url.path, &handle, flags, nil) != SQLITE_OK {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
            throw FactoryError.databaseOpenFailed(message)
        }
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        sqlite3_close(handle)
    }

    public func execute(_ sql: String, binds: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw FactoryError.databaseExecutionFailed(lastErrorMessage)
        }
        try bind(values: binds, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw FactoryError.databaseExecutionFailed(lastErrorMessage)
        }
    }

    public func executeScript(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(handle, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? lastErrorMessage
            sqlite3_free(error)
            throw FactoryError.databaseExecutionFailed(message)
        }
    }

    public func query(_ sql: String, binds: [SQLiteValue] = []) throws -> [[String: String?]] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }

        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw FactoryError.databaseQueryFailed(lastErrorMessage)
        }
        try bind(values: binds, to: statement)

        var rows: [[String: String?]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String?] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                if sqlite3_column_type(statement, column) == SQLITE_NULL {
                    row[name] = nil
                } else if let text = sqlite3_column_text(statement, column) {
                    row[name] = String(cString: text)
                } else {
                    row[name] = nil
                }
            }
            rows.append(row)
        }
        return rows
    }

    public func transaction(_ body: () throws -> Void) throws {
        try executeScript("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try executeScript("COMMIT;")
        } catch {
            try? executeScript("ROLLBACK;")
            throw error
        }
    }

    private var lastErrorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown SQLite error"
    }

    private func bind(values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (index, value) in values.enumerated() {
            let sqliteIndex = Int32(index + 1)
            let result: Int32
            switch value {
            case .text(let text):
                if let text {
                    result = sqlite3_bind_text(statement, sqliteIndex, text, -1, SQLITE_TRANSIENT)
                } else {
                    result = sqlite3_bind_null(statement, sqliteIndex)
                }
            case .int(let value):
                result = sqlite3_bind_int64(statement, sqliteIndex, sqlite3_int64(value))
            case .double(let value):
                result = sqlite3_bind_double(statement, sqliteIndex, value)
            case .null:
                result = sqlite3_bind_null(statement, sqliteIndex)
            }
            if result != SQLITE_OK {
                throw FactoryError.databaseExecutionFailed(lastErrorMessage)
            }
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
