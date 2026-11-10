import 'package:fknotes/models/note.dart';
import 'package:fknotes/services/incoming_share_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fknotes/test_incoming_share');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late IncomingShareService service;
  late List<Map<String, Object?>> queue;

  Map<String, Object?> entry(String text) {
    final id = NoteId.generate().value;
    return {
      'id': id,
      'directory': '/private/inbox/$id',
      'createdAt': 1000,
      'title': '',
      'text': text,
      'files': <Object>[],
      'error': null,
    };
  }

  Future<void> event(String method) async {
    await messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
      (_) {},
    );
  }

  setUp(() {
    queue = [];
    service = IncomingShareService(channel: channel, supported: true);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'peek') return queue.firstOrNull;
      if (call.method == 'finish') {
        queue.removeWhere((entry) => entry['id'] == call.arguments['id']);
      }
      return null;
    });
  });
  tearDown(() {
    service.dispose();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('cold and warm shares stay queued until acknowledged', () async {
    queue.add(entry('cold'));
    await service.initialize();
    expect(service.pending!.text, 'cold');
    queue.add(entry('warm'));
    await event('changed');
    expect(service.pending!.text, 'cold');
    await service.finish(service.pending!.id);
    await service.refresh();
    expect(service.pending!.text, 'warm');
    await service.finish(service.pending!.id);
    await service.refresh();
    expect(service.pending, isNull);
  });

  test(
    'native staging progress and errors do not discard queued shares',
    () async {
      await service.initialize();
      await event('receiving');
      expect(service.receiving, isTrue);
      await event('receiveFailed');
      expect(service.receiving, isFalse);
      expect(service.failed, isTrue);
      queue.add(entry('recovered'));
      await event('changed');
      expect(service.failed, isFalse);
      expect(service.pending!.text, 'recovered');
    },
  );

  test('malformed paths, IDs and oversized content are rejected', () {
    final map = entry('text');
    expect(
      () => IncomingShare.fromMap({...map, 'id': '../../private'}),
      throwsFormatException,
    );
    expect(
      () => IncomingShare.fromMap({...map, 'directory': '/other'}),
      throwsFormatException,
    );
    expect(
      () => IncomingShare.fromMap({...map, 'text': 'x' * 100001}),
      throwsFormatException,
    );
    expect(
      () => IncomingShare.fromMap({
        ...map,
        'files': [
          {
            'name': 'x',
            'fileName': '../secret.db',
            'byteLength': 1,
            'mimeType': 'application/octet-stream',
          },
        ],
      }),
      throwsFormatException,
    );
  });
}
