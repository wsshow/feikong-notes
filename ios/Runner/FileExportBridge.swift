import Flutter
import UIKit

/// Uses the Files export picker so completion means a copy was actually saved.
final class FileExportBridge: NSObject, UIDocumentPickerDelegate, UIAdaptivePresentationControllerDelegate {
  private let channel: FlutterMethodChannel
  private weak var registrar: FlutterPluginRegistrar?
  private var pendingResult: FlutterResult?
  private var stagingDirectory: URL?
  private let queue = DispatchQueue(label: "fknotes.file-export", qos: .userInitiated)

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "fknotes/backup_export", binaryMessenger: registrar.messenger())
    super.init()
    // Clear copies left by a terminated process before preparing any new copy.
    queue.async {
      try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory
        .appendingPathComponent("fknotes-file-export", isDirectory: true))
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "saveFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.save(call.arguments, result: result)
    }
  }

  private func save(_ arguments: Any?, result: @escaping FlutterResult) {
    guard pendingResult == nil else {
      result(FlutterError(code: "backup_export_busy", message: "File picker already active", details: nil))
      return
    }
    guard let values = arguments as? [String: Any],
          let source = values["sourcePath"] as? String,
          let name = values["suggestedName"] as? String,
          !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\"),
          FileManager.default.fileExists(atPath: source) else {
      result(FlutterError(code: "invalid_backup_export", message: "Invalid export file", details: nil))
      return
    }
    pendingResult = result
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("fknotes-file-export", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    stagingDirectory = directory
    let copy = directory.appendingPathComponent(name)
    queue.async { [weak self] in
      do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source), to: copy)
        DispatchQueue.main.async {
          guard let self else {
            try? FileManager.default.removeItem(at: directory)
            return
          }
          self.present(copy)
        }
      } catch {
        try? FileManager.default.removeItem(at: directory)
        DispatchQueue.main.async {
          self?.finish(FlutterError(code: "backup_export_failed", message: "Cannot prepare export", details: nil))
        }
      }
    }
  }

  private func present(_ file: URL) {
    guard var presenter = registrar?.viewController, presenter.view.window != nil else {
      finish(FlutterError(code: "backup_export_unavailable", message: "No active view", details: nil))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    guard !presenter.isBeingDismissed,
          presenter.view.window?.windowScene?.activationState == .foregroundActive else {
      finish(FlutterError(code: "backup_export_unavailable", message: "App is not active", details: nil))
      return
    }
    let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
    picker.delegate = self
    picker.presentationController?.delegate = self
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    finish(!urls.isEmpty)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finish(false) }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { finish(false) }

  private func finish(_ value: Any) {
    let result = pendingResult
    pendingResult = nil
    if let directory = stagingDirectory { try? FileManager.default.removeItem(at: directory) }
    stagingDirectory = nil
    result?(value)
  }

  deinit {
    channel.setMethodCallHandler(nil)
    if let directory = stagingDirectory { try? FileManager.default.removeItem(at: directory) }
  }
}
