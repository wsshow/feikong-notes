import 'package:fknotes/services/ios_platform_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/ios-platform');
  late List<String> calls;
  setUp(() {
    calls = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return null;
    });
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'only a resumed Flutter frame releases the native privacy shield',
    (tester) async {
      final service = IosPlatformService(channel: channel, supported: true);
      await service.initialize();
      expect(calls, ['configureStorage']);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(calls, ['configureStorage']);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(calls, ['configureStorage']);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(calls, ['configureStorage', 'privacyReady']);
      service.dispose();
    },
  );

  testWidgets(
    'a second interruption before the frame keeps the shield in place',
    (tester) async {
      final service = IosPlatformService(channel: channel, supported: true);
      await service.initialize();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(calls, ['configureStorage']);
      service.dispose();
    },
  );

  test('other hosts do not invoke the iOS bridge', () async {
    final service = IosPlatformService(channel: channel, supported: false);
    await service.initialize();
    service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(calls, isEmpty);
    service.dispose();
  });
}
