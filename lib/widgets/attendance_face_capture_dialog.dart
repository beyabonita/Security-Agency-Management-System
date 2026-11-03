import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/services/geotag_watermark_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';

/// Prompts the guard to capture a live front-camera verification photo with
/// an embedded Geotag & Timestamp watermark before recording Time In
/// (Revision Items #6, #8, #20).
Future<String?> captureAttendanceFaceVerification(
  BuildContext context, {
  double? latitude,
  double? longitude,
  double? accuracyMeters,
  String? locationLabel,
  String? deviceLabel,
  String actionLabel = 'Time In Face Verification',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AttendanceFaceCaptureSheet(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: accuracyMeters,
      locationLabel: locationLabel,
      deviceLabel: deviceLabel,
      actionLabel: actionLabel,
    ),
  );
}

class _AttendanceFaceCaptureSheet extends StatefulWidget {
  const _AttendanceFaceCaptureSheet({
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.locationLabel,
    this.deviceLabel,
    required this.actionLabel,
  });

  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final String? locationLabel;
  final String? deviceLabel;
  final String actionLabel;

  @override
  State<_AttendanceFaceCaptureSheet> createState() =>
      _AttendanceFaceCaptureSheetState();
}

class _AttendanceFaceCaptureSheetState
    extends State<_AttendanceFaceCaptureSheet> {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  bool _capturing = false;
  Uint8List? _watermarkedPreview;
  String? _encodedDataUrl;

  @override
  void initState() {
    super.initState();
    _initFrontCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _initFrontCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _initializing = false;
          _error = 'No camera detected. Use the camera capture button below.';
        });
        return;
      }

      // Prefer front camera for face verification (#6, #20)
      final ordered = List<CameraDescription>.of(cameras)
        ..sort((a, b) {
          final aFront = a.lensDirection == CameraLensDirection.front ? 0 : 1;
          final bFront = b.lensDirection == CameraLensDirection.front ? 0 : 1;
          return aFront.compareTo(bFront);
        });

      for (final cam in ordered) {
        final ctrl = CameraController(
          cam,
          ResolutionPreset.medium,
          enableAudio: false,
        );
        try {
          await ctrl.initialize();
          if (!mounted) {
            await ctrl.dispose();
            return;
          }
          setState(() {
            _controller = ctrl;
            _initializing = false;
            _error = null;
          });
          return;
        } catch (_) {
          await ctrl.dispose();
        }
      }

      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Could not start live preview. Use the capture button below.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = 'Camera permission needed. Use the capture button below.';
      });
    }
  }

  Future<void> _captureFromPreview() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await ctrl.takePicture();
      final rawBytes = await file.readAsBytes();
      _processRawPhoto(rawBytes);
    } catch (_) {
      await _captureFallback();
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _captureFallback() async {
    if (_capturing) return;
    setState(() => _capturing = true);
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
        maxWidth: 1024,
      );
      if (picked == null) return;
      final rawBytes = await picked.readAsBytes();
      _processRawPhoto(rawBytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not capture face verification photo.'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _processRawPhoto(Uint8List rawBytes) {
    if (!mounted || rawBytes.isEmpty) return;
    final now = DateTime.now();
    final watermarked = GeotagWatermarkService.applyGeotagWatermark(
      rawBytes,
      latitude: widget.latitude,
      longitude: widget.longitude,
      accuracyMeters: widget.accuracyMeters,
      locationLabel: widget.locationLabel,
      tagLabel: widget.actionLabel.toUpperCase(),
      deviceLabel: widget.deviceLabel,
      capturedAt: now,
      maxDimension: 640,
      jpegQuality: 78,
    );
    final dataUrl = GeotagWatermarkService.toWatermarkedBase64DataUrl(
      rawBytes,
      latitude: widget.latitude,
      longitude: widget.longitude,
      accuracyMeters: widget.accuracyMeters,
      locationLabel: widget.locationLabel,
      tagLabel: widget.actionLabel.toUpperCase(),
      deviceLabel: widget.deviceLabel,
      capturedAt: now,
    );
    setState(() {
      _watermarkedPreview = watermarked;
      _encodedDataUrl = dataUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.actionLabel,
                      style: TextStyle(
                        color: palette.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Live face photo + GPS geotag & device verification',
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(null),
                icon: Icon(Icons.close_rounded, color: palette.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 300,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _watermarkedPreview != null
                  ? Image.memory(_watermarkedPreview!, fit: BoxFit.cover)
                  : _initializing
                  ? const Center(child: CircularProgressIndicator())
                  : (_controller != null && _controller!.value.isInitialized)
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        CameraPreview(_controller!),
                        Positioned(
                          bottom: 10,
                          left: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '📍 ${widget.locationLabel ?? "Scheduled Post"} • '
                              '${widget.latitude != null ? "${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}" : "GPS Active"}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Container(
                      color: palette.surfaceMuted,
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_front_rounded,
                            size: 46,
                            color: palette.accent,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _error ?? 'Capture a live selfie to verify your identity.',
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 13,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 14),
          if (_watermarkedPreview == null)
            FilledButton.icon(
              onPressed: _capturing
                  ? null
                  : (_controller != null && _controller!.value.isInitialized)
                  ? _captureFromPreview
                  : _captureFallback,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.camera_alt_rounded),
              label: Text(
                _capturing
                    ? 'Applying Geotag Watermark...'
                    : 'Capture Geotagged Face Photo',
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _watermarkedPreview = null;
                        _encodedDataUrl = null;
                      });
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(_encodedDataUrl),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Confirm & Record'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
