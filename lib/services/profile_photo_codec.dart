import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Validates, crops, and resizes profile photos to 400x400 metadata-free JPEGs.
class ProfilePhotoCodec {
  static const int maxSourceBytes = 2 * 1024 * 1024; // 2 MB
  static const int targetDimension = 400;

  static bool isSupportedMagicBytes(Uint8List bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true;
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return true;
    }
    return false;
  }

  /// Validates that [raw] is a JPG or PNG within the 2 MB limit and decodes its
  /// oriented dimensions for circular crop preview.
  static ({int width, int height}) validateSource(Uint8List raw) {
    if (raw.isEmpty) {
      throw const FormatException('Selected image file is empty.');
    }
    if (raw.lengthInBytes > maxSourceBytes) {
      throw const FormatException(
        'Profile photo must be 2 MB or smaller. Choose a smaller JPG or PNG.',
      );
    }
    if (!isSupportedMagicBytes(raw)) {
      throw const FormatException(
        'Only JPG and PNG images are supported for profile photos.',
      );
    }
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException(
        'Could not decode the selected image. Choose a valid JPG or PNG.',
      );
    }
    final baked = img.bakeOrientation(decoded);
    return (width: baked.width, height: baked.height);
  }

  /// Crops a square region centered at ([normCenterX], [normCenterY]) in [0..1]
  /// with [zoom] >= 1.0, resizes to 400x400, and encodes a fresh JPEG (stripping EXIF).
  static Uint8List cropAndResizeTo400Jpeg(
    Uint8List raw, {
    double normCenterX = 0.5,
    double normCenterY = 0.5,
    double zoom = 1.0,
  }) {
    if (raw.lengthInBytes > maxSourceBytes) {
      throw const FormatException('Profile photo must be 2 MB or smaller.');
    }
    if (!isSupportedMagicBytes(raw)) {
      throw const FormatException('Only JPG and PNG images are supported.');
    }

    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException('Could not read the selected photo.');
    }

    final oriented = img.bakeOrientation(decoded);
    final shortest = math.min(oriented.width, oriented.height);
    final safeZoom = zoom.clamp(1.0, 4.0);
    final cropSize = math.max(1, (shortest / safeZoom).round());

    final centerX = (normCenterX.clamp(0.0, 1.0) * oriented.width).round();
    final centerY = (normCenterY.clamp(0.0, 1.0) * oriented.height).round();

    final cropX = (centerX - cropSize ~/ 2)
        .clamp(0, math.max(0, oriented.width - cropSize))
        .toInt();
    final cropY = (centerY - cropSize ~/ 2)
        .clamp(0, math.max(0, oriented.height - cropSize))
        .toInt();

    final square = img.copyCrop(
      oriented,
      x: cropX,
      y: cropY,
      width: cropSize,
      height: cropSize,
    );

    final resized = img.copyResize(
      square,
      width: targetDimension,
      height: targetDimension,
      interpolation: img.Interpolation.cubic,
    );

    final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 88));
    if (encoded.lengthInBytes <= maxSourceBytes) {
      return encoded;
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 72));
  }
}
