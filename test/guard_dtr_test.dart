import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/models/guard_dtr.dart';
import 'package:flutter_application_1/services/guard_dtr_pdf.dart';
import 'package:flutter_application_1/time_logs.dart';

final fixtures =
    jsonDecode(File('testing/guard-dtr-parity.json').readAsStringSync())
        as List;
List<AttendanceSession> sessions(int index) =>
    (fixtures[index]['sessions'] as List)
        .map((s) => AttendanceSession.fromRow(Map<String, dynamic>.from(s)))
        .toList();
GuardDtr report(GuardDtrPeriod period, [int index = 0]) => GuardDtr(
  period: period,
  guardName: 'Juan D. Dela Cruz',
  sessions: sessions(index),
  now: DateTime.utc(2026, 10),
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (var i = 0; i < fixtures.length; i++) {
    test('matches web DTR: ${fixtures[i]['name']}', () {
      final r = report(GuardDtrPeriod(2026, 9, false), i);
      final expected = fixtures[i]['expected'];
      expect(r.rows, expected['rows']);
      expect(r.totalMinutes, expected['totalMinutes']);
      expect(r.overtimeMinutes, expected['overtimeMinutes']);
      expect(r.completedDays, expected['completedDays']);
      expect(r.detachment, expected['detachment']);
    });
  }
  test('leap month and overnight hours stay in the starting cutoff', () {
    expect(GuardDtrPeriod(2028, 2, true).end, '2028-02-29');
    expect(GuardDtrPeriod(2027, 2, true).end, '2027-02-28');
    final r = report(GuardDtrPeriod(2026, 9, true), 3);
    expect(r.totalMinutes, 0);
    expect(r.rows.length, 15);
    expect(
      GuardDtr.punch(DateTime.parse('2026-09-15T22:00:00Z'), '2026-09-15'),
      '6:00 AM (next day)',
    );
  });
  test(
    'generates printable PDF for empty, populated and multi-page periods',
    () async {
      for (var i = 0; i < fixtures.length; i++) {
        final bytes = await GuardDtrPdf.generate(
          report(GuardDtrPeriod(2026, 9, false), i),
        );
        expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
        await File('testing/guard-dtr-sample-$i.pdf').writeAsBytes(bytes);
      }
      final repeated = <AttendanceSession>[];
      for (var day = 1; day <= 15; day++) {
        final s = Map<String, dynamic>.from(fixtures[0]['sessions'][0]);
        s['duty_date'] = '2026-09-${day.toString().padLeft(2, '0')}';
        for (final key in [
          'scheduled_start_at',
          'scheduled_end_at',
          'clock_in_at',
          'clock_out_at',
        ]) {
          s[key] = (s[key] as String).replaceFirst(
            '2026-09-13',
            s['duty_date'],
          );
        }
        repeated.add(AttendanceSession.fromRow(s));
      }
      final r = GuardDtr(
        period: GuardDtrPeriod(2026, 9, false),
        guardName: 'Juan D. Dela Cruz',
        sessions: repeated,
      );
      await File(
        'testing/guard-dtr-full.pdf',
      ).writeAsBytes(await GuardDtrPdf.generate(r));
    },
  );
  testWidgets('phone DTR can select cutoff and save that exact report', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    GuardDtr? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: TimeLogsScreen(
          loadReport: (p) async => report(p),
          saveReport: (r) async {
            saved = r;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('My DTR'), findsOneWidget);
    expect(find.textContaining('Morning IN'), findsNothing);
    await tester.tap(find.text('Download DTR'));
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(find.text('DTR saved.'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16th–end of month').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download DTR'));
    await tester.pumpAndSettle();
    expect(saved!.period.secondHalf, true);
    expect(tester.takeException(), isNull);
  });
  testWidgets('old responses cannot overwrite a newly selected month', (
    tester,
  ) async {
    final pending = <({GuardDtrPeriod period, Completer<GuardDtr> future})>[];
    await tester.pumpWidget(
      MaterialApp(
        home: TimeLogsScreen(
          loadReport: (p) {
            final c = Completer<GuardDtr>();
            pending.add((period: p, future: c));
            return c.future;
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('Next month'));
    await tester.pump();
    final newer = pending.last;
    newer.future.complete(report(newer.period));
    await tester.pumpAndSettle();
    final old = pending.first;
    old.future.complete(report(old.period));
    await tester.pumpAndSettle();
    expect(find.text('Period Covered: ${newer.period.label}'), findsOneWidget);
    expect(find.text('Period Covered: ${old.period.label}'), findsNothing);
  });
  testWidgets('failed loading disables download and retry recovers', (
    tester,
  ) async {
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: TimeLogsScreen(
          loadReport: (p) async {
            if (fail) throw StateError('offline');
            return report(p);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    fail = false;
    await tester.tap(find.byTooltip('Refresh DTR'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}
