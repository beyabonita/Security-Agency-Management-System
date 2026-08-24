import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/services/duty_request_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

class ShiftChangeRequestScreen extends StatefulWidget {
  const ShiftChangeRequestScreen({super.key});
  @override
  State<ShiftChangeRequestScreen> createState() =>
      _ShiftChangeRequestScreenState();
}

class _ShiftChangeRequestScreenState extends State<ShiftChangeRequestScreen> {
  final _reason = TextEditingController();
  late Future<List<Map<String, dynamic>>> _schedulesFuture;
  String? _scheduleId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _schedulesFuture = _loadSchedules();
  }

  Future<List<Map<String, dynamic>>> _loadSchedules() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return Future.error('Your session has expired. Sign in again.');
    }
    return DutyRequestService.upcomingSchedules(user.id);
  }

  void _retrySchedules() {
    setState(() => _schedulesFuture = _loadSchedules());
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          children: [
            GuardPageTopBar(
              title: 'Shift change',
              subtitle: 'Submit a request for Inspector review',
              onBack: () => Navigator.pop(context),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _schedulesFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return GuardEmptyState(
                      icon: Icons.cloud_off_rounded,
                      title: 'Could not load duties',
                      message:
                          'Check your connection and try loading your schedules again.',
                      actionLabel: 'Try again',
                      onAction: _retrySchedules,
                    );
                  }
                  if (!snapshot.hasData) {
                    return const GuardLoadingView(
                      label: 'Loading available duties…',
                    );
                  }
                  final schedules = snapshot.data!;
                  if (schedules.isEmpty) {
                    return const GuardEmptyState(
                      icon: Icons.event_busy_outlined,
                      title: 'No upcoming duties',
                      message:
                          'An approved upcoming schedule is needed before you can request a change.',
                    );
                  }
                  return ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    children: [
                      const GuardPageHeader(
                        title: 'Request details',
                        subtitle:
                            'Choose the duty that needs changing and explain why.',
                      ),
                      const SizedBox(height: 16),
                      GuardSurfaceCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: AppColors.surfaceMuted,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.swap_horiz_rounded,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text(
                                    'Change request details',
                                    style: TextStyle(
                                      color: AppColors.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              initialValue: _scheduleId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Duty schedule',
                              ),
                              items: schedules.map((s) {
                                final start = DateTime.tryParse(
                                  s['start_at'].toString(),
                                )?.toLocal();
                                return DropdownMenuItem(
                                  value: s['id'].toString(),
                                  child: Text(
                                    '${s['location_label'] ?? 'Duty site'} • ${start?.toString().substring(0, 16) ?? ''}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                );
                              }).toList(),
                              onChanged: (value) =>
                                  setState(() => _scheduleId = value),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _reason,
                              minLines: 4,
                              maxLines: 6,
                              textCapitalization: TextCapitalization.sentences,
                              decoration: const InputDecoration(
                                labelText: 'Reason for shift change',
                                hintText:
                                    'Explain the requested change (minimum 5 characters).',
                              ),
                            ),
                            const SizedBox(height: 22),
                            FilledButton(
                              onPressed: _saving ? null : _submit,
                              child: GuardBusyLabel(
                                busy: _saving,
                                label: 'Send to Inspector',
                                busyLabel: 'Sending request…',
                                icon: Icons.send_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (_scheduleId == null || _reason.text.trim().length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a schedule and enter a reason.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await DutyRequestService.requestShiftChange(
        scheduleId: _scheduleId!,
        reason: _reason.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent to your Inspector.')),
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
    backgroundColor: AppColors.scaffold,
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
                          hintText: 'Key tasks completed (10+ characters)',
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
                              'Describe activities, observations, patrols, and handover (20+ characters).',
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
    if (_summary.text.trim().length < 10 ||
        _narrative.text.trim().length < 20) {
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
