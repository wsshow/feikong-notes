import AVFoundation
import Foundation

final class AudioDecodeCancellation: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false

  func cancel() {
    lock.lock()
    cancelled = true
    lock.unlock()
  }

  func check() throws {
    lock.lock()
    let value = cancelled
    lock.unlock()
    if value { throw CancellationError() }
  }
}

/// Decodes in bounded chunks; the original recording is never modified.
enum AudioFileDecoder {
  static func decode(
    source: URL, destination: URL, cancellation: AudioDecodeCancellation
  ) async throws {
    guard source.resolvingSymlinksInPath() != destination.resolvingSymlinksInPath() else {
      throw failure("Source and destination must differ")
    }
    try cancellation.check()
    let asset = AVURLAsset(url: source)
    guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
      throw failure("No audio track")
    }
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ])
    output.alwaysCopiesSampleData = false
    guard reader.canAdd(output) else { throw failure("Unsupported audio track") }
    reader.add(output)
    defer { reader.cancelReading() }
    try cancellation.check()
    try FileManager.default.createDirectory(
      at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw failure("Cannot create temporary audio")
    }
    var succeeded = false
    defer {
      if !succeeded { try? FileManager.default.removeItem(at: destination) }
    }
    let file = try FileHandle(forWritingTo: destination)
    defer { try? file.close() }
    try file.write(contentsOf: Data(repeating: 0, count: 44))
    guard reader.startReading() else { throw reader.error ?? failure("Cannot decode audio") }
    var byteCount: UInt64 = 0
    while reader.status == .reading {
      try cancellation.check()
      let count: Int? = try autoreleasepool {
        guard let sample = output.copyNextSampleBuffer() else { return nil }
        guard let block = CMSampleBufferGetDataBuffer(sample) else {
          throw failure("Missing audio samples")
        }
        let length = CMBlockBufferGetDataLength(block)
        if length == 0 { return 0 }
        guard byteCount + UInt64(length) <= UInt64(UInt32.max) - 36 else {
          throw failure("Audio exceeds WAV size limit")
        }
        var bytes = Data(count: length)
        let status = bytes.withUnsafeMutableBytes { buffer in
          CMBlockBufferCopyDataBytes(
            block, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
        }
        guard status == kCMBlockBufferNoErr else { throw failure("Cannot read audio samples") }
        try file.write(contentsOf: bytes)
        return length
      }
      guard let count else { break }
      byteCount += UInt64(count)
    }
    try cancellation.check()
    guard reader.status == .completed, byteCount > 0 else {
      throw reader.error ?? failure("Incomplete or empty audio")
    }
    try file.seek(toOffset: 0)
    try file.write(contentsOf: header(byteCount: UInt32(byteCount)))
    try file.synchronize()
    succeeded = true
  }

  private static func header(byteCount: UInt32) -> Data {
    var data = Data()
    func text(_ value: String) { data.append(contentsOf: value.utf8) }
    func number<T: FixedWidthInteger>(_ value: T) {
      var little = value.littleEndian
      withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }
    text("RIFF")
    number(byteCount + 36)
    text("WAVEfmt ")
    number(UInt32(16))
    number(UInt16(1))
    number(UInt16(1))
    number(UInt32(16_000))
    number(UInt32(32_000))
    number(UInt16(2))
    number(UInt16(16))
    text("data")
    number(byteCount)
    return data
  }

  private static func failure(_ message: String) -> NSError {
    NSError(domain: "fknotes.audio_decode", code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
  }
}
