import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Compresses a photo for the incident database record.
class IncidentImageCodec {
  static const int maxBase64Length = 750000;

  static Future<String> bytesToBase64Jpeg(Uint8List raw) async {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw Exception('Could not read the photo. Try capturing again.');
    }

    var width = decoded.width;
    if (width > 1024) width = 1024;
    var resized = img.copyResize(decoded, width: width);

    for (final quality in [70, 55, 40, 30]) {
      final jpg = img.encodeJpg(resized, quality: quality);
      final b64 = base64Encode(jpg);
      if (b64.length <= maxBase64Length) return b64;
      if (width > 640) {
        width = 640;
        resized = img.copyResize(decoded, width: width);
      }
    }

    throw Exception(
      'Photo is too large even after compression. Retake closer or send without photo.',
    );
  }
}
