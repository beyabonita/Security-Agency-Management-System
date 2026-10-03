import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/request_letter.dart';

void main() {
  test('Cloud-file chunks are read once without a known size', () async {
    final letter = await RequestLetter.read(
      name: 'absence.pdf',
      chunks: Stream.fromIterable(['%PDF-'.codeUnits, '1.7 test'.codeUnits]),
    );
    expect(String.fromCharCodes(letter.bytes), '%PDF-1.7 test');
  });
  test('A misleading cloud-file size cannot bypass the 5 MB bound', () async {
    await expectLater(
      RequestLetter.read(
        name: 'absence.pdf',
        reportedSize: 4,
        chunks: Stream.fromIterable([
          Uint8List(RequestLetter.maxBytes),
          [1],
        ]),
      ),
      throwsFormatException,
    );
  });
  test(
    'Reserved upload identity stays fixed and rejects a different account',
    () {
      final letter = RequestLetter(
        name: 'absence.pdf',
        bytes: Uint8List.fromList('%PDF-1'.codeUnits),
      );
      final path = letter.reservePath('guard-one');
      expect(letter.reservePath('guard-one'), path);
      expect(() => letter.reservePath('guard-two'), throwsStateError);
    },
  );
  test(
    'PDF letters use a private generated filename, not the supplied name',
    () {
      final letter = RequestLetter(
        name: 'Absence request.PDF',
        bytes: Uint8List.fromList('%PDF-1.7'.codeUnits),
      );
      expect(letter.mimeType, 'application/pdf');
      expect(
        letter.newPath('guard-id'),
        matches(RegExp(r'^guard-id/[a-f0-9]{32}\.pdf$')),
      );
      expect(letter.newPath('guard-id'), isNot(letter.newPath('guard-id')));
    },
  );
  test('JPG and PNG letters are recognized by signature and extension', () {
    expect(
      RequestLetter(
        name: 'letter.jpeg',
        bytes: Uint8List.fromList([255, 216, 255]),
      ).mimeType,
      'image/jpeg',
    );
    expect(
      RequestLetter(
        name: 'letter.png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ).mimeType,
      'image/png',
    );
  });
  test('Renaming HTML or unknown data as a PDF does not bypass validation', () {
    expect(
      () => RequestLetter(
        name: 'letter.pdf',
        bytes: Uint8List.fromList('<script>'.codeUnits),
      ),
      throwsFormatException,
    );
    expect(
      () => RequestLetter(
        name: 'letter.exe',
        bytes: Uint8List.fromList('%PDF-'.codeUnits),
      ),
      throwsFormatException,
    );
  });
  test('Empty, oversized and unsafe filenames are rejected', () {
    expect(
      () => RequestLetter(name: 'letter.pdf', bytes: Uint8List(0)),
      throwsFormatException,
    );
    expect(
      () => RequestLetter(
        name: 'letter.pdf',
        bytes: Uint8List(RequestLetter.maxBytes + 1),
      ),
      throwsFormatException,
    );
    expect(
      () => RequestLetter(
        name: '../letter.pdf',
        bytes: Uint8List.fromList('%PDF-'.codeUnits),
      ),
      throwsFormatException,
    );
  });
  test('Exactly 5 MB is accepted', () {
    final bytes = Uint8List(RequestLetter.maxBytes)
      ..setRange(0, 5, '%PDF-'.codeUnits);
    expect(
      RequestLetter(name: 'limit.pdf', bytes: bytes).bytes.length,
      RequestLetter.maxBytes,
    );
  });
}
