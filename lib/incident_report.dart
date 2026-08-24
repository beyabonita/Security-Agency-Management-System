import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_application_1/services/incident_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/incident_in_app_camera.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

/// Fast emergency flow: pick type → capture photo → send alert.
class IncidentReportScreen extends StatefulWidget {
  const IncidentReportScreen({super.key});

  @override
  State<IncidentReportScreen> createState() => _IncidentReportScreenState();
}

class _IncidentReportScreenState extends State<IncidentReportScreen> {
  String _category = 'crime';
  Uint8List? _photoBytes;
  Uint8List? _videoBytes;
  DateTime? _photoCapturedAt;
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
    setState(() {
      _photoBytes = bytes;
      _photoCapturedAt = DateTime.now().toUtc();
    });
  }

  void _onVideoCaptured(
    Uint8List bytes,
    Duration duration,
    String contentType,
  ) {
    setState(() {
      _videoBytes = bytes;
      _videoDurationSeconds = duration.inSeconds.clamp(1, 15);
      _videoContentType = contentType;
    });
  }

  void _retakePhoto() {
    setState(() {
      _photoBytes = null;
      _photoCapturedAt = null;
      _cameraSession++;
    });
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_photoBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Take a photo first'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    if (_remarksController.text.trim().length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Describe the incident before filing the alert.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await IncidentService.submitReport(
        category: _category,
        photoBytes: _photoBytes!,
        remarks: _remarksController.text,
        capturedAt: _photoCapturedAt ?? DateTime.now().toUtc(),
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

    return Scaffold(
      backgroundColor: AppColors.scaffold,
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
                    const Text(
                      'Incident type',
                      style: TextStyle(
                        color: AppColors.text,
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
                          onSelected: _submitting || hasPhoto
                              ? null
                              : (v) {
                                  if (v) setState(() => _category = e.key);
                                },
                          selectedColor: AppColors.primary,
                          backgroundColor: AppColors.surface,
                          labelStyle: TextStyle(
                            color: selected
                                ? Colors.white
                                : AppColors.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide(
                            color: selected
                                ? AppColors.primary
                                : AppColors.border,
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
                    labelText: 'Incident remarks (required)',
                    hintText: 'What happened? Include immediate actions taken.',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_videoBytes != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: GuardStatusBanner(
                  icon: Icons.videocam_rounded,
                  color: AppColors.success,
                  title: 'Video ready',
                  message:
                      '${_videoDurationSeconds ?? 15}-second incident video captured.',
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: hasPhoto
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
                              onPressed: _submitting ? null : _retakePhoto,
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
                  onPressed: (_submitting || !hasPhoto) ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.textHint,
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
                    label: hasPhoto
                        ? 'Send emergency alert'
                        : 'Capture photo to continue',
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
