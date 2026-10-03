import 'dart:typed_data';

import 'package:flutter_application_1/services/incident_image_codec.dart';
import 'package:flutter_application_1/services/incident_video_format.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Emergency incident alerts require a photo or video and a narrative.
class IncidentService {
  static const categories = <String, String>{
    'crime': 'Crime / theft',
    'fire': 'Fire / hazard',
    'medical': 'Medical',
    'disturbance': 'Disturbance',
    'other': 'Emergency',
  };

  static Future<void> submitReport({
    required String category,
    Uint8List? photoBytes,
    String remarks = '',
    required DateTime capturedAt,
    Uint8List? videoBytes,
    int? videoDurationSeconds,
    String? videoContentType,
    double? latitude,
    double? longitude,
    String? locationLabel,
  }) async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      throw Exception('You must be signed in to send an alert.');
    }
    if (!categories.containsKey(category)) {
      throw Exception('Invalid incident type.');
    }
    final hasPhoto = photoBytes != null && photoBytes.isNotEmpty;
    final hasVideo = videoBytes != null && videoBytes.isNotEmpty;
    if (!hasPhoto && !hasVideo) {
      throw Exception(
        'Capture a photo or record a video before sending the alert.',
      );
    }
    if (remarks.trim().isEmpty) {
      throw Exception('Enter an incident narrative before sending the alert.');
    }
    if (remarks.trim().length > 2000) {
      throw Exception('Incident narrative cannot exceed 2,000 characters.');
    }
    if (capturedAt.isBefore(
          DateTime.now().toUtc().subtract(const Duration(minutes: 10)),
        ) ||
        capturedAt.isAfter(
          DateTime.now().toUtc().add(const Duration(minutes: 1)),
        )) {
      throw Exception(
        'Capture a current photo or video before filing the alert.',
      );
    }
    String? resolvedVideoContentType;
    if (videoBytes != null && videoBytes.isNotEmpty) {
      if (videoDurationSeconds == null ||
          videoDurationSeconds < 1 ||
          videoDurationSeconds > 15) {
        throw Exception('Incident video must be between 1 and 15 seconds.');
      }
      if (videoBytes.length > IncidentVideoFormat.maxBytes) {
        throw Exception(
          'Incident video is too large. Record a shorter video and try again.',
        );
      }
      resolvedVideoContentType = IncidentVideoFormat.contentTypeFor(
        reportedMimeType: videoContentType,
      );
    }

    final photoData = hasPhoto
        ? await IncidentImageCodec.bytesToBase64Jpeg(photoBytes)
        : null;
    String? videoPath;
    try {
      if (videoBytes != null && videoBytes.isNotEmpty) {
        final extension = IncidentVideoFormat.extensionFor(
          resolvedVideoContentType!,
        );
        videoPath =
            '${user.id}/${DateTime.now().toUtc().millisecondsSinceEpoch}.$extension';
        await client.storage
            .from('incident-videos')
            .uploadBinary(
              videoPath,
              videoBytes,
              fileOptions: FileOptions(
                contentType: resolvedVideoContentType,
                cacheControl: '3600',
                upsert: false,
              ),
            );
      }
      await client.rpc(
        'file_incident_report',
        params: {
          'p_category': category,
          'p_photo_data': photoData,
          'p_guard_remarks': remarks.trim(),
          'p_captured_at': capturedAt.toUtc().toIso8601String(),
          'p_video_path': videoPath,
          'p_video_duration_seconds': videoPath == null
              ? null
              : videoDurationSeconds,
          'p_latitude': latitude,
          'p_longitude': longitude,
          'p_location_label': locationLabel?.trim(),
        },
      );
    } catch (_) {
      if (videoPath != null) {
        try {
          await client.storage.from('incident-videos').remove([videoPath]);
        } catch (_) {
          // The server-side cleanup policy permits a later retry for unfiled uploads.
        }
      }
      rethrow;
    }
  }
}
