import 'package:flutter/material.dart';

Future<bool?> askOvertimeTimeout(
  BuildContext context,
  String scheduledEnd,
) => showDialog<bool>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('Did you work overtime?'),
    content: Text(
      'Your shift ended at $scheduledEnd.\n\nYes: submit your Time Out for Operations Head approval.\n\nNo: use the scheduled end on your DTR, with no overtime or approval required.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('No, use scheduled end'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Yes, request approval'),
      ),
    ],
  ),
);
