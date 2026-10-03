import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_application_1/services/incident_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/incident_in_app_camera.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

/// Pick a type, capture a photo or video, and send the emergency report.
class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  String _category = 'crime';
  Uint8List? _photoBytes;
  Uint8List? _videoBytes;
  DateTime? _evidenceCapturedAt;
  int? _videoDurationSeconds;
  String? _videoContentType;
  int _cameraSession = 0;
  final _remarksController = TextEditingController();
  bool _submitting = false;
  double? _latitude;
  double? _longitude;

  @override
  void initState() {
    super.initState();
    _captureLocation();
  }

  Future<void> _captureLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = pos.latitude;
        _longitude = pos.longitude;
      });
    } catch (_) {}
  }

  void _onPhotoCaptured(Uint8List bytes) {
    if (!mounted || _submitting || bytes.isEmpty) return;
    setState(() {
      _photoBytes = bytes;
      _videoBytes = null;
      _videoDurationSeconds = null;
      _videoContentType = null;
      _evidenceCapturedAt = DateTime.now().toUtc();
    });
  }

  void _onVideoCaptured(
    Uint8List bytes,
    Duration duration,
    String contentType,
  ) {
    if (!mounted || _submitting || bytes.isEmpty) return;
    setState(() {
      _photoBytes = null;
      _videoBytes = bytes;
      _evidenceCapturedAt = DateTime.now().toUtc();
      _videoDurationSeconds = duration.inSeconds.clamp(1, 15);
      _videoContentType = contentType;
    });
  }

  void _retakeEvidence() {
    setState(() {
      _photoBytes = null;
      _videoBytes = null;
      _videoDurationSeconds = null;
      _videoContentType = null;
      _evidenceCapturedAt = null;
      _cameraSession++;
    });
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if ((_photoBytes == null && _videoBytes == null) ||
        _evidenceCapturedAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Capture a photo or record a video first.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await IncidentService.submitReport(
        category: _category,
        photoBytes: _photoBytes,
        remarks: _remarksController.text,
        capturedAt: _evidenceCapturedAt!,
        videoBytes: _videoBytes,
        videoDurationSeconds: _videoDurationSeconds,
        videoContentType: _videoContentType,
        latitude: _latitude,
        longitude: _longitude,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency alert sent ✓'),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _photoBytes != null;
    final hasVideo = _videoBytes != null;
    final hasEvidence = hasPhoto || hasVideo;

    return Scaffold(
      backgroundColor: AppColors.of(context).scaffold,
      body: SafeArea(
        child: Column(
          children: [
            GuardPageTopBar(
              title: 'Emergency alert',
              subtitle: 'Capture evidence and describe the incident',
              leadingIcon: Icons.close_rounded,
              onBack: _submitting ? null : () => Navigator.pop(context),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GuardSurfaceCard(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incident type',
                      style: TextStyle(
                        color: AppColors.of(context).text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: IncidentService.categories.entries.map((e) {
                        final selected = _category == e.key;
                        return ChoiceChip(
                          label: Text(e.value),
                          selected: selected,
                          onSelected: _submitting
                              ? null
                              : (v) {
                                  if (v) setState(() => _category = e.key);
                                },
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.of(context).surface,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppColors.of(context).textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.of(context).border,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GuardSurfaceCard(
                padding: const EdgeInsets.all(14),
                child: TextField(
                  controller: _remarksController,
                  minLines: 2,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  enabled: !_submitting,
                  decoration: const InputDecoration(
                    labelText: 'Incident narrative (required)',
                    hintText: 'What happened? Include immediate actions taken.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: hasVideo
                    ? GuardSurfaceCard(
                        padding: const EdgeInsets.all(16),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_rounded,
                                  size: 48,
                                  color: AppColors.of(context).success,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Video ready',
                                  style: TextStyle(
                                    color: AppColors.of(context).text,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '$_videoDurationSeconds-second recording',
                                  style: TextStyle(
                                    color: AppColors.of(context).textMuted,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : _retakeEvidence,
                                  icon: const Icon(Icons.refresh_rounded),
                                  label: const Text('Retake video'),
                                ),
                                TextButton(
                                  onPressed: _submitting
                                      ? null
                                      : _retakeEvidence,
                                  child: const Text('Use a photo instead'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : hasPhoto
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.memory(
                              _photoBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton.filled(
                              onPressed: _submitting ? null : _retakeEvidence,
                              tooltip: 'Retake photo or record video',
                              icon: const Icon(Icons.refresh_rounded),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                              ),
                            ),
                          ),
                        ],
                      )
                    : IncidentInAppCamera(
                        key: ValueKey(_cameraSession),
                        onPhotoCaptured: _onPhotoCaptured,
                        onVideoCaptured: _onVideoCaptured,
                        height: double.infinity,
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (_submitting || !hasEvidence) ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.of(context).surfaceMuted,
                    disabledForegroundColor: AppColors.of(context).textHint,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: GuardBusyLabel(
                    busy: _submitting,
                    label: hasEvidence
                        ? 'Send emergency alert'
                        : 'Capture photo or video to continue',
                    busyLabel: 'Sending alert…',
                    icon: Icons.emergency_rounded,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
