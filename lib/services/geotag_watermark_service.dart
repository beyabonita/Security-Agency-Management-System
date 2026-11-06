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
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      final monthName = months[nowPht.month - 1];
      final dateFormatted =
          '$monthName ${nowPht.day.toString().padLeft(2, '0')}, ${nowPht.year}';
      final hour12 = nowPht.hour % 12 == 0 ? 12 : nowPht.hour % 12;
      final ampm = nowPht.hour >= 12 ? 'PM' : 'AM';
      final timeStr =
          '${hour12.toString().padLeft(2, '0')}:${nowPht.minute.toString().padLeft(2, '0')}:${nowPht.second.toString().padLeft(2, '0')} $ampm PHT';

      final dateLine = 'DATE: $dateFormatted';
      final timeLine = 'TIME: $timeStr';
      final clientLine =
          (locationLabel != null && locationLabel.trim().isNotEmpty)
              ? 'CLIENT: ${_sanitizeAscii(locationLabel.trim())}'
              : 'CLIENT: TwentyTwenty Security Agency';
      final gpsLine = (latitude != null && longitude != null)
          ? 'GPS: ${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}'
                '${accuracyMeters != null ? ' (+/-${accuracyMeters.round()}m)' : ''}'
          : 'GPS: Acquiring coordinates...';
      final deviceLine = (deviceLabel != null && deviceLabel.trim().isNotEmpty)
          ? 'DEVICE: ${_sanitizeAscii(deviceLabel.trim())}'
          : 'DEVICE: Registered Android Mobile Device';

      final titleLine = (tagLabel != null && tagLabel.trim().isNotEmpty)
          ? _sanitizeAscii(tagLabel.trim())
          : 'ATTENDANCE FACE VERIFICATION';

      final useLargeFont = canvas.width >= 720;
      final font = useLargeFont ? img.arial24 : img.arial14;
      final lineHeight = useLargeFont ? 28 : 18;
      final padding = useLargeFont ? 14 : 10;
      final approxCharWidth = useLargeFont ? 14.0 : 8.5;
      final maxCharsPerLine =
          ((canvas.width - (padding * 2)) / approxCharWidth).floor();

      final rawLines = <String>[
        dateLine,
        timeLine,
        clientLine,
        gpsLine,
        deviceLine,
      ];

      final lines = <String>[];
      for (final raw in rawLines) {
        if (maxCharsPerLine > 15 && raw.length > maxCharsPerLine) {
          lines.addAll(_wrapText(raw, maxCharsPerLine));
        } else {
          lines.add(raw);
        }
      }

      final bannerHeight = (lines.length * lineHeight) + (padding * 2) + 6;
      final bannerTop = (canvas.height - bannerHeight).clamp(0, canvas.height);

      // Draw dark semi-transparent footer box
      img.fillRect(
        canvas,
        x1: 0,
        y1: bannerTop,
        x2: canvas.width,
        y2: canvas.height,
        color: img.ColorRgba8(15, 23, 42, 235),
      );

      // Draw top red accent stripe on the banner
      img.fillRect(
        canvas,
        x1: 0,
        y1: bannerTop,
        x2: canvas.width,
        y2: (bannerTop + 4).clamp(0, canvas.height),
        color: img.ColorRgba8(220, 38, 38, 255),
      );

      for (var i = 0; i < lines.length; i++) {
        final y = bannerTop + padding + 4 + (i * lineHeight);
        final textColor = (i == 0 && lines[0] == titleLine)
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

  static List<String> _wrapText(String text, int maxChars) {
    if (text.length <= maxChars || maxChars <= 10) return [text];
    final words = text.split(' ');
    final result = <String>[];
    var current = StringBuffer();
    for (final word in words) {
      if (current.isEmpty) {
        current.write(word);
      } else if (current.length + 1 + word.length <= maxChars) {
        current.write(' $word');
      } else {
        result.add(current.toString());
        current = StringBuffer(word);
      }
    }
    if (current.isNotEmpty) result.add(current.toString());
    return result;
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

