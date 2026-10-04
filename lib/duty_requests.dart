import 'package:flutter/material.dart';
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models/accomplishment_photo.dart';
import 'services/accomplishment_photo_picker.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

export 'letter_request.dart';

class AccomplishmentReportScreen extends StatefulWidget {
  const AccomplishmentReportScreen({
    super.key,
    required this.scheduleId,
    this.pickPhoto,
    this.submitReport,
  });
  final String scheduleId;
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
  final _summary = TextEditingController();
  final _narrative = TextEditingController();
  final _issues = TextEditingController();
  bool _saving = false;
  bool _picking = false;
  AccomplishmentPhoto? _photo;
  bool get _locked =>
      _saving || _picking || (_photo?.submissionUncertain ?? false);
  @override
  void dispose() {
    _summary.dispose();
    _narrative.dispose();
    _issues.dispose();
    super.dispose();
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
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(
                            _photo!.bytes,
                            height: 320,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Text(
                              'Photo preview unavailable. Choose another image.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _photo!.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton.icon(
                        onPressed: _locked ? null : _pickPhoto,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _picking
                              ? 'Opening photos…'
                              : _photo == null
                              ? 'Upload photo report'
                              : 'Replace photo',
                        ),
                      ),
                      const Text('Photo required · JPG or PNG · Up to 10 MB'),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _summary,
                        enabled: !_locked,
                        maxLength: 1500,
                        maxLines: 2,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Duty summary',
                          hintText: 'Key tasks completed',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _narrative,
                        enabled: !_locked,
                        maxLength: 5000,
                        minLines: 6,
                        maxLines: 10,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Detailed narrative',
                          hintText:
                              'Describe activities, observations, patrols, and handover.',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _issues,
                        enabled: !_locked,
                        maxLength: 1500,
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Issues encountered (optional)',
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _saving || _picking ? null : _submit,
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
  Future<void> _pickPhoto() async {
    setState(() => _picking = true);
    try {
      final photo =
          await (widget.pickPhoto ?? AccomplishmentPhotoPicker.pick)();
      if (photo == null || !mounted) return;
      final previous = _photo;
      setState(() => _photo = photo);
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
                  : 'Could not open this photo. Choose a JPG or PNG and try again.',
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
    if (_summary.text.trim().isEmpty || _narrative.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Complete the required summary and detailed narrative.',
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await (widget.submitReport ?? DutyRequestService.submitAccomplishment)(
        scheduleId: widget.scheduleId,
        summary: _summary.text,
        narrative: _narrative.text,
        issues: _issues.text,
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
