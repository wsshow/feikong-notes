import Foundation
import SQLite3

struct StoredReminder: Equatable {
  let id: String
  let at: Int64
}

/// Read-only projection: notification scheduling never reads note content.
enum ReminderStore {
  static func validID(_ value: String) -> Bool {
    UUID(uuidString: value)?.uuidString.lowercased() == value
  }

  static func read(path: String, id: String? = nil, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) throws -> [StoredReminder] {
    if let id, !validID(id) { throw Failure.invalidID }
    var db: OpaquePointer?
    guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
      if let db { sqlite3_close(db) }
      throw Failure.database
    }
    defer { sqlite3_close(db) }
    sqlite3_busy_timeout(db, 3000)
    var columns: OpaquePointer?
    guard sqlite3_prepare_v2(db, "PRAGMA table_info(notes)", -1, &columns, nil) == SQLITE_OK else { throw Failure.database }
    defer { sqlite3_finalize(columns) }
    var migrated = false
    while sqlite3_step(columns) == SQLITE_ROW {
      if let name = sqlite3_column_text(columns, 1), String(cString: name) == "reminder_at" { migrated = true }
    }
    guard migrated else { return [] }
    var statement: OpaquePointer?
    let condition = id == nil ? "reminder_at > ?" : "id = ? AND reminder_at IS NOT NULL"
    guard sqlite3_prepare_v2(db, "SELECT id, reminder_at FROM notes WHERE \(condition) ORDER BY reminder_at, id", -1, &statement, nil) == SQLITE_OK else { throw Failure.database }
    defer { sqlite3_finalize(statement) }
    if let id {
      sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
    } else { sqlite3_bind_int64(statement, 1, now) }
    var result: [StoredReminder] = []
    var status = sqlite3_step(statement)
    while status == SQLITE_ROW {
      if let bytes = sqlite3_column_text(statement, 0) {
        let value = String(cString: bytes)
        if validID(value) { result.append(StoredReminder(id: value, at: sqlite3_column_int64(statement, 1))) }
      }
      status = sqlite3_step(statement)
    }
    guard status == SQLITE_DONE else { throw Failure.database }
    return result
  }

  enum Failure: Error { case database, invalidID }
}
