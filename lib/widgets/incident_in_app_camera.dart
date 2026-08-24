import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter_application_1/services/incident_video_format.dart';

/// Live evidence capture with a system photo fallback when no camera can start.
class IncidentInAppCamera extends StatefulWidget {
  const IncidentInAppCamera({
    super.key,
    required this.onPhotoCaptured,
    this.onVideoCaptured,
    this.height = 260,
    this.availableCamerasLoader,
    this.fallbackPhotoLoader,
  });

  final void Function(Uint8List photoBytes) onPhotoCaptured;
  final void Function(
    Uint8List videoBytes,
    Duration duration,
    String contentType,
  )?
  onVideoCaptured;
  final double height;

  @visibleForTesting
  final Future<List<CameraDescription>> Function()? availableCamerasLoader;

  @visibleForTesting
  final Future<Uint8List?> Function()? fallbackPhotoLoader;

  @override
  State<IncidentInAppCamera> createState() => _IncidentInAppCameraState();
}

class _IncidentInAppCameraState extends State<IncidentInAppCamera> {
  CameraController? _controller;
  bool _initializing = true;
  String? _error;
  bool _capturing = false;
  bool _recording = false;
  bool _stoppingVideo = false;
  bool _selectingFallbackPhoto = false;
  Timer? _videoTimer;
  DateTime? _videoStartedAt;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    _videoTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleVideo() async {
    final controller = _controller;
    if (controller == null ||
        _capturing ||
        _stoppingVideo ||
        widget.onVideoCaptured == null) {
      return;
    }
    try {
      if (_recording) {
        setState(() => _stoppingVideo = true);
        _videoTimer?.cancel();
        final file = await controller.stopVideoRecording();
        final bytes = await file.readAsBytes();
        final contentType = IncidentVideoFormat.contentTypeFor(
          reportedMimeType: file.mimeType,
          fileName: file.path,
        );
        final startedAt = _videoStartedAt ?? DateTime.now();
        final elapsed = DateTime.now().difference(startedAt);
        if (bytes.isNotEmpty) {
          widget.onVideoCaptured!(
            bytes,
            elapsed > const Duration(seconds: 15)
                ? const Duration(seconds: 15)
                : elapsed,
            contentType,
          );
        }
        if (mounted) {
          setState(() {
            _recording = false;
            _stoppingVideo = false;
            _videoStartedAt = null;
          });
        }
        return;
      }
      await controller.startVideoRecording();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _videoStartedAt = DateTime.now();
      });
      _videoTimer = Timer(const Duration(seconds: 15), () async {
        if (mounted && _recording) await _toggleVideo();
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not record video.'),
            backgroundColor: Color(0xFFF87171),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _stoppingVideo = false;
          _videoStartedAt = null;
        });
      }
    }
  }

  List<CameraDescription> _orderedCameras(List<CameraDescription> cameras) {
    const priority = <CameraLensDirection, int>{
      CameraLensDirection.back: 0,
      CameraLensDirection.external: 1,
      CameraLensDirection.front: 2,
    };
    final ordered = List<CameraDescription>.of(cameras);
    ordered.sort(
      (a, b) => (priority[a.lensDirection] ?? 3).compareTo(
        priority[b.lensDirection] ?? 3,
      ),
    );
    return ordered;
  }

  Future<void> _disposeController(CameraController? controller) async {
    if (controller == null) return;
    try {
      await controller.dispose();
    } catch (_) {
      // A failed browser camera may already have released its media stream.
    }
  }

  Future<Uint8List?> _loadFallbackPhoto() async {
    final loader = widget.fallbackPhotoLoader;
    if (loader != null) return loader();

    final useDeviceCapture =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    final file = await ImagePicker().pickImage(
      source: useDeviceCapture ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2048,
      requestFullMetadata: false,
    );
    return file?.readAsBytes();
  }

  Future<void> _selectFallbackPhoto() async {
    if (_selectingFallbackPhoto || _capturing) return;
    setState(() => _selectingFallbackPhoto = true);
    try {
      final bytes = await _loadFallbackPhoto();
      if (bytes == null) return;
      if (bytes.isEmpty) {
        throw const FormatException('The selected photo is empty.');
      }
      widget.onPhotoCaptured(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not use that photo. Choose another image.'),
          backgroundColor: Color(0xFFF87171),
        ),
      );
    } finally {
      if (mounted) setState(() => _selectingFallbackPhoto = false);
    }
  }

  Future<void> _initCamera() async {
    CameraException? lastCameraError;
    try {
      final oldController = _controller;
      _controller = null;
      await _disposeController(oldController);

      final cameraLoader = widget.availableCamerasLoader;
      final cameras = cameraLoader == null
          ? await availableCameras()
          : await cameraLoader();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() {
          _error =
              'No camera was detected. Connect a camera or use the photo option below.';
          _initializing = false;
        });
        return;
      }

      for (final description in _orderedCameras(cameras)) {
        for (final resolution in const [
          ResolutionPreset.medium,
          ResolutionPreset.low,
        ]) {
          final controller = CameraController(
            description,
            resolution,
            enableAudio: false,
          );
          try {
            await controller.initialize();
            if (!mounted) {
              await _disposeController(controller);
              return;
            }
            setState(() {
              _controller = controller;
              _initializing = false;
              _error = null;
            });
            return;
          } on CameraException catch (e) {
            lastCameraError = e;
            await _disposeController(controller);
          } catch (_) {
            await _disposeController(controller);
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _error = lastCameraError == null
            ? 'The available camera could not be started. Use the photo option below.'
            : _messageForCameraError(lastCameraError);
        _initializing = false;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _messageForCameraError(e);
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = kIsWeb
            ? 'Could not start camera. Use https or localhost and allow camera access.'
            : 'Could not start camera. Check permission in device settings.';
        _initializing = false;
      });
    }
  }

  String _messageForCameraError(CameraException e) {
    final code = e.code.toLowerCase();
    final description = (e.description ?? '').toLowerCase();
    if (code.contains('accessdenied') || description.contains('permission')) {
      return 'Camera access is blocked. Allow camera access in the browser or use the photo option below.';
    }
    if (code.contains('notfound')) {
      return 'No camera was detected. Connect a camera or use the photo option below.';
    }
    if (code.contains('notreadable')) {
      return 'The camera is busy or unavailable. Close other apps using it, then retry.';
    }
    if (code.contains('overconstrained')) {
      return 'This camera does not support the requested mode. Retry or use the photo option below.';
    }
    if (code.contains('security') || code.contains('cameratype')) {
      return 'Camera access requires HTTPS or localhost and browser camera permission.';
    }
    return 'The camera could not be started. Retry or use the photo option below.';
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final xFile = await controller.takePicture();
      final bytes = await xFile.readAsBytes();
      widget.onPhotoCaptured(bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not take photo. Try again.'),
          backgroundColor: Color(0xFFF87171),
        ),
      );
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Widget _buildContent() {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_initializing)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFFEF4444)),
          )
        else if (_error != null)
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.no_photography_rounded,
                      color: Color(0xFFF87171),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Camera unavailable',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFCA5A5),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _selectingFallbackPhoto
                            ? null
                            : _selectFallbackPhoto,
                        icon: _selectingFallbackPhoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.add_a_photo_rounded),
                        label: Text(
                          _selectingFallbackPhoto
                              ? 'Opening…'
                              : 'Capture or choose photo',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _selectingFallbackPhoto
                            ? null
                            : () {
                                setState(() {
                                  _initializing = true;
                                  _error = null;
                                });
                                _initCamera();
                              },
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white38),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'A photo is required. Video evidence is optional.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          )
        else if (_controller != null && _controller!.value.isInitialized)
          LayoutBuilder(
            builder: (context, constraints) {
              final preview = _controller!.value.previewSize;
              if (preview == null) {
                return CameraPreview(_controller!);
              }
              return FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: preview.height,
                  height: preview.width,
                  child: CameraPreview(_controller!),
                ),
              );
            },
          ),
        if (!_initializing && _error == null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 32, 16, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.8),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _capturing || _recording ? null : _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      alignment: Alignment.center,
                      child: _capturing
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Container(
                              width: 56,
                              height: 56,
                              decoration: const BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                    ),
                  ),
                  if (widget.onVideoCaptured != null) ...[
                    const SizedBox(width: 20),
                    GestureDetector(
                      onTap: _capturing ? null : _toggleVideo,
                      child: Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _recording ? Colors.red : Colors.black54,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _recording
                              ? Icons.stop_rounded
                              : Icons.videocam_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (!_initializing && _error == null)
          const Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Text(
              'Record up to 15 seconds if needed, then capture the required photo',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      color: Colors.black,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
    );

    if (widget.height.isFinite) {
      return Container(
        height: widget.height,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: _buildContent(),
      );
    }

    return Container(
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: _buildContent(),
    );
  }
}
