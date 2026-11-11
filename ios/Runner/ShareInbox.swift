import Foundation
import Darwin

/// The extension can only write this bounded inbox; it has no access to the
/// main application's database or Keychain. A manifest becomes visible atomically.
final class ShareInbox {
  static let maximumFileBytes = 100 * 1024 * 1024
  static let maximumTotalBytes = 200 * 1024 * 1024
  let root: URL

  init(root: URL) throws {
    self.root = root.standardizedFileURL
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw Failure.invalid }
    var url = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
    #if os(iOS)
    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: root.path)
    #endif
  }

  static func applicationInbox() throws -> ShareInbox {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "FKNotesAppGroup") as? String,
          let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw Failure.unavailable }
    return try ShareInbox(root: container.appendingPathComponent("incoming_shares").resolvingSymlinksInPath())
  }

  private func locked<T>(_ action: () throws -> T) throws -> T {
    let fd = open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw Failure.unavailable }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw Failure.unavailable }
    defer { flock(fd, LOCK_UN) }
    return try action()
  }

  func begin() throws -> Draft {
    try locked {
      let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey])
      var count = 0
      for entry in contents where entry.lastPathComponent != ".lock" {
        if entry.lastPathComponent.hasSuffix(".partial"),
           let date = try entry.resourceValues(forKeys: [.creationDateKey]).creationDate,
           Date().timeIntervalSince(date) > 3600 {
          try FileManager.default.removeItem(at: entry)
        } else { count += 1 }
      }
      guard count < 8 else { throw Failure.full }
      let id = UUID().uuidString.lowercased()
      let directory = root.appendingPathComponent(id + ".partial")
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
      return Draft(inbox: self, id: id, directory: directory)
    }
  }

  func peek() throws -> [String: Any]? {
    try locked {
      let directories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { Self.validID($0.lastPathComponent) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
      var candidates: [[String: Any]] = []
      for directory in directories {
        do { candidates.append(try read(directory)) }
        catch {
          // Keep a discardable entry so corruption does not permanently block
          // the queue or silently erase the user's pending share.
          candidates.append(["id": directory.lastPathComponent, "directory": directory.path,
                             "createdAt": 0, "title": "", "text": "", "files": [], "error": "invalid_share"])
        }
      }
      return candidates.min { ($0["createdAt"] as? Int64 ?? 0) < ($1["createdAt"] as? Int64 ?? 0) }
    }
  }

  private func read(_ directory: URL) throws -> [String: Any] {
    let directoryValues = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard directoryValues.isDirectory == true, directoryValues.isSymbolicLink != true else { throw Failure.invalid }
    let manifest = directory.appendingPathComponent("manifest.json")
    let values = try manifest.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
          (values.fileSize ?? Int.max) <= 512 * 1024 else { throw Failure.invalid }
    guard var payload = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any],
          payload["id"] as? String == directory.lastPathComponent,
          payload["createdAt"] is NSNumber,
          let title = payload["title"] as? String, title.utf16.count <= 500,
          let text = payload["text"] as? String, text.utf16.count <= 100000,
          let files = payload["files"] as? [[String: Any]], files.count <= 20 else { throw Failure.invalid }
    var total = 0
    for file in files {
      guard let name = file["fileName"] as? String,
            name.range(of: "^[0-9a-f-]{36}(\\.[a-z0-9]{1,10})?$", options: .regularExpression) != nil,
            let bytes = file["byteLength"] as? Int, bytes >= 0, bytes <= Self.maximumFileBytes,
            file["name"] is String, file["mimeType"] is String else { throw Failure.invalid }
      let source = directory.appendingPathComponent(name)
      let stat = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
      guard stat.isRegularFile == true, stat.isSymbolicLink != true, stat.fileSize == bytes else { throw Failure.invalid }
      total += bytes
    }
    guard total <= Self.maximumTotalBytes else { throw Failure.tooLarge }
    payload["directory"] = directory.path
    return payload
  }

  func finish(_ id: String) throws {
    guard Self.validID(id) else { throw Failure.invalid }
    try locked {
      let directory = root.appendingPathComponent(id)
      if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }
  }

  static func validID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }

  final class Draft {
    let id: String
    let directory: URL
    private let inbox: ShareInbox
    private let lock = NSLock()
    private var canceled = false
    private var total = 0
    private var files: [[String: Any]] = []
    private var text = ""
    fileprivate init(inbox: ShareInbox, id: String, directory: URL) {
      self.inbox = inbox; self.id = id; self.directory = directory
    }
    func cancel() { lock.lock(); canceled = true; lock.unlock() }
    private func checkCanceled() throws {
      lock.lock(); let value = canceled; lock.unlock()
      if value { throw Failure.canceled }
    }
    func appendText(_ value: String) throws {
      try checkCanceled()
      guard value.utf16.count + text.utf16.count + (text.isEmpty ? 0 : 2) <= 100000 else { throw Failure.tooLarge }
      if !text.isEmpty { text += "\n\n" }
      text += value
    }
    /// Called inside the item provider callback, before its temporary URL expires.
    func copy(_ source: URL, name: String, extension suffix: String, mime: String) throws {
      try checkCanceled()
      guard files.count < 20, source.isFileURL,
            try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw Failure.invalid }
      let safeSuffix = suffix.lowercased().range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) != nil ? suffix.lowercased() : ""
      let fileName = UUID().uuidString.lowercased() + (safeSuffix.isEmpty ? "" : "." + safeSuffix)
      let destination = directory.appendingPathComponent(fileName)
      guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw Failure.unavailable }
      let input = try FileHandle(forReadingFrom: source)
      let output = try FileHandle(forWritingTo: destination)
      defer { try? input.close(); try? output.close() }
      var bytes = 0
      while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
        try checkCanceled()
        bytes += chunk.count
        guard bytes <= ShareInbox.maximumFileBytes, total + bytes <= ShareInbox.maximumTotalBytes else { throw Failure.tooLarge }
        try output.write(contentsOf: chunk)
      }
      total += bytes
      files.append(["name": String(name.prefix(500)), "fileName": fileName, "mimeType": mime, "byteLength": bytes])
    }
    func commit(title: String) throws {
      try checkCanceled()
      guard !files.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            title.utf16.count <= 500 else { throw Failure.invalid }
      let payload: [String: Any] = ["id": id, "createdAt": Int64(Date().timeIntervalSince1970 * 1000),
                                   "title": title, "text": text, "files": files]
      try JSONSerialization.data(withJSONObject: payload).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
      try inbox.locked {
        try checkCanceled()
        try FileManager.default.moveItem(at: directory, to: inbox.root.appendingPathComponent(id))
      }
    }
    func discard() { try? FileManager.default.removeItem(at: directory) }
  }

  enum Failure: Error { case unavailable, invalid, full, tooLarge, canceled }
}
