/// Fixed Philippine calendar-date contract. Expiry restricts new duty, not
/// account access or closing an already-open attendance session.
class ContractPeriod {
  ContractPeriod.fromProfile(Map<String, dynamic> profile)
    : isContract = profile['employment_category'] == 'contract',
      start = _date(profile['contract_start_date']),
      end = _date(profile['contract_end_date']);

  final bool isContract;
  final DateTime? start;
  final DateTime? end;

  static DateTime? _date(dynamic value) {
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return null;
    }
    final date = DateTime.tryParse('${value}T00:00:00Z');
    return date != null && date.toIso8601String().startsWith(value)
        ? date
        : null;
  }

  bool get configured => start != null && end != null && !end!.isBefore(start!);

  String? timeInBlockReason(DateTime now) {
    if (!isContract) return null;
    if (!configured) {
      return 'Ask Operational Head to set your contract start and end dates before Time In.';
    }
    final manila = now.toUtc().add(const Duration(hours: 8));
    final today = DateTime.utc(manila.year, manila.month, manila.day);
    if (today.isBefore(start!)) {
      return 'Your contract has not started. Contact Operational Head if your dates are incorrect.';
    }
    if (today.isAfter(end!)) {
      return 'Your contract has expired. Ask Operational Head to renew it before Time In.';
    }
    return null;
  }

  String label(DateTime now) {
    if (!isContract) return 'No contract date limit';
    if (!configured) return 'Set contract dates · Contact Operational Head';
    final block = timeInBlockReason(now);
    final status = block == null
        ? 'Active contract'
        : block.contains('expired')
        ? 'Expired'
        : 'Not started';
    return '${start!.toIso8601String().substring(0, 10)} – ${end!.toIso8601String().substring(0, 10)} · $status';
  }
}
