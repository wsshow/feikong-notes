import 'package:fknotes/services/realtime_dictation_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers platform hardware execution providers', () {
    expect(
      RealtimeDictationExecutionPolicy.preferredFor(
        isAndroid: true,
        isIOS: false,
      ),
      RealtimeDictationExecutionProvider.nnapi,
    );
    expect(
      RealtimeDictationExecutionPolicy.preferredFor(
        isAndroid: false,
        isIOS: true,
      ),
      RealtimeDictationExecutionProvider.coreMl,
    );
    expect(
      RealtimeDictationExecutionPolicy.preferredFor(
        isAndroid: false,
        isIOS: false,
      ),
      RealtimeDictationExecutionProvider.cpu,
    );
  });

  test('maps sherpa provider names to stable runtime values', () {
    expect(
      RealtimeDictationExecutionPolicy.fromSherpaName('nnapi'),
      RealtimeDictationExecutionProvider.nnapi,
    );
    expect(
      RealtimeDictationExecutionPolicy.fromSherpaName('CoreML'),
      RealtimeDictationExecutionProvider.coreMl,
    );
    expect(
      RealtimeDictationExecutionPolicy.fromSherpaName('unknown'),
      RealtimeDictationExecutionProvider.cpu,
    );
  });
}
