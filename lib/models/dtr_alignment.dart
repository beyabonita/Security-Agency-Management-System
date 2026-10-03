class DtrCutoffPeriod {
  const DtrCutoffPeriod({
    required this.startDate,
    required this.endDate,
    required this.label,
  });

  final String startDate;
  final String endDate;
  final String label;
}

/// Shared presentation rules for the agency's semi-monthly Daily Time Record.
///
/// A schedule owns the DTR row and columns. Actual attendance supplies the
/// values shown in those columns, so a late punch that crosses noon does not
/// move to a different column. Explicit periods keep their own IN/OUT pair;
/// legacy continuous shifts retain their original AM/PM placement. Overtime
/// is shown only when explicitly scheduled, never inferred from its hour.
class DtrAlignment {
  DtrAlignment._();

  static const Duration _manilaOffset = Duration(hours: 8);
  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static DateTime inManila(DateTime value) => value.toUtc().add(_manilaOffset);

  static String dateString(DateTime value) {
    final date = inManila(value);
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static DateTime? _parseDutyDate(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (match == null) return null;
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    if (month < 1 || month > 12 || day < 1) return null;
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static DtrCutoffPeriod? cutoffForDutyDate(String dutyDate) {
    final date = _parseDutyDate(dutyDate);
    if (date == null) return null;
    final lastDay = DateTime.utc(date.year, date.month + 1, 0).day;
    final startDay = date.day <= 15 ? 1 : 16;
    final endDay = date.day <= 15 ? 15 : lastDay;
    final month = date.month.toString().padLeft(2, '0');
    return DtrCutoffPeriod(
      startDate: '${date.year}-$month-${startDay.toString().padLeft(2, '0')}',
      endDate: '${date.year}-$month-${endDay.toString().padLeft(2, '0')}',
      label: '${_months[date.month - 1]} $startDay–$endDay, ${date.year}',
    );
  }

  static String cutoffLabel(String dutyDate) =>
      cutoffForDutyDate(dutyDate)?.label ?? 'DTR period unavailable';

  static String normalizePeriod(String? value) {
    final period = value?.trim().toLowerCase();
    return const ['morning', 'afternoon', 'overtime'].contains(period)
        ? period!
        : 'auto';
  }

  static String cellLabel(
    DateTime scheduledAt, {
    required bool isTimeIn,
    required String dutyDate,
    String period = 'auto',
  }) {
    final manilaTime = inManila(scheduledAt);
    final declaredPeriod = normalizePeriod(period);
    final atNoon = manilaTime.hour == 12 &&
        manilaTime.minute == 0 &&
        manilaTime.second == 0;
    final autoMorning = manilaTime.hour < 12 || (!isTimeIn && atNoon);
    final section = switch (declaredPeriod) {
      'morning' => 'Morning',
      'afternoon' => 'Afternoon',
      'overtime' => 'Overtime',
      _ => autoMorning ? 'Morning' : 'Afternoon',
    };
    final direction = isTimeIn ? 'IN' : 'OUT';
    final dutyDay = _parseDutyDate(dutyDate);
    final scheduledDay = _parseDutyDate(dateString(scheduledAt));
    final dayOffset = dutyDay != null && scheduledDay != null
        ? scheduledDay.difference(dutyDay).inDays
        : 0;
    final suffix = dayOffset > 0
        ? ' (+$dayOffset)'
        : dayOffset < 0
        ? ' ($dayOffset)'
        : '';
    return '$section $direction$suffix';
  }

  static String mappingLabel({
    required String dutyDate,
    required DateTime scheduledStartAt,
    required DateTime scheduledEndAt,
    String period = 'auto',
  }) =>
      '${cellLabel(scheduledStartAt, isTimeIn: true, dutyDate: dutyDate, period: period)} '
      '→ ${cellLabel(scheduledEndAt, isTimeIn: false, dutyDate: dutyDate, period: period)}';
}
