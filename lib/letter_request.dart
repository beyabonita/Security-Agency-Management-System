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
  String _swapScope = 'day';
  late DateTime _calendarMonth;
  bool _calendarMonthTouched = false;
  bool _coverage = false;
  bool get _requiresTarget => _type == 'swap' && !_coverage;
  Future<List<Map<String, dynamic>>>? _swapOptions;
  RequestLetter? _letter;
  bool _saving = false;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _calendarMonth = DateTime(now.year, now.month, 1);
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
        swapScope: _requiresTarget ? _swapScope : 'day',
      );
      if (!mounted) return;
      setState(() {
        _letter = null;
        _scheduleId = null;
        _targetScheduleId = null;
        _swapScope = 'day';
        _swapOptions = null;
        _reason.clear();
        _data = _gateway.load();
      });
      _message(
        _requiresTarget
            ? 'Swap request sent to Operations Head for approval.'
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

  String _requestStatusText(Map<String, dynamic> r) {
    final isExchange =
        r['target_schedule_id'] != null || r['exchange_snapshot'] is Map;
    if (!isExchange) {
      return _status(r['status'].toString());
    }
    final status = r['status']?.toString() ?? '';
    final guardResp = r['guard_response']?.toString();
    final adminApproved = r['admin_decision_at'] != null;
    if (status == 'approved') return 'Confirmed & scheduled';
    if (guardResp == 'declined') return 'Declined by Guard';
    if (status == 'rejected') return 'Rejected by Operations Head';
    if (status == 'pending_admin' && guardResp == 'pending') {
      return adminApproved
          ? 'Approved by Operations Head · Awaiting Guard confirmation'
          : 'Awaiting Operational Head approval';
    }
    return _status(status);
  }

  Future<void> _respondToSwap(
    Map<String, dynamic> request,
    bool approve,
  ) async {
    final isMonthly = request['swap_scope'] == 'month';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          approve ? 'Confirm & agree to this shift swap?' : 'Decline this shift swap?',
        ),
        content: Text(
          approve
              ? (isMonthly
                    ? 'Operations Head already approved this request. Confirming will automatically swap your shifts for the rest of the month and notify both the requesting Guard and Operations Head.'
                    : 'Operations Head already approved this request. Confirming will automatically swap your shift for this date and notify both the requesting Guard and Operations Head.')
              : 'Your duties will stay unchanged and both the requesting Guard and Operations Head will be notified.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Confirm swap' : 'Decline swap'),
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
            ? 'Swap confirmed! Your schedule has been automatically updated.'
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

  String _scheduleDateKey(Map<String, dynamic> schedule) {
    final stored = schedule['duty_date']?.toString();
    if (stored != null && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(stored)) {
      return stored;
    }
    final start = DateTime.tryParse(schedule['start_at']?.toString() ?? '');
    if (start != null) return DtrAlignment.dateString(start);
    return '';
  }

  DateTime? _parseDutyDate(String key) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return null;
    final parts = key.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2]);
  }

  void _selectDuty(Map<String, dynamic> duty) {
    setState(() {
      _scheduleId = duty['id']?.toString();
      _coverage = scheduleHasAttendance(duty['attendance_sessions']);
      final key = _scheduleDateKey(duty);
      final parsed = _parseDutyDate(key);
      if (parsed != null) {
        _calendarMonth = DateTime(parsed.year, parsed.month, 1);
      }
      _loadSwapOptions();
    });
  }

  Widget _buildDutyCalendarPicker(
    List<Map<String, dynamic>> duties,
    String? selectedId,
    AppPalette colors,
  ) {
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    final byDate = <String, List<Map<String, dynamic>>>{};
    for (final d in duties) {
      final key = _scheduleDateKey(d);
      if (key.isEmpty) continue;
      byDate.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(d);
    }

    DateTime activeMonth = _calendarMonth;
    if (!_calendarMonthTouched && duties.isNotEmpty) {
      final monthPrefix =
          '${activeMonth.year.toString().padLeft(4, '0')}-${activeMonth.month.toString().padLeft(2, '0')}-';
      final hasInMonth = byDate.keys.any((k) => k.startsWith(monthPrefix));
      if (!hasInMonth) {
        final firstKey = _scheduleDateKey(duties.first);
        final firstDate = _parseDutyDate(firstKey);
        if (firstDate != null) {
          activeMonth = DateTime(firstDate.year, firstDate.month, 1);
        }
      }
    }

    final firstOfMonth = DateTime(activeMonth.year, activeMonth.month, 1);
    final firstDayOffset = firstOfMonth.weekday % 7;
    final daysInMonth = DateTime(
      activeMonth.year,
      activeMonth.month + 1,
      0,
    ).day;
    final totalCells = ((firstDayOffset + daysInMonth + 6) ~/ 7) * 7;
    final rowCount = totalCells ~/ 7;

    final selectedDuty = duties.where((d) => d['id'] == selectedId).firstOrNull;
    final selectedDateKey =
        selectedDuty != null ? _scheduleDateKey(selectedDuty) : '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceMuted.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('swapCalendarPrevMonth'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Previous month',
                onPressed: duties.isEmpty
                    ? null
                    : () => setState(() {
                        _calendarMonthTouched = true;
                        _calendarMonth = DateTime(
                          activeMonth.year,
                          activeMonth.month - 1,
                          1,
                        );
                      }),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${monthNames[activeMonth.month - 1]} ${activeMonth.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('swapCalendarNextMonth'),
                visualDensity: VisualDensity.compact,
                tooltip: 'Next month',
                onPressed: duties.isEmpty
                    ? null
                    : () => setState(() {
                        _calendarMonthTouched = true;
                        _calendarMonth = DateTime(
                          activeMonth.year,
                          activeMonth.month + 1,
                          1,
                        );
                      }),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: weekdays
                .map(
                  (w) => Expanded(
                    child: Center(
                      child: Text(
                        w,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          for (int row = 0; row < rowCount; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: List.generate(7, (col) {
                  final idx = row * 7 + col;
                  final cellDate = DateTime(
                    activeMonth.year,
                    activeMonth.month,
                    1 - firstDayOffset + idx,
                  );
                  final isOutside =
                      cellDate.month != activeMonth.month ||
                      cellDate.year != activeMonth.year;
                  final key =
                      '${cellDate.year.toString().padLeft(4, '0')}-${cellDate.month.toString().padLeft(2, '0')}-${cellDate.day.toString().padLeft(2, '0')}';
                  final dayDuties = byDate[key] ?? const [];
                  final hasDuty = dayDuties.isNotEmpty;
                  final isSelected = key == selectedDateKey && hasDuty;

                  return Expanded(
                    child: InkWell(
                      key: ValueKey('swapCalendarDay_$key'),
                      borderRadius: BorderRadius.circular(10),
                      onTap: !hasDuty
                          ? null
                          : () {
                              _calendarMonthTouched = true;
                              _selectDuty(dayDuties.first);
                            },
                      child: Container(
                        height: 36,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.accent
                              : hasDuty
                              ? colors.accent.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: hasDuty && !isSelected
                              ? Border.all(
                                  color: colors.accent.withValues(alpha: 0.45),
                                )
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${cellDate.day}',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : hasDuty
                                    ? colors.accent
                                    : isOutside
                                    ? colors.textHint.withValues(alpha: 0.5)
                                    : colors.textHint,
                                fontSize: 12,
                                fontWeight: hasDuty
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                            if (hasDuty)
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(top: 1),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.white
                                      : colors.accent,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  bool _isSameClient(
    Map<String, dynamic> duty,
    Map<String, dynamic> candidate,
  ) {
    final dutyLocId = (duty['location_id'] ?? '').toString().trim();
    final candLocId = (candidate['location_id'] ?? '').toString().trim();
    if (dutyLocId.isNotEmpty && candLocId.isNotEmpty) {
      return dutyLocId == candLocId;
    }
    final dutyLabel = (duty['location_label'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final candLabel = (candidate['location_label'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (dutyLabel.isNotEmpty && candLabel.isNotEmpty) {
      return dutyLabel == candLabel;
    }
    return true;
  }

  Widget _swapPicker(Map<String, dynamic>? currentDuty) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _swapOptions,
        builder: (context, snapshot) {
          final colors = AppColors.of(context);
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: GuardBusyLabel(
                busy: true,
                label: 'Available duties',
                busyLabel: 'Finding Guards to swap with…',
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
          final sameClientOptions = (snapshot.data ?? [])
              .where((s) => currentDuty == null || _isSameClient(currentDuty, s))
              .toList();
          if (sameClientOptions.isEmpty) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No eligible duties to swap with at this client. You can only swap shifts with another active Guard assigned to the same client who has an unstarted, non-overlapping duty.',
                ),
                TextButton(
                  onPressed: () => setState(_loadSwapOptions),
                  child: const Text('Refresh swap options'),
                ),
              ],
            );
          }

          final currentDateKey =
              currentDuty != null ? _scheduleDateKey(currentDuty) : '';
          final options = sameClientOptions
            ..sort((a, b) {
              final aSame = _scheduleDateKey(a) == currentDateKey ? 0 : 1;
              final bSame = _scheduleDateKey(b) == currentDateKey ? 0 : 1;
              if (aSame != bSame) return aSame.compareTo(bSame);
              return _scheduleDateKey(a).compareTo(_scheduleDateKey(b));
            });

          final selected = options
              .where((s) => s['id'] == _targetScheduleId)
              .firstOrNull;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Swap duration',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'day',
                    label: Text('This Day', overflow: TextOverflow.ellipsis),
                    icon: Icon(Icons.today_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: 'month',
                    label: Text('Entire Month', overflow: TextOverflow.ellipsis),
                    icon: Icon(Icons.calendar_month_rounded, size: 16),
                  ),
                ],
                selected: {_swapScope},
                onSelectionChanged: (val) =>
                    setState(() => _swapScope = val.first),
              ),
              const SizedBox(height: 6),
              Text(
                _swapScope == 'month'
                    ? 'Swaps your duties with the chosen Guard for all matching days in this month once Operations Head approves and the Guard confirms.'
                    : 'Swaps only this selected shift once Operations Head approves and the Guard confirms.',
                style: TextStyle(color: colors.textMuted, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              Text(
                'Select Guard to swap with',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...options.map((s) {
                final id = s['id'].toString();
                final isChosen = id == _targetScheduleId;
                final isSameDate =
                    currentDateKey.isNotEmpty &&
                    _scheduleDateKey(s) == currentDateKey;
                final name = s['guard_name']?.toString() ?? 'Guard';
                final initials = name
                    .trim()
                    .split(RegExp(r'\s+'))
                    .where((p) => p.isNotEmpty)
                    .take(2)
                    .map((p) => p[0].toUpperCase())
                    .join();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    key: ValueKey('swapGuardCard_$id'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _targetScheduleId = id),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isChosen
                            ? colors.accent.withValues(alpha: 0.09)
                            : colors.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isChosen ? colors.accent : colors.border,
                          width: isChosen ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: isChosen
                                ? colors.accent
                                : colors.surfaceMuted,
                            child: Text(
                              initials.isEmpty ? 'G' : initials,
                              style: TextStyle(
                                color: isChosen ? Colors.white : colors.accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colors.text,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (isSameDate)
                                      Container(
                                        margin: const EdgeInsets.only(left: 6),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.success.withValues(
                                            alpha: 0.14,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: Text(
                                          'Same date',
                                          style: TextStyle(
                                            color: colors.success,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _dutyLabel(s),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  s['location_label']?.toString() ??
                                      'Assigned post',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.textMuted,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            isChosen
                                ? Icons.check_circle_rounded
                                : Icons.radio_button_unchecked_rounded,
                            color: isChosen ? colors.accent : colors.textHint,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              if (selected != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'Swap partner: ${selected['guard_name']}\nYou will take: ${_dutyLabel(selected)}\nPost: ${selected['location_label'] ?? 'Assigned post'}',
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
                title: 'Absence & Shift Swap',
                subtitle: 'Absence Request & Shift Swap Request',
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
                                  'Select request type',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'absence',
                                      label: Text('Absence Request'),
                                      icon: Icon(Icons.event_busy),
                                    ),
                                    ButtonSegment(
                                      value: 'swap',
                                      label: Text('Shift Swap Request'),
                                      icon: Icon(Icons.swap_horiz),
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
                                ] else ...[
                                  Text(
                                    'Select duty date on calendar',
                                    style: TextStyle(
                                      color: colors.text,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildDutyCalendarPicker(
                                    duties,
                                    selectedId,
                                    colors,
                                  ),
                                  const SizedBox(height: 12),
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
                                      : (value) {
                                          final picked = duties
                                              .where((s) => s['id'] == value)
                                              .firstOrNull;
                                          if (picked != null) {
                                            _selectDuty(picked);
                                          }
                                        },
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
                                  if (!_coverage)
                                    _swapPicker(
                                      duties
                                          .where((s) => s['id'] == selectedId)
                                          .firstOrNull,
                                    ),
                                  const SizedBox(height: 12),
                                ],
                                Text(
                                  _type == 'swap' && _coverage
                                      ? 'Your existing Time In and worked hours stay on your DTR. The Operational Head confirms any missing Time Out and assigns the remaining duty to a replacement.'
                                      : _type == 'swap'
                                      ? 'Your swap request goes to Operations Head first. Once approved, the chosen Guard is notified to confirm, and your shifts swap automatically.'
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
                                    label: 'Send to Operations Head',
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
                          (r) {
                            final isMonthly =
                                (r['swap_scope'] ??
                                    (r['exchange_snapshot'] is Map
                                        ? r['exchange_snapshot']['swap_scope']
                                        : null)) ==
                                'month';
                            final isSwapExchange =
                                r['target_schedule_id'] != null ||
                                r['exchange_snapshot'] is Map;
                            final canGuardConfirm =
                                r['is_incoming'] == true &&
                                r['guard_response'] == 'pending' &&
                                r['status'] == 'pending_admin' &&
                                r['admin_decision_at'] != null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: GuardSurfaceCard(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${r['is_incoming'] == true
                                          ? 'Shift Swap Request (Invitation)'
                                          : (r['request_type'] == 'overtime' || (r['reason'] ?? '').toString().startsWith('[Overtime Request]'))
                                          ? 'Overtime Request'
                                          : r['request_type'] == 'absence'
                                          ? 'Absence Request'
                                          : 'Shift Swap Request'} · ${_requestStatusText(r)}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (isSwapExchange) ...[
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.accent.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          isMonthly
                                              ? 'Entire Month Swap'
                                              : 'Single Day Swap',
                                          style: TextStyle(
                                            color: colors.accent,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
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
                                    if (canGuardConfirm) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 12,
                                        runSpacing: 8,
                                        children: [
                                          FilledButton(
                                            onPressed: _saving
                                                ? null
                                                : () => _respondToSwap(r, true),
                                            child: const Text('Confirm & Agree'),
                                          ),
                                          OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () =>
                                                      _respondToSwap(r, false),
                                            child: const Text('Decline swap'),
                                          ),
                                        ],
                                      ),
                                    ],
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
                            );
                          },
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
