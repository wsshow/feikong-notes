import Foundation

@main struct ShareInboxTest {
  static func main() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let inbox = try ShareInbox(root: root.appendingPathComponent("inbox"))
    let source = root.appendingPathComponent("sample.bin")
    try Data([1, 2, 3]).write(to: source)
    let draft = try inbox.begin()
    try draft.appendText("synthetic share")
    try draft.copy(source, name: "../../display only.bin", extension: "../../bad", mime: "application/octet-stream")
    let before = try inbox.peek()
    precondition(before == nil, "Partial copies must be invisible")
    try draft.commit(title: "test")
    let payload = try inbox.peek()!
    precondition(payload["id"] as? String == draft.id)
    precondition(payload["text"] as? String == "synthetic share")
    let files = payload["files"] as! [[String: Any]]
    let name = files[0]["fileName"] as! String
    precondition(ShareInbox.validID(name))
    precondition(files[0]["byteLength"] as? Int == 3)
    do { try inbox.finish("../escape"); fatalError("Traversal accepted") }
    catch ShareInbox.Failure.invalid {}
    let stored = inbox.root.appendingPathComponent(draft.id).appendingPathComponent(name)
    try FileManager.default.removeItem(at: stored)
    try FileManager.default.createSymbolicLink(at: stored, withDestinationURL: source)
    let invalid = try inbox.peek()
    precondition(invalid?["error"] as? String == "invalid_share")
    try inbox.finish(draft.id)
    precondition(FileManager.default.fileExists(atPath: source.path), "Discard must not follow symlinks")
    try inbox.finish(draft.id) // Idempotent acknowledgement.
    let canceled = try inbox.begin()
    canceled.cancel()
    do { try canceled.appendText("discard"); fatalError("Cancellation ignored") }
    catch ShareInbox.Failure.canceled {}
    canceled.discard()
    let tooLarge = try inbox.begin()
    do { try tooLarge.appendText(String(repeating: "😀", count: 50001)); fatalError("UTF-16 bound ignored") }
    catch ShareInbox.Failure.tooLarge {}
    tooLarge.discard()
    let oversized = try inbox.begin()
    let handle = try FileHandle(forWritingTo: source)
    try handle.truncate(atOffset: UInt64(ShareInbox.maximumFileBytes + 1))
    try handle.close()
    do { try oversized.copy(source, name: "large.bin", extension: "bin", mime: "application/octet-stream"); fatalError("File limit ignored") }
    catch ShareInbox.Failure.tooLarge {}
    oversized.discard()
    let drafts = try (0..<8).map { _ in try inbox.begin() }
    do { _ = try inbox.begin(); fatalError("Queue quota ignored") }
    catch ShareInbox.Failure.full {}
    for item in drafts { item.discard() }
    let empty = try inbox.peek()
    precondition(empty == nil)
    print("Share inbox: atomicity, quotas, cancellation, UTF-16 and traversal checks passed")
  }
}
