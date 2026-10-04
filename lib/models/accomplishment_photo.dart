import 'dart:math';
import 'dart:typed_data';

class AccomplishmentPhoto {
  AccomplishmentPhoto({required this.name, required this.bytes}) {
    if (name.isEmpty ||
        name.length > 180 ||
        RegExp(r'[\x00-\x1f/\\]').hasMatch(name)) {
      throw const FormatException(
        'Use a photo filename of up to 180 characters.',
      );
    }
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Choose a photo of 10 MB or smaller.');
    }
    bool starts(List<int> signature) =>
        bytes.length >= signature.length &&
        List.generate(
          signature.length,
          (i) => bytes[i] == signature[i],
        ).every((v) => v);
    final lower = name.toLowerCase();
    if ((lower.endsWith('.jpg') || lower.endsWith('.jpeg')) &&
        starts([255, 216, 255])) {
      extension = 'jpg';
      mimeType = 'image/jpeg';
    } else if (lower.endsWith('.png') &&
        starts([137, 80, 78, 71, 13, 10, 26, 10])) {
      extension = 'png';
      mimeType = 'image/png';
    } else {
      throw const FormatException('Choose a JPG or PNG photo report.');
    }
  }

  static const maxBytes = 10 * 1024 * 1024;
  final String name;
  final Uint8List bytes;
  late final String extension;
  late final String mimeType;
  String? uploadPath;
  bool uploaded = false;
  bool submissionUncertain = false;

  String reservePath(String userId) {
    if (uploadPath != null && !uploadPath!.startsWith('$userId/')) {
      throw StateError('Your account changed. Choose your photo again.');
    }
    final random = Random.secure();
    return uploadPath ??=
        '$userId/${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}.$extension';
  }

  static Future<AccomplishmentPhoto> read({
    required String name,
    required Stream<List<int>> chunks,
    int? reportedSize,
  }) async {
    if (reportedSize != null && reportedSize > maxBytes) {
      throw const FormatException('Choose a photo of 10 MB or smaller.');
    }
    final buffer = BytesBuilder(copy: false);
    await for (final chunk in chunks) {
      if (buffer.length + chunk.length > maxBytes) {
        throw const FormatException('Choose a photo of 10 MB or smaller.');
      }
      buffer.add(chunk);
    }
    return AccomplishmentPhoto(name: name, bytes: buffer.takeBytes());
  }
}
