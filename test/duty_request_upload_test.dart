import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/request_letter.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';

RequestLetter letter() => RequestLetter(
  name: 'absence.pdf',
  bytes: Uint8List.fromList('%PDF-1.7 test letter'.codeUnits),
);

void main() {
  test(
    'Uncertain submitted letter is never deleted while an RPC may finish',
    () async {
      final attachment = letter()
        ..pendingUploadPath = 'guard-1/safe.pdf'
        ..uploadedPath = 'guard-1/safe.pdf'
        ..submissionUncertain = true;
      // No Supabase client is initialized: returning proves no delete was sent.
      await DutyRequestService.discardUnsubmittedLetter(attachment);
    },
  );
  test(
    'Upload is only performed once when RPC submission is retried',
    () async {
      final attachment = letter();
      var uploads = 0;
      Future<void> attempt() => prepareRequestLetterUpload(
        letter: attachment,
        userId: 'guard-1',
        upload: (_) async {
          uploads++;
        },
        exists: (_) async =>
            throw StateError('No existence check on fresh upload'),
      );
      await attempt();
      final path = attachment.uploadedPath;
      await attempt();
      expect(uploads, 1);
      expect(attachment.uploadedPath, path);
    },
  );
  test('Lost upload response reuses the uploaded object on retry', () async {
    final attachment = letter();
    var uploads = 0;
    final objects = <String>{};
    Future<void> attempt() => prepareRequestLetterUpload(
      letter: attachment,
      userId: 'guard-1',
      upload: (path) async {
        uploads++;
        objects.add(path);
        throw TimeoutException('Response lost');
      },
      exists: (path) async => objects.contains(path),
    );
    await expectLater(attempt(), throwsA(isA<TimeoutException>()));
    final reserved = attachment.pendingUploadPath;
    await attempt();
    expect(uploads, 1);
    expect(attachment.uploadedPath, reserved);
  });
  test('Failed upload retries with the same reserved key', () async {
    final attachment = letter();
    final paths = <String>[];
    Future<void> attempt() => prepareRequestLetterUpload(
      letter: attachment,
      userId: 'guard-1',
      upload: (path) async {
        paths.add(path);
        if (paths.length == 1) throw TimeoutException('Offline');
      },
      exists: (_) async => false,
    );
    await expectLater(attempt(), throwsA(isA<TimeoutException>()));
    await attempt();
    expect(paths.length, 2);
    expect(paths[0], paths[1]);
  });
  test(
    'Concurrent completed upload accepts duplicate only after confirming object',
    () async {
      final attachment = letter();
      await prepareRequestLetterUpload(
        letter: attachment,
        userId: 'guard-1',
        upload: (_) async =>
            throw const StorageException('Duplicate', statusCode: '409'),
        exists: (_) async => true,
      );
      expect(attachment.uploadedPath, isNotNull);
      final missing = letter();
      await expectLater(
        prepareRequestLetterUpload(
          letter: missing,
          userId: 'guard-1',
          upload: (_) async =>
              throw const StorageException('Duplicate', statusCode: '409'),
          exists: (_) async => false,
        ),
        throwsA(isA<StorageException>()),
      );
      expect(missing.uploadedPath, isNull);
    },
  );
  test('Storage denial is not swallowed or treated as uploaded', () async {
    final attachment = letter();
    await expectLater(
      prepareRequestLetterUpload(
        letter: attachment,
        userId: 'guard-1',
        upload: (_) async =>
            throw const StorageException('Denied', statusCode: '403'),
        exists: (_) async => true,
      ),
      throwsA(isA<StorageException>()),
    );
    expect(attachment.uploadedPath, isNull);
    expect(
      dutyRequestErrorMessage(
        const StorageException('Denied', statusCode: '403'),
      ),
      contains('upload was denied'),
    );
    expect(
      dutyRequestErrorMessage(const StorageException('Bucket not found')),
      contains('storage is unavailable'),
    );
    expect(
      dutyRequestErrorMessage(TimeoutException('slow')),
      contains('will not create a duplicate'),
    );
  });
}
