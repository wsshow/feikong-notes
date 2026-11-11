import Flutter
import Foundation
import LiteRTLM

/// Channel state is confined to the main actor. Engine initialization runs on
/// the SDK actor; streaming yields to the UI and to cancellation requests.
final class LiteRtLmBridge: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private var engine: Engine?
  private var conversation: Conversation?
  private var activeRequest: Int?
  private var canceled = false
  private var channel: FlutterMethodChannel!
  private var events: FlutterEventChannel!

  init(messenger: FlutterBinaryMessenger) {
    super.init()
    events = FlutterEventChannel(name: "fknotes/litert_lm_events", binaryMessenger: messenger)
    events.setStreamHandler(self)
    channel = FlutterMethodChannel(name: "fknotes/litert_lm", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    canceled = true
    try? conversation?.cancel()
    sink = nil
    return nil
  }

  private func emit(_ id: Int, _ type: String, _ data: String = "") {
    sink?(["requestId": id, "type": type, "data": data])
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["requestId"] as? Int else {
      result(false)
      return
    }
    if call.method == "cancel" {
      if activeRequest == id {
        canceled = true
        try? conversation?.cancel()
      }
      result(true)
      return
    }
    guard ["load", "generate", "unload"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard activeRequest == nil, sink != nil else { result(false); return }
    activeRequest = id
    canceled = false
    result(true)
    Task { @MainActor in
      do {
        switch call.method {
        case "load":
          self.engine = nil
          guard let path = args["modelPath"] as? String else { throw BridgeFailure.invalidInput }
          let model = try self.managedFile(path, directories: ["models"])
          let cpu = args["backend"] as? String == "cpu"
          let backend: Backend = cpu ? .cpu(threadCount: args["threads"] as? Int) : .gpu
          let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("litert-lm")
            .appendingPathComponent(model.deletingLastPathComponent().lastPathComponent)
          try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
          let config = try EngineConfig(
            modelPath: model.path, backend: backend,
            visionBackend: args["imageInput"] as? Bool == true ? backend : nil,
            audioBackend: args["audioInput"] as? Bool == true ? .cpu() : nil,
            maxNumTokens: args["contextTokens"] as? Int, cacheDir: cache.path)
          let engine = Engine(engineConfig: config)
          try await engine.initialize()
          if self.canceled { self.emit(id, "canceled") }
          else { self.engine = engine; self.emit(id, "loaded", cpu ? "cpu" : "metal") }
        case "generate":
          try await self.generate(id, args)
        default:
          self.conversation = nil
          self.engine = nil
          self.emit(id, "unloaded")
        }
      } catch {
        // Native errors can contain note text or sandbox paths. Do not send
        // those to diagnostics; the Dart layer retains a useful operation code.
        self.emit(id, self.canceled ? "canceled" : "error", self.canceled ? "" : "litert_\(call.method)_failed")
      }
      self.conversation = nil
      self.activeRequest = nil
    }
  }

  @MainActor private func generate(_ id: Int, _ args: [String: Any]) async throws {
    guard let engine, let raw = args["messages"] as? [[String: Any]],
          raw.last?["role"] as? String == "user" else { throw BridgeFailure.invalidInput }
    let system = raw.filter { $0["role"] as? String == "system" }
      .compactMap { $0["content"] as? String }.joined(separator: "\n\n")
    let messages = try raw.filter { $0["role"] as? String != "system" }.map(message)
    guard let last = messages.last else { throw BridgeFailure.invalidInput }
    let config = ConversationConfig(
      systemMessage: system.isEmpty ? nil : Message(system, role: .system),
      initialMessages: Array(messages.dropLast()),
      samplerConfig: try SamplerConfig(
        topK: args["topK"] as? Int ?? 40,
        topP: (args["topP"] as? NSNumber)?.floatValue ?? 0.9,
        temperature: (args["temperature"] as? NSNumber)?.floatValue ?? 0.7))
    let conversation = try await engine.createConversation(with: config)
    self.conversation = conversation
    if canceled { emit(id, "canceled"); return }
    for try await chunk in conversation.sendMessageStream(last) {
      if canceled { try? conversation.cancel() }
      else if !chunk.toString.isEmpty { emit(id, "textDelta", chunk.toString) }
    }
    if canceled { emit(id, "canceled"); return }
    var metrics: [String: Any] = [:]
    if let stats = try? conversation.getBenchmarkInfo() {
      metrics = ["promptTokens": stats.lastPrefillTokenCount,
                 "generatedTokens": stats.lastDecodeTokenCount,
                 "prefillTokensPerSecond": stats.lastPrefillTokensPerSecond,
                 "decodeTokensPerSecond": stats.lastDecodeTokensPerSecond]
    }
    let data = try JSONSerialization.data(withJSONObject: metrics)
    emit(id, "completed", String(decoding: data, as: UTF8.self))
  }

  private func message(_ raw: [String: Any]) throws -> Message {
    let role: Role
    switch raw["role"] as? String {
    case "user": role = .user
    case "assistant": role = .model
    default: throw BridgeFailure.invalidInput
    }
    var contents: [Content] = [.text(raw["content"] as? String ?? "")]
    for attachment in raw["attachments"] as? [[String: Any]] ?? [] {
      guard let path = attachment["path"] as? String,
            let mime = attachment["mimeType"] as? String else { throw BridgeFailure.invalidInput }
      let file = try managedFile(path, directories: ["notes", "assistant"])
      if mime.hasPrefix("image/") { contents.append(.imageFile(file.path)) }
      else if mime.hasPrefix("audio/") { contents.append(.audioFile(file.path)) }
      else { throw BridgeFailure.invalidInput }
    }
    return Message(contents: contents, role: role)
  }

  private func managedFile(_ path: String, directories: [String]) throws -> URL {
    let file = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .resolvingSymlinksInPath()
    guard directories.contains(where: { file.path.hasPrefix(root.appendingPathComponent($0).path + "/") }),
          try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
      throw BridgeFailure.invalidInput
    }
    return file
  }

  private enum BridgeFailure: Error { case invalidInput }
}
