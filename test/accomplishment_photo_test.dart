import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_application_1/models/accomplishment_photo.dart';
import 'package:flutter_application_1/duty_requests.dart';
import 'package:flutter_application_1/services/schedule_service.dart';

AccomplishmentPhoto photo(String name) => AccomplishmentPhoto(
  name: name,
  bytes: Uint8List.fromList(img.encodeJpg(img.Image(width: 10, height: 10))),
);

void main() {
  test(
    'finished photo bytes are retained and upload path is stable across retries',
    () {
      final report = photo('duty.jpg');
      expect(report.mimeType, 'image/jpeg');
      final path = report.reservePath('guard');
      expect(report.reservePath('guard'), path);
      expect(() => report.reservePath('other'), throwsStateError);
    },
  );
  test('rejects non-photo attachments and oversized streams', () async {
    expect(
      () => AccomplishmentPhoto(
        name: 'report.jpg',
        bytes: Uint8List.fromList([37, 80, 68, 70]),
      ),
      throwsFormatException,
    );
    expect(
      () => AccomplishmentPhoto(
        name: 'report.pdf',
        bytes: photo('report.jpg').bytes,
      ),
      throwsFormatException,
    );
    await expectLater(
      AccomplishmentPhoto.read(
        name: 'report.jpg',
        chunks: Stream.value(Uint8List(AccomplishmentPhoto.maxBytes + 1)),
      ),
      throwsFormatException,
    );
  });
  test(
    'report entry is available after Time In and after Time Out, but not for cancelled or unstarted duty',
    () {
      Map<String, dynamic> schedule(String status) => {
        'approval_status': 'approved',
        'attendance_sessions': [
          {'status': status, 'clock_in_at': '2026-09-20T00:00:00Z'},
        ],
      };
      expect(ScheduleService.canSubmitAccomplishment(schedule('open')), true);
      expect(ScheduleService.canSubmitAccomplishment(schedule('closed')), true);
      expect(
        ScheduleService.canSubmitAccomplishment({
          'approval_status': 'approved',
        }),
        false,
      );
      expect(
        ScheduleService.canSubmitAccomplishment({
          ...schedule('open'),
          'approval_status': 'cancelled',
        }),
        false,
      );
    },
  );
  testWidgets('missing photo cannot submit a completed written report', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AccomplishmentReportScreen(scheduleId: 'duty')),
    );
    await tester.enterText(find.byType(TextField).at(0), 'Patrol');
    await tester.enterText(find.byType(TextField).at(1), 'All posts checked.');
    await tester.ensureVisible(find.text('Submit report'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit report'));
    await tester.pump();
    expect(find.text('Attach your finished photo report.'), findsOneWidget);
  });
  testWidgets(
    'replace photo retains written content and uncertain submission retries the same photo',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var picked = 0, sent = 0;
      final submitted = <AccomplishmentPhoto>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AccomplishmentReportScreen(
            scheduleId: 'duty',
            pickPhoto: () async => photo('report${++picked}.jpg'),
            submitReport:
                ({
                  required scheduleId,
                  required summary,
                  required narrative,
                  required issues,
                  required photo,
                }) async {
                  submitted.add(photo);
                  sent++;
                  photo.submissionUncertain = true;
                  if (sent == 1) throw TimeoutException('test');
                },
          ),
        ),
      );
      await tester.enterText(find.byType(TextField).at(0), 'Patrol');
      await tester.enterText(find.byType(TextField).at(1), 'Checked');
      await tester.tap(find.text('Upload photo report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Replace photo'));
      await tester.pumpAndSettle();
      expect(find.text('report2.jpg'), findsOneWidget);
      expect(find.text('Patrol'), findsOneWidget);
      await tester.ensureVisible(find.text('Submit report'));
      await tester.tap(find.text('Submit report'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).at(0)).enabled,
        false,
      );
      await tester.ensureVisible(find.text('Retry submission'));
      await tester.tap(find.text('Retry submission'));
      await tester.pumpAndSettle();
      expect(sent, 2);
      expect(identical(submitted[0], submitted[1]), true);
    },
  );
}
