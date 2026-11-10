import Foundation

// Host-side integration harness for the exact decoder compiled into Runner.
@main
struct AudioDecodeTest {
  static func main() async {
    let args = CommandLine.arguments
    let cancellation = AudioDecodeCancellation()
    if args.count > 3 && args[3] == "cancel" { cancellation.cancel() }
    do {
      try await AudioFileDecoder.decode(
        source: URL(fileURLWithPath: args[1]), destination: URL(fileURLWithPath: args[2]),
        cancellation: cancellation)
    } catch {
      exit(1)
    }
  }
}
