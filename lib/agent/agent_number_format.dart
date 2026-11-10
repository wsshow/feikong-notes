/// Formats token counts with a short, locale-independent unit used by model
/// configuration and usage displays throughout the agent UI.
String formatAgentTokenCount(int value) {
  final absolute = value.abs();
  if (absolute < 1000) return value.toString();

  final (divisor, suffix) = absolute >= 1000000000
      ? (1000000000, 'B')
      : absolute >= 1000000
      ? (1000000, 'M')
      : (1000, 'K');
  final digits = absolute < divisor * 10
      ? 2
      : absolute < divisor * 100
      ? 1
      : 0;
  final factor = digits == 2
      ? 100
      : digits == 1
      ? 10
      : 1;
  final rounded = (absolute * factor + divisor ~/ 2) ~/ divisor;
  final whole = rounded ~/ factor;
  final fraction = rounded.remainder(factor);
  var compact = '$whole';
  if (fraction != 0) {
    final tail = fraction
        .toString()
        .padLeft(digits, '0')
        .replaceFirst(RegExp(r'0+$'), '');
    compact = '$compact.$tail';
  }
  if (value.isNegative) compact = '-$compact';
  return '$compact$suffix';
}
