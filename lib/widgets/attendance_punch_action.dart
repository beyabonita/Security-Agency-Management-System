import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import 'guard_ui.dart';

/// One next-action control. The caller supplies confirmed server session state.
class AttendancePunchAction extends StatelessWidget {
  const AttendancePunchAction({
    super.key,
    required this.hasOpenDuty,
    required this.onPunch,
    this.recordedTime,
    this.loading = false,
    this.busy = false,
    this.enabled = true,
  });
  final bool hasOpenDuty, loading, busy, enabled;
  final String? recordedTime;
  final ValueChanged<String> onPunch;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (hasOpenDuty && recordedTime != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            'Time In recorded at $recordedTime',
            textAlign: TextAlign.center,
          ),
        ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: hasOpenDuty
              ? AppColors.of(context).warning
              : AppColors.of(context).success,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 20),
        ),
        onPressed: !enabled || loading || busy
            ? null
            : () => onPunch(hasOpenDuty ? 'clock_out' : 'clock_in'),
        child: GuardBusyLabel(
          busy: loading || busy,
          label: hasOpenDuty ? 'Time Out' : 'Time In',
          busyLabel: loading ? 'Checking attendance…' : 'Recording…',
          icon: hasOpenDuty ? Icons.logout_rounded : Icons.login_rounded,
        ),
      ),
    ],
  );
}
