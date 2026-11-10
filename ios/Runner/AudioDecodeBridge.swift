import Flutter
import Foundation

final class AudioDecodeBridge {
  private let channel: FlutterMethodChannel
  // Accessed only on the platform (main) thread. Tokens are thread-safe.
  private var jobs: [String: AudioDecodeCancellation] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "fknotes/audio_decode", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "decodeToWav" || call.method == "cancel" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let output = arguments["outputPath"] as? String, !output.isEmpty else {
      result(FlutterError(code: "invalid_audio", message: "Missing output path", details: nil))
      return
    }
    if call.method == "cancel" {
      jobs[output]?.cancel()
      result(nil)
      return
    }
    guard let source = arguments["sourcePath"] as? String, !source.isEmpty else {
      result(FlutterError(code: "invalid_audio", message: "Missing source path", details: nil))
      return
    }
    guard jobs[output] == nil else {
      result(FlutterError(code: "audio_decode_busy", message: "Decoder already active", details: nil))
      return
    }
    let cancellation = AudioDecodeCancellation()
    jobs[output] = cancellation
    Task.detached(priority: .userInitiated) { [weak self] in
      let response: Any
      do {
        try await AudioFileDecoder.decode(
          source: URL(fileURLWithPath: source), destination: URL(fileURLWithPath: output),
          cancellation: cancellation)
        response = output
      } catch is CancellationError {
        response = FlutterError(code: "cancelled", message: "Audio decode cancelled", details: nil)
      } catch {
        // Do not return filesystem paths or decoder diagnostics to the UI.
        response = FlutterError(code: "audio_decode_failed", message: "Cannot decode audio", details: nil)
      }
      DispatchQueue.main.async {
        self?.jobs.removeValue(forKey: output)
        result(response)
      }
    }
  }

  deinit {
    for cancellation in jobs.values { cancellation.cancel() }
    channel.setMethodCallHandler(nil)
  }
}
