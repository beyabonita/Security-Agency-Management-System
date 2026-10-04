import 'dart:async';
import 'package:flutter/material.dart';
import 'models/dtr_alignment.dart';
import 'models/request_letter.dart';
import 'services/duty_request_service.dart';
import 'services/request_letter_picker.dart';
import 'theme/app_colors.dart';
import 'widgets/guard_ui.dart';

class ShiftChangeRequestScreen extends StatefulWidget {
  const ShiftChangeRequestScreen({super.key, this.gateway, this.pickLetter});
  final DutyRequestGateway? gateway;
  final Future<RequestLetter?> Function()? pickLetter;
  @override
  State<ShiftChangeRequestScreen> createState() =>
      _ShiftChangeRequestScreenState();
}

class _ShiftChangeRequestScreenState extends State<ShiftChangeRequestScreen> {
  final _reason = TextEditingController();
  late final DutyRequestGateway _gateway;
  late Future<DutyRequestData> _data;
  String _type = 'absence';
  String? _scheduleId;
  String? _targetScheduleId;
  bool _coverage = false;
  bool get _requiresTarget => _type == 'swap' && !_coverage;
  Future<List<Map<String, dynamic>>>? _swapOptions;
  RequestLetter? _letter;
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _gateway = widget.gateway ?? const SupabaseDutyRequestGateway();
    _data = _gateway.load();
  }

  void _reload() => setState(() {
    _data = _gateway.load();
    _loadSwapOptions();
  });

  void _loadSwapOptions() {
    _targetScheduleId = null;
    _swapOptions = _requiresTarget && _scheduleId != null
        ? _gateway.swapOptions(_scheduleId!)
        : null;
    // The dropdown can be below the ListView viewport. Observe early failures
    // immediately; its FutureBuilder still receives and renders the same error.
    _swapOptions?.ignore();
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : null,
      ),
    );
  }

  Future<void> _discard(RequestLetter? letter) async {
    if (letter == null) return;
    try {
      await _gateway.discard(letter);
    } catch (_) {
      _message(
        'Could not clean up the unused upload. Your filed requests are safe.',
        error: true,
      );
    }
  }

  Future<void> _pickLetter() async {
    if (_saving || _picking) return;
    setState(() => _picking = true);
    try {
      final letter = await (widget.pickLetter ?? RequestLetterPicker.pick)();
      if (letter == null || !mounted) return;
      final old = _letter;
      setState(() => _letter = letter);
      await _discard(old);
    } catch (error) {
      _message(
        error is FormatException
            ? error.message
            : 'Could not read this file. Save it to Downloads, then attach it again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (_scheduleId == null ||
        (_requiresTarget && _targetScheduleId == null) ||
        _reason.text.trim().length < 5 ||
        _letter == null) {
      _message(
        _requiresTarget
            ? 'Choose both duties, enter a reason, and attach your letter.'
            : 'Choose a duty, enter a reason, and attach your letter.',
        error: true,
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await _gateway.submit(
        scheduleId: _scheduleId!,
        reason: _reason.text,
        requestType: _type,
        letter: _letter!,
        targetScheduleId: _requiresTarget ? _targetScheduleId : null,
      );
      if (!mounted) return;
      setState(() {
        _letter = null;
        _scheduleId = null;
        _targetScheduleId = null;
        _swapOptions = null;
        _reason.clear();
        _data = _gateway.load();
      });
      _message(
        _requiresTarget
            ? 'Swap request sent to the selected Guard for approval.'
            : 'Request and letter sent to Operations Head.',
      );
    } catch (error) {
      _message(dutyRequestErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    unawaited(_discard(_letter));
    _reason.dispose();
    super.dispose();
  }

  String _status(String value) => switch (value) {
    'pending_admin' ||
    'pending_inspector' => 'Awaiting Operational Head approval',
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    _ => 'Cancelled',
  };

  Future<void> _respondToSwap(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approve ? 'Accept this shift swap?' : 'Decline this shift swap?',
        ),
        content: Text(
          approve
              ? 'Operations Head will review the exchange next. Your schedule changes only after final approval.'
              : 'Your duties will stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Accept swap' : 'Decline swap'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await _gateway.respondToSwap(request['id'].toString(), approve);
      if (!mounted) return;
      _message(
        approve
            ? 'Swap sent to Operations Head for final approval.'
            : 'Swap declined.',
      );
      _reload();
    } catch (error) {
      _message(dutyRequestErrorMessage(error), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _dutyLabel(Map<String, dynamic> schedule) {
    final start = DateTime.tryParse(schedule['start_at']?.toString() ?? '');
    final end = DateTime.tryParse(schedule['end_at']?.toString() ?? '');
    if (start == null || end == null) return 'Duty dates unavailable';
    String time(DateTime date) {
      final ph = DtrAlignment.inManila(date);
      final hour = ph.hour % 12 == 0 ? 12 : ph.hour % 12;
      return '$hour:${ph.minute.toString().padLeft(2, '0')} ${ph.hour < 12 ? 'AM' : 'PM'}';
    }

    final period = switch (DtrAlignment.normalizePeriod(
      schedule['dtr_period']?.toString(),
    )) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'overtime' => 'Overtime',
      _ => 'Duty shift',
    };
    final nextDay =
        DtrAlignment.dateString(start) != DtrAlignment.dateString(end)
        ? ' (+1 day)'
        : '';
    return '${schedule['duty_date'] ?? DtrAlignment.dateString(start)} · $period · ${time(start)}–${time(end)}$nextDay';
  }

  Widget _swapPicker() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _swapOptions,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: GuardBusyLabel(
            busy: true,
            label: 'Available duties',
            busyLabel: 'Finding available duties…',
          ),
        );
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            const Text(
              'Could not load other Guards’ duties. Your letter is still selected.',
            ),
            TextButton(
              onPressed: () => setState(_loadSwapOptions),
              child: const Text('Retry swap options'),
            ),
          ],
        );
      }
      final options = snapshot.data ?? [];
      if (options.isEmpty) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'No eligible duties to swap with. Another active Guard needs an unstarted duty with no pending request, and neither Guard can have an overlapping duty after the exchange.',
            ),
            TextButton(
              onPressed: () => setState(_loadSwapOptions),
              child: const Text('Refresh swap options'),
            ),
          ],
        );
      }
      final selected = options
          .where((s) => s['id'] == _targetScheduleId)
          .firstOrNull;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            key: ValueKey('swap-${_scheduleId ?? ''}-${selected?['id'] ?? ''}'),
            initialValue: selected?['id']?.toString(),
            isExpanded: true,
            itemHeight: 104,
            decoration: const InputDecoration(
              labelText: 'Swap with another Guard’s duty',
            ),
            selectedItemBuilder: (_) => options
                .map(
                  (s) => Text(
                    s['guard_name'].toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )
                .toList(),
            items: options
                .map(
                  (s) => DropdownMenuItem(
                    value: s['id'].toString(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s['guard_name'].toString(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _dutyLabel(s),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          s['location_label']?.toString() ?? 'Assigned post',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            onChanged: (id) => setState(() => _targetScheduleId = id),
          ),
          if (selected != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'You will take: ${_dutyLabel(selected)}\nPost: ${selected['location_label'] ?? 'Assigned post'}',
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return PopScope(
      canPop: !_saving && !_picking,
      child: Scaffold(
        backgroundColor: colors.scaffold,
        body: SafeArea(
          child: Column(
            children: [
              GuardPageTopBar(
                title: 'Letter requests',
                subtitle: 'Absence, relief and shift swaps',
                onBack: () {
                  if (!_saving && !_picking) Navigator.pop(context);
                },
              ),
              Expanded(
                child: FutureBuilder<DutyRequestData>(
                  future: _data,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return GuardEmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Could not load requests',
                        message: dutyRequestLoadErrorMessage(snapshot.error!),
                        actionLabel: 'Try again',
                        onAction: _reload,
                      );
                    }
                    if (!snapshot.hasData) {
                      return const GuardLoadingView(
                        label: 'Loading duties and requests…',
                      );
                    }
                    final requests = snapshot.data!.requests;
                    final pending = requests
                        .where(
                          (r) => [
                            'pending_admin',
                            'pending_inspector',
                          ].contains(r['status']),
                        )
                        .expand(
                          (r) => [
                            r['requested_schedule_id'],
                            r['target_schedule_id'],
                          ],
                        )
                        .toSet();
                    final duties = snapshot.data!.schedules
                        .where((s) => !pending.contains(s['id']))
                        .toList();
                    final selectedId = duties.any((s) => s['id'] == _scheduleId)
                        ? _scheduleId
                        : null;
                    if (selectedId != null &&
                        scheduleHasAttendance(
                          duties.firstWhere(
                            (s) => s['id'] == selectedId,
                          )['attendance_sessions'],
                        )) {
                      _coverage = true;
                    }
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                      children: [
                        GuardSurfaceCard(
                          child: AbsorbPointer(
                            absorbing: _saving,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Submit a duty request',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'swap',
                                      label: Text('Swap Duty'),
                                      icon: Icon(Icons.swap_horiz),
                                    ),
                                    ButtonSegment(
                                      value: 'absence',
                                      label: Text('Absent'),
                                      icon: Icon(Icons.event_busy),
                                    ),
                                  ],
                                  selected: {_type},
                                  onSelectionChanged: (value) => setState(() {
                                    _type = value.first;
                                    _loadSwapOptions();
                                  }),
                                ),
                                const SizedBox(height: 18),
                                if (duties.isEmpty) ...[
                                  Text(
                                    snapshot.data!.schedules.isEmpty
                                        ? 'No eligible duty yet. Choose a duty scheduled today, an ongoing overnight duty, or a future duty.'
                                        : 'All available duties already have a pending request. Check My requests below for the Operational Head decision.',
                                    style: TextStyle(color: colors.textMuted),
                                  ),
                                  const SizedBox(height: 14),
                                ],
                                DropdownButtonFormField<String>(
                                  key: ValueKey(selectedId),
                                  initialValue: selectedId,
                                  isExpanded: true,
                                  itemHeight: 80,
                                  decoration: const InputDecoration(
                                    labelText: 'Duty date and period',
                                  ),
                                  selectedItemBuilder: (context) => duties
                                      .map(
                                        (s) => Text(
                                          _dutyLabel(s),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      )
                                      .toList(),
                                  items: duties
                                      .map(
                                        (s) => DropdownMenuItem(
                                          value: s['id'].toString(),
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _dutyLabel(s),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                s['location_label']
                                                        ?.toString() ??
                                                    'Assigned post',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: colors.textMuted,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: duties.isEmpty
                                      ? null
                                      : (value) => setState(() {
                                          _scheduleId = value;
                                          _coverage = scheduleHasAttendance(
                                            duties.firstWhere(
                                              (s) => s['id'] == value,
                                            )['attendance_sessions'],
                                          );
                                          _loadSwapOptions();
                                        }),
                                ),
                                if (selectedId != null) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    _dutyLabel(
                                      duties.firstWhere(
                                        (s) => s['id'] == selectedId,
                                      ),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                if (_type == 'swap' && selectedId != null) ...[
                                  Material(
                                    color: Colors.transparent,
                                    child: SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text(
                                        'Request a replacement Guard',
                                      ),
                                      subtitle: const Text(
                                        'Use this if you feel unwell or cannot finish duty. The Operational Head chooses the replacement.',
                                      ),
                                      value: _coverage,
                                      onChanged:
                                          scheduleHasAttendance(
                                            duties.firstWhere(
                                              (s) => s['id'] == selectedId,
                                            )['attendance_sessions'],
                                          )
                                          ? null
                                          : (value) => setState(() {
                                              _coverage = value;
                                              _loadSwapOptions();
                                            }),
                                    ),
                                  ),
                                  if (!_coverage) _swapPicker(),
                                  const SizedBox(height: 12),
                                ],
                                Text(
                                  _type == 'swap' && _coverage
                                      ? 'Your existing Time In and worked hours stay on your DTR. The Operational Head confirms any missing Time Out and assigns the remaining duty to a replacement.'
                                      : _type == 'swap'
                                      ? 'The selected Guard approves or declines first. If accepted, Operations Head reviews the exchange. Your duties change only after final approval.'
                                      : 'Applies only to the selected duty period. For a whole-day absence, submit a letter request for each assigned period. Only Operational Head can approve it.',
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                TextField(
                                  controller: _reason,
                                  minLines: 3,
                                  maxLines: 5,
                                  maxLength: 1500,
                                  decoration: InputDecoration(
                                    labelText: 'Reason',
                                    hintText: _type == 'swap'
                                        ? 'Explain why you want to exchange these duty periods.'
                                        : 'Explain why you need to be absent.',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _picking ? null : _pickLetter,
                                  icon: const Icon(Icons.attach_file),
                                  label: Text(
                                    _picking
                                        ? 'Opening files…'
                                        : _letter == null
                                        ? 'Attach request letter'
                                        : 'Replace letter',
                                  ),
                                ),
                                if (_letter != null)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.description_outlined,
                                    ),
                                    title: Text(
                                      _letter!.name,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      '${(_letter!.bytes.length / 1024).ceil()} KB',
                                    ),
                                    trailing: IconButton(
                                      tooltip: 'Remove letter',
                                      icon: const Icon(Icons.close),
                                      onPressed: () async {
                                        final letter = _letter;
                                        setState(() => _letter = null);
                                        await _discard(letter);
                                      },
                                    ),
                                  ),
                                Text(
                                  'Required · PDF, JPG or PNG · Up to 5 MB',
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                FilledButton(
                                  onPressed:
                                      _saving ||
                                          _picking ||
                                          selectedId == null ||
                                          (_requiresTarget &&
                                              _targetScheduleId == null)
                                      ? null
                                      : _submit,
                                  child: GuardBusyLabel(
                                    busy: _saving,
                                    label: _requiresTarget
                                        ? 'Send to selected Guard'
                                        : 'Send to Operations Head',
                                    busyLabel: 'Uploading & submitting…',
                                    icon: Icons.send_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'My requests & swap invitations',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Refresh requests',
                              onPressed: _saving ? null : _reload,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        if (requests.isEmpty)
                          const GuardSurfaceCard(
                            child: Text('No requests yet.'),
                          ),
                        ...requests.map(
                          (r) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GuardSurfaceCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${r['is_incoming'] == true
                                        ? 'Swap invitation'
                                        : r['request_type'] == 'absence'
                                        ? 'Absence'
                                        : 'Swap'} · ${r['guard_response'] == 'pending'
                                        ? 'Awaiting Guard approval'
                                        : r['guard_response'] == 'declined'
                                        ? 'Declined by Guard'
                                        : _status(r['status'].toString())}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (r['exchange_snapshot'] is Map) ...[
                                    Text(
                                      '${r['exchange_snapshot']['requester_name']} offers: ${_dutyLabel(Map<String, dynamic>.from(r['exchange_snapshot']['offered']))}',
                                    ),
                                    Text(
                                      '${r['exchange_snapshot']['target_name']} exchanges: ${_dutyLabel(Map<String, dynamic>.from(r['exchange_snapshot']['requested']))}',
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  if (r['requested_duty']
                                      is Map<String, dynamic>) ...[
                                    Text(
                                      _dutyLabel(
                                        r['requested_duty']
                                            as Map<String, dynamic>,
                                      ),
                                      style: TextStyle(
                                        color: colors.textMuted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                  Text(r['reason'] ?? ''),
                                  if (r['is_incoming'] == true &&
                                      r['guard_response'] == 'pending' &&
                                      r['status'] == 'pending_admin')
                                    Wrap(
                                      spacing: 12,
                                      children: [
                                        FilledButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _respondToSwap(r, true),
                                          child: const Text('Approve swap'),
                                        ),
                                        OutlinedButton(
                                          onPressed: _saving
                                              ? null
                                              : () => _respondToSwap(r, false),
                                          child: const Text('Decline swap'),
                                        ),
                                      ],
                                    ),
                                  if (r['letter_name'] != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Letter: ${r['letter_name']}',
                                        style: TextStyle(
                                          color: colors.textMuted,
                                        ),
                                      ),
                                    ),
                                  if ((r['admin_note'] ?? '')
                                      .toString()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Operational Head: ${r['admin_note']}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
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
      ),
    );
  }
}
