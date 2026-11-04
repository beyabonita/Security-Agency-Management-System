import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Applies a tamper-evident Geotagging & Timestamp watermark banner onto
/// captured evidence and attendance verification photos (Revision Item #8 & #20).
class GeotagWatermarkService {
  /// Stamps a semi-transparent dark footer banner containing:
  /// - Date & Time (PHT / UTC+8)
  /// - GPS Coordinates (Lat, Lng, ±Accuracy)
  /// - Site / Post Label or Action Tag
  /// - Device / Guard Info (optional)
  static Uint8List applyGeotagWatermark(
    Uint8List rawBytes, {
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? locationLabel,
    String? tagLabel,
    String? deviceLabel,
    DateTime? capturedAt,
    int maxDimension = 1280,
    int jpegQuality = 85,
  }) {
    if (rawBytes.isEmpty) return rawBytes;
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return rawBytes;

      img.Image canvas = img.bakeOrientation(decoded);
      if (canvas.width > maxDimension || canvas.height > maxDimension) {
        if (canvas.width >= canvas.height) {
          canvas = img.copyResize(canvas, width: maxDimension);
        } else {
          canvas = img.copyResize(canvas, height: maxDimension);
        }
      }

      final nowPht = (capturedAt ?? DateTime.now()).toUtc().add(
        const Duration(hours: 8),
      );
      final dateStr =
          '${nowPht.year}-${nowPht.month.toString().padLeft(2, '0')}-${nowPht.day.toString().padLeft(2, '0')}';
      final hour12 = nowPht.hour % 12 == 0 ? 12 : nowPht.hour % 12;
      final ampm = nowPht.hour >= 12 ? 'PM' : 'AM';
      final timeStr =
          '${hour12.toString().padLeft(2, '0')}:${nowPht.minute.toString().padLeft(2, '0')}:${nowPht.second.toString().padLeft(2, '0')} $ampm PHT';

      final gpsStr = (latitude != null && longitude != null)
          ? 'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
                '${accuracyMeters != null ? ' (+/-${accuracyMeters.round()}m)' : ''}'
          : 'GPS: Acquiring coordinates...';

      final siteStr = (locationLabel != null && locationLabel.trim().isNotEmpty)
          ? 'POST: ${_sanitizeAscii(locationLabel.trim())}'
          : 'POST: TwentyTwenty Security Agency';

      final headerStr = (tagLabel != null && tagLabel.trim().isNotEmpty)
          ? '${_sanitizeAscii(tagLabel.trim())} | $dateStr $timeStr'
          : 'GEOTAGGED EVIDENCE | $dateStr $timeStr';

      final lines = <String>[
        headerStr,
        gpsStr,
        siteStr,
        if (deviceLabel != null && deviceLabel.trim().isNotEmpty)
          'DEVICE: ${_sanitizeAscii(deviceLabel.trim())}',
      ];

      final useLargeFont = canvas.width >= 720;
      final font = useLargeFont ? img.arial24 : img.arial14;
      final lineHeight = useLargeFont ? 28 : 18;
      final padding = useLargeFont ? 14 : 10;
      final bannerHeight = (lines.length * lineHeight) + (padding * 2);
      final bannerTop = (canvas.height - bannerHeight).clamp(0, canvas.height);

      // Draw dark semi-transparent footer box
      img.fillRect(
        canvas,
        x1: 0,
        y1: bannerTop,
        x2: canvas.width,
        y2: canvas.height,
        color: img.ColorRgba8(15, 23, 42, 205),
      );

      // Draw top red accent stripe on the banner
      img.fillRect(
        canvas,
        x1: 0,
        y1: bannerTop,
        x2: canvas.width,
        y2: (bannerTop + 3).clamp(0, canvas.height),
        color: img.ColorRgba8(220, 38, 38, 255),
      );

      for (var i = 0; i < lines.length; i++) {
        final y = bannerTop + padding + (i * lineHeight);
        final textColor = i == 0
            ? img.ColorRgba8(254, 240, 138, 255) // Warm yellow header
            : img.ColorRgba8(248, 250, 252, 255); // Crisp white details
        img.drawString(
          canvas,
          lines[i],
          font: font,
          x: padding,
          y: y,
          color: textColor,
        );
      }

      return Uint8List.fromList(img.encodeJpg(canvas, quality: jpegQuality));
    } catch (_) {
      return rawBytes;
    }
  }

  /// Creates a compact base64 JPEG data URL with geotag watermark suitable for
  /// storing on `attendance_sessions.clock_in_face_photo`.
  static String toWatermarkedBase64DataUrl(
    Uint8List rawBytes, {
    double? latitude,
    double? longitude,
    double? accuracyMeters,
    String? locationLabel,
    String? tagLabel,
    String? deviceLabel,
    DateTime? capturedAt,
  }) {
    final watermarked = applyGeotagWatermark(
      rawBytes,
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      locationLabel: locationLabel,
      tagLabel: tagLabel ?? 'ATTENDANCE FACE VERIFICATION',
      deviceLabel: deviceLabel,
      capturedAt: capturedAt,
      maxDimension: 640,
      jpegQuality: 78,
    );
    return 'data:image/jpeg;base64,${base64Encode(watermarked)}';
  }

  static String _sanitizeAscii(String input) {
    return input
        .replaceAll('·', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('±', '+/-')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '');
  }
}

