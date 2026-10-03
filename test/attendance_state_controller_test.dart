import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/services/attendance_state_controller.dart';
import 'package:flutter_application_1/widgets/attendance_punch_action.dart';

AttendanceSession openDuty() => AttendanceSession(
  id: 'duty-session',
  scheduleId: 'duty',
  dutyDate: '2026-09-08',
  locationLabel: 'Gate',
  scheduledStartAt: DateTime(2026, 9, 8, 8),
  scheduledEndAt: DateTime(2026, 9, 8, 17),
  clockInAt: DateTime(2026, 9, 8, 8),
  status: 'open',
);

void main() {
  test(
    'initial stalled request ends with a retryable error, not a spinner',
    () async {
      final controller = AttendanceStateController(
        loadSession: () => Completer<AttendanceSession?>().future,
        requestTimeout: const Duration(milliseconds: 20),
      );
      final request = controller.refresh();
      expect(controller.initialLoading, isTrue);
      await request;
      expect(controller.initialLoading, isFalse);
      expect(controller.hasConfirmedSession, isFalse);
      expect(controller.error, isA<TimeoutException>());
      controller.dispose();
    },
  );
  test('a confirmed empty session is ready for Time In', () async {
    final controller = AttendanceStateController(loadSession: () async => null);
    await controller.refresh();
    expect(controller.hasConfirmedSession, isTrue);
    expect(controller.initialLoading, isFalse);
    expect(controller.session, isNull);
    controller.dispose();
  });
  test(
    'resume and repeated refreshes share one request without discarding Time In',
    () async {
      final pending = Completer<AttendanceSession?>();
      var calls = 0;
      final controller = AttendanceStateController(
        loadSession: () {
          calls++;
          return pending.future;
        },
      );
      controller.accept(openDuty());
      final first = controller.refresh();
      final second = controller.refresh();
      expect(calls, 1);
      expect(controller.initialLoading, isFalse);
      expect(controller.session?.isOpen, isTrue);
      pending.complete(openDuty());
      await Future.wait([first, second]);
      controller.dispose();
    },
  );
  test('late read cannot overwrite a newer confirmed Time Out', () async {
    final pending = Completer<AttendanceSession?>();
    final controller = AttendanceStateController(
      loadSession: () => pending.future,
    );
    final request = controller.refresh();
    controller.accept(null);
    pending.complete(openDuty());
    await request;
    expect(controller.session, isNull);
    expect(controller.hasConfirmedSession, isTrue);
    controller.dispose();
  });
  testWidgets(
    'Time Out stays visible during a background check and errors stop spinning',
    (tester) async {
      final pending = Completer<AttendanceSession?>();
      final controller = AttendanceStateController(
        loadSession: () => pending.future,
      );
      controller.accept(openDuty());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => AttendancePunchAction(
                hasOpenDuty: controller.session != null,
                onPunch: (_) {},
                loading: controller.initialLoading,
                enabled:
                    controller.hasConfirmedSession && controller.error == null,
              ),
            ),
          ),
        ),
      );
      final request = controller.refresh();
      await tester.pump();
      expect(find.text('Time Out'), findsOneWidget);
      expect(find.text('Checking attendance…'), findsNothing);
      pending.completeError(TimeoutException('offline'));
      await request;
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    },
  );
}
