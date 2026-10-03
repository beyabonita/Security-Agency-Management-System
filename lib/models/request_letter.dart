import 'dart:math';
import 'dart:typed_data';

class RequestLetter {
  /// Reads cloud/document-provider files once and stops at the size limit,
  /// including when the provider reports an unknown or inaccurate file size.
  static Future<RequestLetter> read({
    required String name,
    required Stream<List<int>> chunks,
    int? reportedSize,
  }) async {
    if (reportedSize != null && reportedSize > maxBytes) {
      throw const FormatException('The letter must be 5 MB or smaller.');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in chunks) {
      if (buffer.length + chunk.length > maxBytes) {
        throw const FormatException('The letter must be 5 MB or smaller.');
      }
      buffer.add(chunk);
    }
    return RequestLetter(name: name, bytes: buffer.takeBytes());
  }

  RequestLetter({required this.name, required this.bytes}) {
    if (name.isEmpty ||
        name.length > 180 ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(name)) {
      throw const FormatException('Use a filename of up to 180 characters.');
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException(
        'The letter must be between 1 byte and 5 MB.',
      );
    }
    final lower = name.toLowerCase();
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((value) => value);
    if (lower.endsWith('.pdf') && starts([0x25, 0x50, 0x44, 0x46, 0x2d])) {
      extension = 'pdf';
      mimeType = 'application/pdf';
    } else if ((lower.endsWith('.jpg') || lower.endsWith('.jpeg')) &&
        starts([0xff, 0xd8, 0xff])) {
      extension = 'jpg';
      mimeType = 'image/jpeg';
    } else if (lower.endsWith('.png') &&
        starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      extension = 'png';
      mimeType = 'image/png';
    } else {
      throw const FormatException('Attach a valid PDF, JPG or PNG letter.');
    }
  }
  static const maxBytes = 5 * 1024 * 1024;
  final String name;
  final Uint8List bytes;
  late final String extension;
  late final String mimeType;
  // Reserve before starting I/O. A lost upload response must reuse this key.
  String? pendingUploadPath;
  String? uploadedPath;
  // An interrupted RPC may already have filed this letter on the server.
  bool submissionUncertain = false;
  String reservePath(String userId) {
    final path = uploadedPath ?? pendingUploadPath;
    if (path != null && !path.startsWith('$userId/')) {
      throw StateError('Your account changed. Choose your letter again.');
    }
    return pendingUploadPath ??= path ?? newPath(userId);
  }

  String newPath(String userId) {
    final random = Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$userId/$key.$extension';
  }
}
