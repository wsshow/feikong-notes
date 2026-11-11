import Flutter
import UIKit
import UniformTypeIdentifiers

final class IncomingShareBridge: NSObject, UIDocumentInteractionControllerDelegate {
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private var document: UIDocumentInteractionController?
  private let queue = DispatchQueue(label: "fknotes.share-inbox")

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "fknotes/incoming_share", binaryMessenger: registrar.messenger())
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      if call.method == "openAttachment" { self.open(call.arguments, result: result); return }
      self.queue.async {
        do {
          let inbox = try ShareInbox.applicationInbox()
          let value: Any?
          switch call.method {
          case "peek": value = try inbox.peek()
          case "finish":
            guard let args = call.arguments as? [String: Any], let id = args["id"] as? String else { throw ShareInbox.Failure.invalid }
            try inbox.finish(id)
            value = nil
          default: value = FlutterMethodNotImplemented
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async { result(FlutterError(code: "share_inbox_unavailable", message: nil, details: nil)) }
        }
      }
    }
  }

  private func open(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let key = args["storageKey"] as? String,
          key.hasPrefix("notes/files/"), let presenter = registrar.viewController else {
      result(FlutterError(code: "invalid_attachment", message: nil, details: nil)); return
    }
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].resolvingSymlinksInPath()
    let file = root.appendingPathComponent(key).standardizedFileURL.resolvingSymlinksInPath()
    guard file.path.hasPrefix(root.appendingPathComponent("notes/files").path + "/"),
          (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
      result(FlutterError(code: "invalid_attachment", message: nil, details: nil)); return
    }
    let controller = UIDocumentInteractionController(url: file)
    if let mime = args["mimeType"] as? String { controller.uti = UTType(mimeType: mime)?.identifier }
    controller.delegate = self
    document = controller
    if controller.presentPreview(animated: true) { result(nil); return }
    let bounds = presenter.view.bounds
    let anchor = CGRect(x: bounds.midX, y: bounds.midY, width: 1, height: 1)
    if controller.presentOptionsMenu(from: anchor, in: presenter.view, animated: true) { result(nil) }
    else { document = nil; result(FlutterError(code: "attachment_unavailable", message: nil, details: nil)) }
  }

  func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
    var presenter = registrar.viewController!
    while let next = presenter.presentedViewController { presenter = next }
    return presenter
  }

  func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) { document = nil }
}
