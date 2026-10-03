import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/services/live_location_controller.dart';
import 'package:flutter_application_1/widgets/duty_tracking_scope.dart';

void main() {
  late DateTime now;
  late AttendanceSession? duty;
  late StreamController<Position> gps;
  late LiveLocationController tracker;
  late List<String> calls;
  var allowed = true, offline = false;
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Position fix({
    bool mock = false,
    double accuracy = 10,
    DateTime? at,
    double latitude = 14.6,
  }) => Position(
    longitude: 120.98,
    latitude: latitude,
    timestamp: at ?? now,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
    isMocked: mock,
  );
  setUp(() {
    now = DateTime.utc(2026, 9, 7, 12);
    duty = AttendanceSession(
      id: 'session',
      scheduleId: 'schedule',
      dutyDate: '2026-09-07',
      locationLabel: 'Gate',
      scheduledStartAt: now.subtract(const Duration(hours: 1)),
      scheduledEndAt: now.add(const Duration(hours: 1)),
      clockInAt: now.subtract(const Duration(hours: 1)),
      status: 'open',
    );
    gps = StreamController<Position>.broadcast(sync: true);
    calls = [];
    allowed = true;
    offline = false;
    tracker = LiveLocationController(
      loadDuty: () async {
        if (offline) throw Exception('offline');
        return duty;
      },
      positions: () => gps.stream,
      permission: () async => allowed,
      publish: (id, p) async {
        calls.add('publish');
      },
      remove: (id) async {
        calls.add('remove');
      },
      now: () => now,
    );
  });
  tearDown(() async {
    await tracker.stop();
    tracker.dispose();
    await gps.close();
  });
  test('off by default and rejects hosted tracking endpoints', () {
    expect(tracker.enabled, false);
    expect(gps.hasListener, false);
    expect(isLocalTrackingEndpoint('https://example.supabase.co'), false);
    expect(
      isTrackingEndpoint('https://uqtupmpofjqrnefgrexm.supabase.co'),
      true,
    );
    expect(isTrackingEndpoint('https://example.supabase.co'), false);
    expect(isLocalTrackingEndpoint('http://127.0.0.1:54321'), true);
    expect(isLocalTrackingEndpoint('http://10.0.2.2:54321'), true);
  });
  test('permission denied does not subscribe', () async {
    allowed = false;
    await tracker.start();
    expect(gps.hasListener, false);
    expect(tracker.enabled, true);
    allowed = true;
    await tracker.refresh();
    expect(gps.hasListener, true);
  });
  test('no duty does not capture; time in starts capture', () async {
    final next = duty;
    duty = null;
    await tracker.start();
    expect(gps.hasListener, false);
    duty = next;
    await tracker.refresh();
    expect(gps.hasListener, true);
  });
  testWidgets(
    'app owner has no location panel and follows Time In and Time Out',
    (tester) async {
      final activeDuty = duty;
      duty = null;
      var permissionRequests = 0;
      final automatic = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async {
          permissionRequests++;
          return true;
        },
        publish: (id, p) async {
          calls.add('publish');
        },
        remove: (id) async {
          calls.add('remove');
        },
        now: () => now,
      );
      final key = GlobalKey<DutyTrackingScopeState>();
      await tester.pumpWidget(
        DutyTrackingScope(
          key: key,
          controller: automatic,
          child: const MaterialApp(
            home: Scaffold(body: Text('Duty dashboard')),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('On-duty live location'), findsNothing);
      expect(find.text('Retry GPS'), findsNothing);
      expect(permissionRequests, 0);
      expect(gps.hasListener, isFalse);
      duty = activeDuty;
      await tester.runAsync(() => key.currentState!.syncDuty());
      await tester.pump();
      expect(permissionRequests, 1);
      expect(gps.hasListener, isTrue);
      gps.add(fix());
      await tester.pump();
      expect(calls, ['publish']);
      duty = null;
      await tester.runAsync(() => key.currentState!.syncDuty());
      await tester.pump();
      expect(gps.hasListener, isFalse);
      expect(calls, ['publish', 'remove']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets(
    'opening the app while clocked in resumes sharing automatically',
    (tester) async {
      final automatic = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        publish: (id, p) async {
          calls.add('publish');
        },
        remove: (id) async {},
        now: () => now,
      );
      await tester.pumpWidget(
        DutyTrackingScope(
          controller: automatic,
          child: const MaterialApp(
            home: Scaffold(body: Text('Duty dashboard')),
          ),
        ),
      );
      await tester.pump();
      expect(gps.hasListener, isTrue);
      gps.add(fix());
      await tester.pump();
      expect(calls, ['publish']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(seconds: 5));
      gps.add(fix(latitude: 14.601));
      await tester.pump();
      expect(gps.hasListener, isTrue);
      expect(calls, ['publish', 'publish']);
      await tester.pumpWidget(
        DutyTrackingScope(
          controller: automatic,
          child: const MaterialApp(
            home: Scaffold(body: Text('Another screen')),
          ),
        ),
      );
      expect(gps.hasListener, isTrue);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  test(
    'Time In arriving during a duty check is processed immediately afterwards',
    () async {
      final pending = Completer<AttendanceSession?>();
      var checks = 0;
      await tracker.stop();
      tracker.dispose();
      tracker = LiveLocationController(
        loadDuty: () async => ++checks == 1 ? await pending.future : duty,
        positions: () => gps.stream,
        permission: () async => true,
        publish: (id, p) async {},
        remove: (id) async {},
        now: () => now,
      );
      final starting = tracker.start();
      await tracker.refresh();
      pending.complete(null);
      await starting;
      await flush();
      expect(checks, 2);
      expect(gps.hasListener, isTrue);
    },
  );
  test(
    'successful Time In starts tracking from its server result without a second network read',
    () async {
      final session = duty!;
      duty = null;
      await tracker.start();
      offline = true;
      await tracker.attendanceRecorded(session);
      expect(gps.hasListener, isTrue);
      gps.add(fix());
      await flush();
      expect(calls, ['publish']);
    },
  );

  testWidgets(
    'Time In owns GPS immediately through screen lock and delayed duty lookup',
    (tester) async {
      final session = duty!;
      final delayed = Completer<AttendanceSession?>();
      final events = StreamController<AttendanceSession>.broadcast(sync: true);
      final handoff = StreamController<Position>.broadcast(sync: true);
      final configured = <DateTime?>[];
      final automatic = LiveLocationController(
        loadDuty: () => delayed.future,
        positions: () => gps.stream,
        permission: () async => true,
        configureDuty: (end) async {
          configured.add(end);
        },
        publish: (_, _) async {
          calls.add('publish');
        },
        remove: (_) async {
          calls.add('remove');
        },
        now: () => now,
      );
      await tester.pumpWidget(
        DutyTrackingScope(
          controller: automatic,
          attendanceEvents: events.stream,
          configureLocation: (end) async {
            configured.add(end);
          },
          handoffPositions: () => handoff.stream,
          child: const MaterialApp(home: Scaffold(body: Text('Attendance'))),
        ),
      );
      events.add(session);
      expect(handoff.hasListener, isTrue);
      expect(configured.first, session.scheduledEndAt);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(handoff.hasListener, isTrue);
      delayed.complete(null);
      await tester.pump();
      await tester.pump();
      expect(gps.hasListener, isTrue);
      expect(handoff.hasListener, isFalse);
      gps.add(fix());
      await tester.pump();
      expect(calls, ['publish']);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await events.close();
      await handoff.close();
    },
  );
  test('mock, stale and inaccurate fixes are rejected', () async {
    await tracker.start();
    gps.add(fix(mock: true));
    gps.add(fix(accuracy: 501));
    gps.add(fix(at: now.subtract(const Duration(minutes: 2))));
    await flush();
    expect(calls, isEmpty);
  });
  test('rejected fixes explain the actual reason', () async {
    await tracker.start();
    gps.add(fix(mock: true));
    expect(tracker.status, contains('Simulated GPS'));
    gps.add(fix(accuracy: 850));
    expect(tracker.status, contains('850 m'));
    gps.add(fix(at: now.subtract(const Duration(minutes: 2))));
    expect(tracker.status, contains('old GPS fix'));
    gps.add(fix(at: now.add(const Duration(seconds: 6))));
    expect(tracker.status, contains('automatic date and time'));
    gps.add(fix(accuracy: 0));
    expect(tracker.status, contains('usable accuracy'));
    expect(calls, isEmpty);
  });
  test(
    'first fresh fix uploads even when the position stream is silent',
    () async {
      await tracker.stop();
      tracker.dispose();
      var requests = 0;
      tracker = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        currentPosition: () async {
          requests++;
          return fix();
        },
        publish: (id, p) async {
          calls.add('publish');
        },
        remove: (id) async {},
        now: () => now,
      );
      await tracker.start();
      await flush();
      expect(calls, ['publish']);
      expect(tracker.status, contains('Sharing on-duty location'));
      await tracker.refresh();
      expect(requests, 1);
      now = now.add(const Duration(seconds: 30));
      await tracker.refresh();
      await flush();
      expect(calls, ['publish', 'publish']);
      expect(requests, 2);
    },
  );
  test('poor initial accuracy recovers through a fresh request', () async {
    await tracker.stop();
    tracker.dispose();
    var requests = 0;
    tracker = LiveLocationController(
      loadDuty: () async => duty,
      positions: () => gps.stream,
      permission: () async => true,
      currentPosition: () async => fix(accuracy: ++requests == 1 ? 900 : 20),
      publish: (id, p) async {
        calls.add('publish');
      },
      remove: (id) async {},
      now: () => now,
    );
    await tracker.start();
    await flush();
    expect(tracker.status, contains('900 m'));
    expect(calls, isEmpty);
    await tracker.refresh(requestFresh: true);
    await flush();
    expect(calls, ['publish']);
    expect(tracker.status, contains('accuracy 20 m'));
  });
  test('fresh request is single flight and discarded after stopping', () async {
    final pending = Completer<Position>();
    await tracker.stop();
    tracker.dispose();
    var requests = 0;
    tracker = LiveLocationController(
      loadDuty: () async => duty,
      positions: () => gps.stream,
      permission: () async => true,
      currentPosition: () {
        requests++;
        return pending.future;
      },
      publish: (id, p) async {
        calls.add('publish');
      },
      remove: (id) async {},
      now: () => now,
    );
    await tracker.start();
    await tracker.refresh(requestFresh: true);
    expect(requests, 1);
    await tracker.stop();
    pending.complete(fix());
    await flush();
    expect(calls, isEmpty);
  });
  test(
    'a pending fix from the previous duty cannot publish on the next duty',
    () async {
      final pending = Completer<Position>();
      await tracker.stop();
      tracker.dispose();
      tracker = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        currentPosition: () => pending.future,
        publish: (id, p) async {
          calls.add('publish');
        },
        remove: (id) async {},
        now: () => now,
      );
      await tracker.start();
      final previous = duty!;
      duty = AttendanceSession(
        id: 'new-session',
        scheduleId: 'new-schedule',
        dutyDate: previous.dutyDate,
        locationLabel: previous.locationLabel,
        scheduledStartAt: now,
        scheduledEndAt: now.add(const Duration(hours: 1)),
        clockInAt: now,
        status: 'open',
      );
      await tracker.refresh();
      pending.complete(fix());
      await flush();
      expect(calls, isEmpty);
      gps.add(fix());
      await flush();
      expect(calls, ['publish']);
    },
  );
  test(
    'server rejection is distinguished from GPS acquisition failure',
    () async {
      await tracker.stop();
      tracker.dispose();
      tracker = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        publish: (id, p) async {
          throw const PostgrestException(
            message: 'Location sharing requires your active, clocked-in duty.',
            code: '42501',
          );
        },
        remove: (id) async {},
        now: () => now,
      );
      await tracker.start();
      gps.add(fix());
      await flush();
      expect(tracker.status, contains('active, clocked-in duty'));
      expect(tracker.lastSent, isNull);
    },
  );
  test('fresh publications limited to one per 30 seconds', () async {
    await tracker.start();
    gps.add(fix());
    await flush();
    gps.add(fix());
    await flush();
    expect(calls, ['publish']);
    now = now.add(const Duration(seconds: 30));
    gps.add(fix());
    await flush();
    expect(calls, ['publish', 'publish']);
  });
  test(
    'a cached fix is not published twice with a newer delivery time',
    () async {
      await tracker.start();
      final cached = fix();
      gps.add(cached);
      await flush();
      now = now.add(const Duration(seconds: 30));
      gps.add(cached);
      await flush();
      expect(calls, ['publish']);
      gps.add(fix());
      await flush();
      expect(calls, ['publish', 'publish']);
    },
  );
  test(
    '114 m fix publishes as approximate without inventing better accuracy',
    () async {
      await tracker.start();
      gps.add(fix(accuracy: 114));
      await flush();
      expect(calls, ['publish']);
      expect(tracker.status, contains('approximate'));
      expect(tracker.status, contains('114 m'));
    },
  );
  test('time out cancels GPS and removes latest position', () async {
    await tracker.start();
    gps.add(fix());
    await flush();
    duty = null;
    await tracker.refresh();
    expect(gps.hasListener, false);
    expect(calls, ['publish', 'remove']);
    gps.add(fix());
    await flush();
    expect(calls.length, 2);
  });
  test('scheduled end stops capture without a new fix', () async {
    await tracker.start();
    now = now.add(const Duration(hours: 2));
    await tracker.refresh();
    expect(gps.hasListener, false);
    expect(calls, ['remove']);
  });
  test(
    'known shift deadline stops GPS while duty refresh is stalled',
    () async {
      await tracker.stop();
      tracker.dispose();
      final pending = Completer<AttendanceSession?>();
      final previous = duty!;
      duty = AttendanceSession(
        id: previous.id,
        scheduleId: previous.scheduleId,
        dutyDate: previous.dutyDate,
        locationLabel: previous.locationLabel,
        scheduledStartAt: previous.scheduledStartAt,
        scheduledEndAt: now.add(const Duration(seconds: 2)),
        clockInAt: previous.clockInAt,
        status: 'open',
      );
      var checks = 0;
      tracker = LiveLocationController(
        loadDuty: () async => ++checks == 1 ? duty : await pending.future,
        positions: () => gps.stream,
        permission: () async => true,
        publish: (_, _) async {},
        remove: (_) async => calls.add('remove'),
        now: () => now,
      );
      await tracker.start();
      expect(gps.hasListener, isTrue);
      final refresh = tracker.refresh();
      now = now.add(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 2100));
      await flush();
      expect(gps.hasListener, isFalse);
      expect(calls, ['remove']);
      expect(tracker.status, contains('Duty ended'));
      pending.complete(duty);
      await refresh;
      await tracker.stop();
    },
  );
  test('permission granted after scheduled end never starts GPS', () async {
    await tracker.stop();
    tracker.dispose();
    final permission = Completer<bool>();
    final prompted = Completer<void>();
    tracker = LiveLocationController(
      loadDuty: () async => duty,
      positions: () => gps.stream,
      permission: () {
        prompted.complete();
        return permission.future;
      },
      publish: (_, _) async => calls.add('publish'),
      remove: (_) async => calls.add('remove'),
      now: () => now,
    );
    final starting = tracker.start();
    await prompted.future;
    now = duty!.scheduledEndAt;
    permission.complete(true);
    await starting;
    expect(gps.hasListener, isFalse);
    expect(calls, isEmpty);
    expect(tracker.status, contains('Duty ended'));
  });
  test('previous duty deadline cannot stop a new active duty', () async {
    final previous = duty!;
    duty = AttendanceSession(
      id: previous.id,
      scheduleId: previous.scheduleId,
      dutyDate: previous.dutyDate,
      locationLabel: previous.locationLabel,
      scheduledStartAt: previous.scheduledStartAt,
      scheduledEndAt: now.add(const Duration(seconds: 2)),
      clockInAt: previous.clockInAt,
      status: 'open',
    );
    await tracker.start();
    duty = AttendanceSession(
      id: 'next-session',
      scheduleId: 'next-schedule',
      dutyDate: previous.dutyDate,
      locationLabel: previous.locationLabel,
      scheduledStartAt: now,
      scheduledEndAt: now.add(const Duration(hours: 1)),
      clockInAt: now,
      status: 'open',
    );
    await tracker.refresh();
    now = now.add(const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 2100));
    expect(gps.hasListener, isTrue);
    expect(calls, ['remove']);
    await tracker.stop();
  });
  test(
    'network loss preserves verified duty capture and reconnects without restarting GPS',
    () async {
      await tracker.start();
      gps.add(fix());
      await flush();
      offline = true;
      await tracker.refresh();
      expect(gps.hasListener, true);
      expect(calls, ['publish']);
      offline = false;
      await tracker.refresh();
      expect(gps.hasListener, true);
      now = now.add(const Duration(seconds: 30));
      gps.add(fix());
      await flush();
      expect(calls, ['publish', 'publish']);
    },
  );
  test(
    'GPS interruption retains last point, but confirmed Time Out removes it',
    () async {
      await tracker.start();
      gps.add(fix());
      await flush();
      gps.addError(StateError('GPS interrupted'));
      await flush();
      expect(gps.hasListener, isFalse);
      expect(calls, ['publish']);
      await tracker.refresh();
      expect(gps.hasListener, isTrue);
      duty = null;
      await tracker.refresh();
      expect(calls, ['publish', 'remove']);
    },
  );
  test(
    'moving guard publishes every five seconds; stationary jitter waits',
    () async {
      await tracker.start();
      gps.add(fix());
      await flush();
      now = now.add(const Duration(seconds: 4));
      gps.add(fix(latitude: 14.601));
      await flush();
      expect(calls, ['publish']);
      now = now.add(const Duration(seconds: 1));
      gps.add(fix(latitude: 14.601));
      await flush();
      expect(calls, ['publish', 'publish']);
      now = now.add(const Duration(seconds: 5));
      gps.add(fix(latitude: 14.601001));
      await flush();
      expect(calls.length, 2);
      now = now.add(const Duration(seconds: 25));
      gps.add(fix(latitude: 14.601001));
      await flush();
      expect(calls.length, 3);
    },
  );
  test(
    'page disposal stops capture without deleting last known position',
    () async {
      final pageTracker = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        publish: (_, _) async {
          calls.add('publish');
        },
        remove: (_) async {
          calls.add('remove');
        },
        now: () => now,
      );
      await pageTracker.start();
      gps.add(fix());
      await flush();
      pageTracker.dispose();
      await flush();
      expect(gps.hasListener, isFalse);
      expect(calls, ['publish']);
    },
  );
  test('stop during permission request prevents late GPS start', () async {
    final ready = Completer<bool>();
    await tracker.stop();
    tracker.dispose();
    tracker = LiveLocationController(
      loadDuty: () async => duty,
      positions: () => gps.stream,
      permission: () => ready.future,
      publish: (id, p) async {},
      remove: (id) async {},
      now: () => now,
    );
    final start = tracker.start();
    await tracker.stop();
    ready.complete(true);
    await start;
    expect(tracker.enabled, false);
    expect(gps.hasListener, false);
  });
  test('stop waits for in-flight publish before removal', () async {
    final sent = Completer<void>();
    await tracker.stop();
    tracker.dispose();
    tracker = LiveLocationController(
      loadDuty: () async => duty,
      positions: () => gps.stream,
      permission: () async => true,
      publish: (id, p) {
        calls.add('publish');
        return sent.future;
      },
      remove: (id) async {
        calls.add('remove');
      },
      now: () => now,
    );
    await tracker.start();
    gps.add(fix());
    final stop = tracker.stop();
    await flush();
    expect(calls, ['publish']);
    sent.complete();
    await stop;
    expect(calls, ['publish', 'remove']);
    expect(tracker.enabled, false);
  });

  test(
    'page disposal preserves a late real point without deleting the marker',
    () async {
      final delivery = Completer<void>();
      final failed = Completer<void>();
      final pageTracker = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        publishTimeout: const Duration(milliseconds: 20),
        publish: (_, _) => delivery.future,
        remove: (_) async {
          calls.add('remove');
        },
        now: () => now,
      );
      pageTracker.addListener(() {
        if (pageTracker.status.startsWith('Location not delivered') &&
            !failed.isCompleted) {
          failed.complete();
        }
      });
      await pageTracker.start();
      gps.add(fix());
      await failed.future.timeout(const Duration(seconds: 2));
      pageTracker.dispose();
      delivery.complete();
      await flush();
      expect(calls, isEmpty);
      expect(gps.hasListener, isFalse);
    },
  );

  test(
    'stalled upload releases subsequent fixes and late completion is cleaned after stop',
    () async {
      final stalled = Completer<void>();
      await tracker.stop();
      tracker.dispose();
      var uploads = 0;
      tracker = LiveLocationController(
        loadDuty: () async => duty,
        positions: () => gps.stream,
        permission: () async => true,
        publishTimeout: const Duration(milliseconds: 20),
        publish: (_, _) {
          calls.add('publish');
          return ++uploads == 1 ? stalled.future : Future<void>.value();
        },
        remove: (_) async {
          calls.add('remove');
        },
        now: () => now,
      );
      await tracker.start();
      gps.add(fix());
      final failed = Completer<void>();
      tracker.addListener(() {
        if (tracker.status.startsWith('Location not delivered') &&
            !failed.isCompleted) {
          failed.complete();
        }
      });
      await failed.future.timeout(const Duration(seconds: 2));
      await flush();
      now = now.add(const Duration(seconds: 5));
      gps.add(fix());
      await flush();
      expect(uploads, 2);
      expect(tracker.status, startsWith('Sharing on-duty'));
      await tracker.stop();
      expect(calls, ['publish', 'publish', 'remove']);
      stalled.complete();
      await flush();
      expect(calls, ['publish', 'publish', 'remove', 'remove']);
    },
  );
}
