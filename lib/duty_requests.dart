import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models/accomplishment_photo.dart';
import 'services/accomplishment_photo_picker.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/device_verification_service.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/attendance_face_capture_dialog.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

export 'letter_request.dart';

class AccomplishmentReportScreen extends StatefulWidget {
  const AccomplishmentReportScreen({
    super.key,
    required this.scheduleId,
    this.scheduleData,
    this.pickPhoto,
    this.submitReport,
  });

  final String scheduleId;
  final Map<String, dynamic>? scheduleData;
  final Future<AccomplishmentPhoto?> Function()? pickPhoto;
  final Future<void> Function({
    required String scheduleId,
    required String summary,
    required String narrative,
    required String issues,
    required AccomplishmentPhoto photo,
  })?
  submitReport;

  @override
  State<AccomplishmentReportScreen> createState() =>
      _AccomplishmentReportScreenState();
}

class _AccomplishmentReportScreenState
    extends State<AccomplishmentReportScreen> {
  final _guardOnDutyController = TextEditingController();
  final _clientController = TextEditingController();
  final _postController = TextEditingController();
  final _timeInController = TextEditingController();
  final _timeOutController = TextEditingController();

  bool _saving = false;
  bool _picking = false;
  AccomplishmentPhoto? _photo;

  String _guardName = '';
  String _clientName = '';
  String _postName = '';
  String _timeInStr = '';
  String _timeOutStr = '';

  bool get _locked =>
      _saving || _picking || (_photo?.submissionUncertain ?? false);

  @override
  void initState() {
    super.initState();
    _loadDutyDetails();
  }

  @override
  void dispose() {
    _guardOnDutyController.dispose();
    _clientController.dispose();
    _postController.dispose();
    _timeInController.dispose();
    _timeOutController.dispose();
    super.dispose();
  }

  Future<void> _loadDutyDetails() async {
    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;

      // 1. Guard profile name
      if (user != null) {
        try {
          final profile = await UserProfileService.getProfile(user.id);
          if (profile != null) {
            final name = UserProfileService.displayName(profile);
            _guardName = name.startsWith('SG ') || name.startsWith('PSP ')
                ? name
                : 'SG $name';
          }
        } catch (_) {}
      }

      // 2. Schedule details
      Map<String, dynamic>? sched = widget.scheduleData;
      if (sched == null && widget.scheduleId.isNotEmpty) {
        try {
          final rows = await client
              .from('schedules')
              .select()
              .eq('id', widget.scheduleId)
              .maybeSingle();
          if (rows != null) sched = rows;
        } catch (_) {}
      }

      if (sched != null) {
        if (_guardName.isEmpty && sched['guard_name'] != null) {
          _guardName = sched['guard_name'].toString();
        }
        _clientName =
            (sched['location_label'] ?? sched['client_name'] ?? '').toString();
        _postName =
            (sched['location_address'] ??
                    sched['post'] ??
                    sched['duty_post'] ??
                    '')
                .toString();

        if (_clientName.isEmpty && sched['location_id'] != null) {
          try {
            final loc = await client
                .from('locations')
                .select('label, address')
                .eq('id', sched['location_id'])
                .maybeSingle();
            if (loc != null) {
              _clientName = loc['label']?.toString() ?? '';
              if (_postName.isEmpty) {
                _postName = loc['address']?.toString() ?? '';
              }
            }
          } catch (_) {}
        }
      }

      // 3. Attendance session for Time In & Time Out
      try {
        final sessionRow = await client
            .from('attendance_sessions')
            .select()
            .eq('schedule_id', widget.scheduleId)
            .maybeSingle();
        if (sessionRow != null) {
          final inAt = sessionRow['clock_in_at'] != null
              ? DateTime.tryParse(sessionRow['clock_in_at'].toString())?.toLocal()
              : null;
          final outAt = sessionRow['clock_out_at'] != null
              ? DateTime.tryParse(sessionRow['clock_out_at'].toString())?.toLocal()
              : null;
          if (inAt != null) _timeInStr = AttendanceService.formatTime(inAt);
          if (outAt != null) _timeOutStr = AttendanceService.formatTime(outAt);
        }
      } catch (_) {}

      // Fallbacks if not punched yet or using schedule times
      if (_timeInStr.isEmpty && sched != null && sched['start_at'] != null) {
        final st = DateTime.tryParse(sched['start_at'].toString())?.toLocal();
        if (st != null) _timeInStr = AttendanceService.formatTime(st);
      }
      if (_timeOutStr.isEmpty) {
        if (sched != null && sched['end_at'] != null) {
          final et = DateTime.tryParse(sched['end_at'].toString())?.toLocal();
          if (et != null) _timeOutStr = AttendanceService.formatTime(et);
        } else {
          _timeOutStr = AttendanceService.formatTime(DateTime.now());
        }
      }

      if (_clientName.isEmpty) _clientName = 'State University of Northern Negros';
      if (_postName.isEmpty) _postName = 'Roving and Assist';
      if (_guardName.isEmpty) _guardName = 'Security Guard';
      if (_timeInStr.isEmpty) _timeInStr = '07:00 AM';
      if (_timeOutStr.isEmpty) _timeOutStr = '07:00 PM';
    } catch (_) {}
  }

  void _populateFields() {
    if (_guardOnDutyController.text.isEmpty && _guardName.isNotEmpty) {
      _guardOnDutyController.text = _guardName;
    }
    if (_clientController.text.isEmpty && _clientName.isNotEmpty) {
      _clientController.text = _clientName;
    }
    if (_postController.text.isEmpty && _postName.isNotEmpty) {
      _postController.text = _postName;
    }
    if (_timeInController.text.isEmpty && _timeInStr.isNotEmpty) {
      _timeInController.text = _timeInStr;
    }
    if (_timeOutController.text.isEmpty && _timeOutStr.isNotEmpty) {
      _timeOutController.text = _timeOutStr;
    }
    if (mounted) setState(() {});
  }

  Widget _buildFieldCard({
    required String label,
    required TextEditingController controller,
    required String placeholder,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3D2D2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2A4A4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF8B2525),
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            enabled: !_locked,
            style: const TextStyle(
              color: Color(0xFF2A0808),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: placeholder,
              hintStyle: const TextStyle(
                color: Color(0xFFA56666),
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).scaffold,
    body: SafeArea(
      child: Column(
        children: [
          GuardPageTopBar(
            title: 'Accomplishment report',
            subtitle: 'Photo and written duty report',
            onBack: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                const GuardPageHeader(
                  title: 'Accomplishment report',
                  subtitle:
                      'Attach your finished photo report and add your duty details.',
                ),
                const SizedBox(height: 16),
                GuardSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_photo != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            _photo!.bytes,
                            height: 280,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Text(
                              'Photo preview unavailable. Retake face report.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _photo!.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.of(context).textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                      ],
                      OutlinedButton.icon(
                        onPressed: _locked ? null : _captureLiveFaceReport,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.face_retouching_natural_rounded),
                        label: Text(
                          _picking
                              ? 'Opening camera…'
                              : _photo == null
                              ? 'Capture live face report'
                              : 'Retake live face report',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildFieldCard(
                        label: 'Guard on Duty:',
                        controller: _guardOnDutyController,
                        placeholder: 'SG Guard Name',
                      ),
                      _buildFieldCard(
                        label: 'Client:',
                        controller: _clientController,
                        placeholder: 'State University of Northern Negros',
                      ),
                      _buildFieldCard(
                        label: 'Post:',
                        controller: _postController,
                        placeholder: 'Roving and Assist / Main Gate',
                      ),
                      _buildFieldCard(
                        label: 'Time in:',
                        controller: _timeInController,
                        placeholder: '07:00 AM',
                      ),
                      _buildFieldCard(
                        label: 'Time out:',
                        controller: _timeOutController,
                        placeholder: '07:00 PM',
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _saving || _picking ? null : _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: GuardBusyLabel(
                          busy: _saving,
                          label: _photo?.submissionUncertain == true
                              ? 'Retry submission'
                              : 'Submit report',
                          busyLabel: 'Submitting report…',
                          icon: Icons.assignment_turned_in_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _captureLiveFaceReport() async {
    setState(() => _picking = true);
    try {
      AccomplishmentPhoto? photo;
      if (widget.pickPhoto != null) {
        photo = await widget.pickPhoto!();
      } else {
        Position? position;
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 5),
          );
        } catch (_) {
          try {
            position = await Geolocator.getLastKnownPosition();
          } catch (_) {}
        }

        final devInfo = DeviceVerificationService.getDeviceInfoLabel();
        final devId = await DeviceVerificationService.getDeviceId();
        final deviceLabel = '$devInfo ($devId)';

        final dataUrl = await captureAttendanceFaceVerification(
          context,
          latitude: position?.latitude,
          longitude: position?.longitude,
          accuracyMeters: position?.accuracy,
          locationLabel: _clientName.isNotEmpty
              ? _clientName
              : 'State University of Northern Negros',
          deviceLabel: deviceLabel,
          actionLabel: 'Accomplishment Face Report',
        );

        if (dataUrl != null && dataUrl.isNotEmpty) {
          final comma = dataUrl.indexOf(',');
          final base64Str =
              comma != -1 ? dataUrl.substring(comma + 1) : dataUrl;
          final bytes = base64Decode(base64Str);
          photo = AccomplishmentPhoto(
            name:
                'accomplishment_${DateTime.now().millisecondsSinceEpoch}.jpg',
            bytes: bytes,
          );
        }
      }

      if (photo == null || !mounted) return;
      final previous = _photo;
      setState(() {
        _photo = photo;
        _populateFields();
      });
      if (previous != null) {
        unawaited(
          DutyRequestService.discardAccomplishmentPhoto(
            previous,
          ).catchError((Object _) {}),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'Could not capture face report. Try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_photo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attach your finished photo report.')),
      );
      return;
    }
    if (_guardOnDutyController.text.trim().isEmpty ||
        _clientController.text.trim().isEmpty ||
        _postController.text.trim().isEmpty ||
        _timeInController.text.trim().isEmpty ||
        _timeOutController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete all required duty details (Guard, Client, Post, Time in, Time out).',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final summary =
          'Duty Accomplishment Report - ${_clientController.text.trim()} (${_postController.text.trim()})';
      final narrative =
          'GUARD ON DUTY: ${_guardOnDutyController.text.trim()}\n'
          'CLIENT: ${_clientController.text.trim()}\n'
          'POST: ${_postController.text.trim()}\n'
          'TIME IN: ${_timeInController.text.trim()}\n'
          'TIME OUT: ${_timeOutController.text.trim()}';

      await (widget.submitReport ?? DutyRequestService.submitAccomplishment)(
        scheduleId: widget.scheduleId,
        summary: summary,
        narrative: narrative,
        issues: '',
        photo: _photo!,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Accomplishment report submitted.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PostgrestException
                  ? e.message
                  : e is TimeoutException || _photo?.submissionUncertain == true
                  ? 'Submission could not be confirmed. Retry with this photo to avoid a duplicate report.'
                  : e is StateError
                  ? e.message.toString()
                  : 'Could not submit the report. Check your connection and retry.',
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
