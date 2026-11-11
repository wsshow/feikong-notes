import Social
import UniformTypeIdentifiers

final class ShareViewController: SLComposeServiceViewController {
  private var task: Task<Void, Never>?
  private var draft: ShareInbox.Draft?

  override func viewDidLoad() {
    super.viewDidLoad()
    title = NativeStrings.text("share.title")
    placeholder = NativeStrings.text("share.placeholder")
  }

  override func isContentValid() -> Bool { (contentText ?? "").utf16.count <= 100000 && task == nil }

  override func didSelectPost() {
    guard task == nil else { return }
    let extraText = contentText ?? ""
    let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
    task = Task { @MainActor in
      do {
        let draft = try ShareInbox.applicationInbox().begin()
        self.draft = draft
        let providers = items.flatMap { $0.attachments ?? [] }
        guard providers.count <= 20 else { throw ShareInbox.Failure.tooLarge }
        if !extraText.isEmpty { try draft.appendText(extraText) }
        for provider in providers {
          try Task.checkCancellation()
          try await self.receive(provider, into: draft)
        }
        if providers.isEmpty {
          for item in items {
            if let text = item.attributedContentText?.string, text != extraText { try draft.appendText(text) }
          }
        }
        try Task.checkCancellation()
        try draft.commit(title: "")
        self.draft = nil
        // No unsupported attempt to launch the containing app from an extension.
        let alert = UIAlertController(title: NativeStrings.text("share.saved"),
                                      message: NativeStrings.text("share.openApp"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeStrings.text("share.done"), style: .default) { _ in
          self.extensionContext?.completeRequest(returningItems: nil)
        })
        self.present(alert, animated: true)
      } catch {
        self.draft?.discard()
        self.draft = nil
        guard !Task.isCancelled else { return }
        let key: String
        switch error {
        case ShareInbox.Failure.full: key = "share.full"
        case ShareInbox.Failure.tooLarge: key = "share.tooLarge"
        default: key = "share.failed"
        }
        let alert = UIAlertController(title: NativeStrings.text("share.failedTitle"),
                                      message: NativeStrings.text(key), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NativeStrings.text("share.done"), style: .default) { _ in
          self.extensionContext?.cancelRequest(withError: NSError(domain: "fknotes.share", code: 1))
        })
        self.present(alert, animated: true)
      }
    }
  }

  override func didSelectCancel() {
    draft?.cancel()
    task?.cancel()
    extensionContext?.cancelRequest(withError: NSError(domain: "fknotes.share", code: NSUserCancelledError))
  }

  private func receive(_ provider: NSItemProvider, into draft: ShareInbox.Draft) async throws {
    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
      let item = try await item(provider, type: UTType.fileURL.identifier)
      guard let url = item as? URL else { throw ShareInbox.Failure.invalid }
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let type = UTType(filenameExtension: url.pathExtension)
      let name = provider.suggestedName ?? url.lastPathComponent
      try await Task.detached {
        try draft.copy(url, name: name, extension: url.pathExtension,
                       mime: type?.preferredMIMEType ?? "application/octet-stream")
      }.value
    } else if let identifier = provider.registeredTypeIdentifiers.first(where: {
      guard let type = UTType($0) else { return false }
      return type.conforms(to: .data) && !type.conforms(to: .text) && !type.conforms(to: .url)
    }) {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        provider.loadFileRepresentation(forTypeIdentifier: identifier) { url, error in
          do {
            if let error { throw error }
            guard let url else { throw ShareInbox.Failure.invalid }
            let type = UTType(identifier)
            try draft.copy(url, name: provider.suggestedName ?? url.lastPathComponent,
                           extension: url.pathExtension.isEmpty ? (type?.preferredFilenameExtension ?? "") : url.pathExtension,
                           mime: type?.preferredMIMEType ?? "application/octet-stream")
            continuation.resume()
          } catch { continuation.resume(throwing: error) }
        }
      }
    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
      let item = try await item(provider, type: UTType.url.identifier)
      guard let url = item as? URL, !url.isFileURL else { throw ShareInbox.Failure.invalid }
      try draft.appendText(url.absoluteString)
    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
      let item = try await item(provider, type: UTType.plainText.identifier)
      guard let text = item as? String else { throw ShareInbox.Failure.invalid }
      try draft.appendText(text)
    } else { throw ShareInbox.Failure.invalid }
  }

  private func item(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
    try await withCheckedThrowingContinuation { continuation in
      provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
        if let error { continuation.resume(throwing: error) }
        else if let item { continuation.resume(returning: item) }
        else { continuation.resume(throwing: ShareInbox.Failure.invalid) }
      }
    }
  }
}
