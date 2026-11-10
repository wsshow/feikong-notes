import 'dart:convert';

import 'models.dart';

class ContextSelection {
  final List<AgentMessage> messages;
  final List<AgentMessage> omitted;
  const ContextSelection(this.messages, this.omitted);
}

/// Keeps complete assistant/tool exchanges together. Full history stays in RunStore.
class ContextWindow {
  static int estimate(String text) => (utf8.encode(text).length / 3).ceil() + 8;
  static int messageTokens(AgentMessage message) =>
      estimate(jsonEncode(message.toJson()));
  static ContextSelection select(List<AgentMessage> messages, int tokenBudget) {
    final groups = <List<AgentMessage>>[];
    for (final message in messages) {
      if (message.role == MessageRole.tool &&
          groups.isNotEmpty &&
          groups.last.first.role == MessageRole.assistant &&
          groups.last.first.calls.isNotEmpty) {
        groups.last.add(message);
      } else {
        groups.add([message]);
      }
    }
    final kept = <AgentMessage>[];
    var used = 0;
    var start = groups.length;
    for (var i = groups.length - 1; i >= 0; i--) {
      final size = groups[i].fold<int>(0, (n, m) => n + messageTokens(m));
      if (used + size > tokenBudget) break;
      used += size;
      kept.insertAll(0, groups[i]);
      start = i;
    }
    if (kept.isEmpty && messages.isNotEmpty) {
      throw const HarnessException(
        'contextOverflow',
        'The most recent exchange exceeds the model context.',
      );
    }
    return ContextSelection(kept, groups.take(start).expand((g) => g).toList());
  }
}
