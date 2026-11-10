import 'dart:io';
import 'dart:typed_data';

import 'package:fknotes_harness/fknotes_harness.dart';
import 'package:path/path.dart' as p;

import '../services/file_storage_service.dart';

class AgentAttachmentLoader {
  final FileStorageService storage;
  AgentAttachmentLoader(this.storage);
  Future<File> file(ModelAttachment attachment) async {
    final file = File(storage.absolutePath(attachment.reference));
    final root = await Directory(storage.baseDir).resolveSymbolicLinks();
    final resolved = await file.resolveSymbolicLinks();
    if (!p.isWithin(root, resolved) ||
        ![
          'image/png',
          'image/jpeg',
          'image/webp',
          'audio/wav',
          'audio/mpeg',
          'audio/mp4',
        ].contains(attachment.mimeType)) {
      throw const HarnessException(
        'invalidAttachment',
        'Unsupported or inaccessible attachment.',
      );
    }
    final length = await file.length();
    if (length == 0 || length > 10 * 1024 * 1024) {
      throw const HarnessException(
        'attachmentSize',
        'Attachments must be between 1 byte and 10 MB.',
      );
    }
    return File(resolved);
  }

  Future<Uint8List> bytes(ModelAttachment attachment) async =>
      (await file(attachment)).readAsBytes();
}
