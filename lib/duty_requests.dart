import 'package:flutter/material.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

export 'letter_request.dart';

class AccomplishmentReportScreen extends StatefulWidget {
  const AccomplishmentReportScreen({super.key, required this.scheduleId});
  final String scheduleId;
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
            subtitle: 'Complete your duty handover',
            onBack: () => Navigator.pop(context),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              children: [
                const GuardPageHeader(
                  title: 'Duty summary',
                  subtitle:
                      'Record completed work, observations, and handover details.',
                ),
                const SizedBox(height: 16),
                GuardSurfaceCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _summary,
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
                        minLines: 2,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          labelText: 'Issues encountered (optional)',
                        ),
                      ),
                      const SizedBox(height: 22),
                      FilledButton(
                        onPressed: _saving ? null : _submit,
                        child: GuardBusyLabel(
                          busy: _saving,
                          label: 'Submit report',
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
  Future<void> _submit() async {
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
      await DutyRequestService.submitAccomplishment(
        scheduleId: widget.scheduleId,
        summary: _summary.text,
        narrative: _narrative.text,
        issues: _issues.text,
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
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
