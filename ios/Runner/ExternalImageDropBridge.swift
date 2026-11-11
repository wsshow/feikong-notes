import Flutter
import UIKit
import UniformTypeIdentifiers

/// iOS has no desktop_drop implementation. Keep the existing channel contract
/// (physical coordinates and owned cache files), so Delta insertion stays in Dart.
final class ExternalImageDropBridge: NSObject, UIDropInteractionDelegate {
  private let channel: FlutterMethodChannel
  private weak var view: UIView?
  private let cache: URL
  private var enabled = false
  private var copying = false

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(name: "fknotes/external_image_drop", binaryMessenger: registrar.messenger())
    cache = FileManager.default.temporaryDirectory.appendingPathComponent("external_image_drop")
    super.init()
    // Each launch removes abandoned copies; no user attachments live here.
    try? FileManager.default.removeItem(at: cache)
    try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
    if let view = registrar.viewController?.view {
      self.view = view
      view.addInteraction(UIDropInteraction(delegate: self))
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "setEnabled": self.enabled = call.arguments as? Bool == true; result(nil)
      case "deleteTemporaryFiles":
        for path in call.arguments as? [String] ?? [] {
          let file = URL(fileURLWithPath: path).standardizedFileURL
          // Only direct, app-generated cache children may be acknowledged.
          if file.deletingLastPathComponent().path == self.cache.path {
            try? FileManager.default.removeItem(at: file)
          }
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
    enabled && !copying && session.localDragSession == nil && session.hasItemsConforming(toTypeIdentifiers: [UTType.image.identifier])
  }

  private func position(_ session: UIDropSession) -> [Double] {
    guard let view else { return [0, 0] }
    let point = session.location(in: view)
    let scale = view.window?.screen.scale ?? 1
    return [Double(point.x * scale), Double(point.y * scale)]
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnter session: UIDropSession) {
    channel.invokeMethod("entered", arguments: ["position": position(session)])
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
    channel.invokeMethod("updated", arguments: ["position": position(session)])
    return UIDropProposal(operation: enabled && !copying ? .copy : .cancel)
  }

  func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
    channel.invokeMethod("exited", arguments: ["position": position(session)])
  }

  func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
    guard enabled && !copying else { return }
    copying = true
    let point = position(session)
    let providers = session.items.map(\.itemProvider)
    Task { @MainActor in
      var files: [[String: Any]] = []
      var rejected = max(0, providers.count - 10)
      for provider in providers.prefix(10) {
        do { files.append(try await copy(provider)) }
        catch { rejected += 1 }
      }
      copying = false
      if enabled {
        channel.invokeMethod("done", arguments: ["position": point, "files": files, "rejectedCount": rejected])
      } else {
        for file in files { if let path = file["path"] as? String { try? FileManager.default.removeItem(atPath: path) } }
      }
    }
  }

  private func copy(_ provider: NSItemProvider) async throws -> [String: Any] {
    guard let identifier = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .image) == true }) else { throw CopyFailure.invalid }
    return try await withCheckedThrowingContinuation { continuation in
      provider.loadFileRepresentation(forTypeIdentifier: identifier) { [cache] source, error in
        var destination: URL?
        do {
          if let error { throw error }
          guard let source,
                try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw CopyFailure.invalid }
          let type = UTType(identifier)
          let suffix = type?.preferredFilenameExtension ?? "img"
          let file = cache.appendingPathComponent(UUID().uuidString.lowercased()).appendingPathExtension(suffix)
          destination = file
          guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CopyFailure.invalid }
          let input = try FileHandle(forReadingFrom: source)
          let output = try FileHandle(forWritingTo: file)
          defer { try? input.close(); try? output.close() }
          var bytes = 0
          while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            bytes += chunk.count
            guard bytes <= 20 * 1024 * 1024 else { throw CopyFailure.invalid }
            try output.write(contentsOf: chunk)
          }
          guard bytes > 0 else { throw CopyFailure.invalid }
          continuation.resume(returning: ["path": file.path, "name": provider.suggestedName ?? file.lastPathComponent,
                                          "mimeType": type?.preferredMIMEType ?? "image/unknown", "byteLength": bytes])
        } catch {
          if let destination { try? FileManager.default.removeItem(at: destination) }
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private enum CopyFailure: Error { case invalid }
}
