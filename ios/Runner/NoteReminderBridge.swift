import Flutter
import UserNotifications

final class NoteReminderBridge {
  static let shared = NoteReminderBridge()
  private let center = UNUserNotificationCenter.current()
  private let defaults = UserDefaults.standard
  private let prefix = "fknotes.reminder."
  private var channel: FlutterMethodChannel?
  private var tail: Task<Void, Never>?
  private var databasePath: String?
  private var suspended = false

  func attach(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "fknotes/note_reminders", binaryMessenger: messenger)
    channel?.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      // Serialize across await points (permission requests and OS scheduling).
      let previous = self.tail
      self.tail = Task { @MainActor in
        await previous?.value
        do { result(try await self.handle(call)) }
        catch LimitReached.capacity { result(FlutterError(code: "reminder_limit", message: nil, details: nil)) }
        catch { result(FlutterError(code: "reminder_failed", message: nil, details: nil)) }
      }
    }
  }

  private func handle(_ call: FlutterMethodCall) async throws -> Any? {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "initialize":
      guard let path = args["databasePath"] as? String else { throw ReminderStore.Failure.database }
      let file = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
      guard file.path.hasPrefix(root.path + "/"), file.lastPathComponent == "fknotes.db" else { throw ReminderStore.Failure.database }
      databasePath = file.path
      suspended = false
      try await synchronize()
      return nil
    case "requestAccess":
      let settings = await center.notificationSettings()
      if settings.authorizationStatus == .notDetermined {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
      }
      return await allowed() ? "ready" : "notificationsDisabled"
    case "syncNote":
      guard let id = args["id"] as? String, ReminderStore.validID(id) else { throw ReminderStore.Failure.invalidID }
      return try await syncNote(id)
    case "synchronize": try await synchronize(); return nil
    case "suspend":
      suspended = true
      let pending = await center.pendingNotificationRequests()
      center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(prefix) }.map(\.identifier))
      let delivered = await center.deliveredNotifications()
      center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter { $0.hasPrefix(prefix) })
      defaults.removeObject(forKey: "fknotes.pendingReminder")
      return nil
    case "takePendingNote":
      guard !suspended else { return nil }
      let value = defaults.dictionary(forKey: "fknotes.pendingReminder")
      defaults.removeObject(forKey: "fknotes.pendingReminder")
      guard let id = value?["id"] as? String, let at = value?["at"] as? NSNumber,
            let path = databasePath, let note = try ReminderStore.read(path: path, id: id).first,
            note.at == at.int64Value else { return nil }
      return id
    default: return FlutterMethodNotImplemented
    }
  }

  private func allowed() async -> Bool {
    let settings = await center.notificationSettings()
    return [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
  }

  private func syncNote(_ id: String) async throws -> Bool {
    guard !suspended, let path = databasePath else { return false }
    let identifier = prefix + id
    center.removeDeliveredNotifications(withIdentifiers: [identifier])
    guard let note = try ReminderStore.read(path: path, id: id).first,
          note.at > Int64(Date().timeIntervalSince1970 * 1000) else {
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      return false
    }
    guard await allowed() else {
      center.removePendingNotificationRequests(withIdentifiers: [identifier])
      return false
    }
    let pending = await center.pendingNotificationRequests()
    if pending.count >= 64 && !pending.contains(where: { $0.identifier == identifier }) { throw LimitReached.capacity }
    try await schedule(note)
    return true
  }

  private func synchronize() async throws {
    guard !suspended, let path = databasePath else { return }
    let notes = try ReminderStore.read(path: path)
    let pending = await center.pendingNotificationRequests()
    let foreignCount = pending.filter { !$0.identifier.hasPrefix(prefix) }.count
    let selected = Array(notes.prefix(max(0, 64 - foreignCount)))
    let wanted = Set(selected.map { prefix + $0.id })
    center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(prefix) && !wanted.contains($0) })
    guard await allowed() else { return }
    for note in selected { try await schedule(note) }
  }

  private func schedule(_ note: StoredReminder) async throws {
    let content = UNMutableNotificationContent()
    content.title = NSLocalizedString("reminder.title", comment: "Reminder title")
    content.body = NSLocalizedString("reminder.body", comment: "Generic reminder, never note content")
    content.sound = .default
    content.userInfo = ["id": note.id, "at": note.at]
    let date = Date(timeIntervalSince1970: Double(note.at) / 1000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    components.timeZone = calendar.timeZone
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    try await center.add(UNNotificationRequest(identifier: prefix + note.id, content: content, trigger: trigger))
  }

  func owns(_ notification: UNNotification) -> Bool {
    notification.request.identifier.hasPrefix(prefix)
  }

  func opened(_ response: UNNotificationResponse) {
    guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
          let id = response.notification.request.content.userInfo["id"] as? String,
          ReminderStore.validID(id),
          let at = response.notification.request.content.userInfo["at"] as? NSNumber else { return }
    defaults.set(["id": id, "at": at], forKey: "fknotes.pendingReminder")
    channel?.invokeMethod("reminderOpened", arguments: nil)
  }

  private enum LimitReached: Error { case capacity }
}
