import 'dart:async';
import 'dart:convert';

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
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => _AttendanceFaceCapturePage(
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
        locationLabel: locationLabel,
        deviceLabel: deviceLabel,
        actionLabel: actionLabel,
      ),
    ),
  );
}

class _AttendanceFaceCapturePage extends StatefulWidget {
  const _AttendanceFaceCapturePage({
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
  State<_AttendanceFaceCapturePage> createState() =>
      _AttendanceFaceCapturePageState();
}

class _AttendanceFaceCapturePageState
    extends State<_AttendanceFaceCapturePage> {
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
      maxDimension: 720,
      jpegQuality: 82,
    );
    final dataUrl = 'data:image/jpeg;base64,${base64Encode(watermarked)}';
    setState(() {
      _watermarkedPreview = watermarked;
      _encodedDataUrl = dataUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    // ── Mode 1: Review View (Full Watermark Visible Above Buttons) ──
    if (_watermarkedPreview != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Top Bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: () {
                        setState(() {
                          _watermarkedPreview = null;
                          _encodedDataUrl = null;
                        });
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white12,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.arrow_back_rounded, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.actionLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'Review captured photo & verified details',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Center: Fully Visible Watermarked Photo
              Expanded(
                child: Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Center(
                    child: Image.memory(
                      _watermarkedPreview!,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      height: double.infinity,
                    ),
                  ),
                ),
              ),

              // Bottom Bar: Retake & Submit Buttons (Completely Below Photo)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0F17),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            _watermarkedPreview = null;
                            _encodedDataUrl = null;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(
                            color: Colors.white70,
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        label: const Text(
                          'Retake',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: () =>
                            Navigator.of(context).pop(_encodedDataUrl),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text(
                          'Submit',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ── Mode 2: Live Full-Screen Camera View ──
    final mediaQuery = MediaQuery.of(context);
    final topPadding = mediaQuery.padding.top;
    final bottomPadding = mediaQuery.padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Layer 1: Full-Screen Live Camera Preview ──
          Positioned.fill(
            child: _initializing
                ? Container(
                    color: Colors.black,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Initializing camera...',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : (_controller != null && _controller!.value.isInitialized)
                ? LayoutBuilder(
                    builder: (ctx, constraints) {
                      return SizedBox.expand(
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.previewSize?.height ??
                                constraints.maxWidth,
                            height: _controller!.value.previewSize?.width ??
                                constraints.maxHeight,
                            child: CameraPreview(_controller!),
                          ),
                        ),
                      );
                    },
                  )
                : Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.camera_front_rounded,
                          size: 64,
                          color: Colors.white54,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error ??
                              'Capture a live selfie to verify your identity.',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _captureFallback,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                          ),
                          icon: const Icon(Icons.photo_camera_rounded),
                          label: const Text('Open System Camera'),
                        ),
                      ],
                    ),
                  ),
          ),

          // ── Layer 2: Subtle Face Framing Guide (when previewing) ──
          if (_controller != null && _controller!.value.isInitialized)
            Center(
              child: Container(
                width: 260,
                height: 340,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: 2,
                  ),
                ),
              ),
            ),

          // ── Layer 3: Top Full-Screen App Bar Overlay ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.75),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Row(
                children: [
                  IconButton.filledTonal(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.5),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.actionLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Text(
                          'Align your face inside the frame',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Layer 4: Bottom Controls & Geotag Watermark Overlay ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, bottomPadding + 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.85),
                    Colors.black.withValues(alpha: 0.0),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Geotag badge pill
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      '📍 ${widget.locationLabel ?? "Scheduled Post"} • '
                      '${widget.latitude != null ? "${widget.latitude!.toStringAsFixed(5)}, ${widget.longitude!.toStringAsFixed(5)}" : "GPS Active"}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                  // Shutter Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _capturing
                          ? null
                          : (_controller != null &&
                                  _controller!.value.isInitialized)
                              ? _captureFromPreview
                              : _captureFallback,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 4,
                      ),
                      icon: _capturing
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.camera_alt_rounded, size: 22),
                      label: Text(
                        _capturing
                            ? 'Applying Geotag Watermark...'
                            : 'Capture Geotagged Face Photo',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

