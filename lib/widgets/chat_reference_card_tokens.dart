/// Shared geometry for compact references attached to chat messages.
///
/// Text quotes and note references intentionally use the same footprint so a
/// mixed reference stack keeps a stable right edge and vertical rhythm.
abstract final class ChatReferenceCardTokens {
  static const width = 176.0;
  static const height = 38.0;
  static const gap = 6.0;
  static const radius = 12.0;
  static const iconSize = 17.0;
}
