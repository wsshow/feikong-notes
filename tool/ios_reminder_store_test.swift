import Foundation
import SQLite3

@main struct ReminderStoreTest {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let path = root.appendingPathComponent("fknotes.db").path
    var db: OpaquePointer?
    precondition(sqlite3_open(path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    func sql(_ value: String) {
      precondition(sqlite3_exec(db, value, nil, nil, nil) == SQLITE_OK)
    }
    sql("CREATE TABLE notes (id TEXT PRIMARY KEY)")
    let oldSchema = try ReminderStore.read(path: path)
    precondition(oldSchema.isEmpty)
    sql("ALTER TABLE notes ADD COLUMN reminder_at INTEGER")
    let first = "00000000-0000-4000-8000-000000000001"
    let second = "00000000-0000-4000-8000-000000000002"
    sql("INSERT INTO notes VALUES ('\(first)', 2000), ('\(second)', 1000), ('invalid', 3000)")
    let future = try ReminderStore.read(path: path, now: 1500)
    precondition(future == [StoredReminder(id: first, at: 2000)])
    let past = try ReminderStore.read(path: path, id: second, now: 1500)
    precondition(past == [StoredReminder(id: second, at: 1000)])
    sql("UPDATE notes SET reminder_at=NULL WHERE id='\(first)'")
    let cleared = try ReminderStore.read(path: path, id: first)
    precondition(cleared.isEmpty)
    do {
      _ = try ReminderStore.read(path: path, id: "' OR 1=1 --")
      fatalError("invalid ID accepted")
    } catch ReminderStore.Failure.invalidID {}
    sql("DELETE FROM notes WHERE id='\(second)'")
    let deleted = try ReminderStore.read(path: path, id: second)
    precondition(deleted.isEmpty)
    print("Reminder read-only store: migration, ordering, removal and malformed IDs passed")
  }
}
