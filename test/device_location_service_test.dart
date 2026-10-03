import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_application_1/services/device_location_service.dart';

void main() {
  late DateTime now;
  late DeviceLocationService service;
  late List<bool> modes;
  late List<StreamController<Position>> sources;

  Position fix({DateTime? at, bool mocked = false, double accuracy = 114}) =>
      Position(
        longitude: 120.98,
        latitude: 14.6,
        timestamp: at ?? now,
        accuracy: accuracy,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
        isMocked: mocked,
      );
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    now = DateTime.utc(2026, 9, 8, 12);
    modes = [];
    sources = [];
    service = DeviceLocationService(
      now: () => now,
      requestTimeout: const Duration(milliseconds: 50),
      source: (background) {
        modes.add(background);
        final source = StreamController<Position>.broadcast(sync: true);
        sources.add(source);
        return source.stream;
      },
    );
  });
  tearDown(() async {
    for (final source in sources) {
      await source.close();
    }
  });

  test(
    'attendance reuses the live stream fix and its real accuracy/time',
    () async {
      final subscription = service.positions().listen((_) {});
      await flush();
      final actual = fix();
      sources.single.add(actual);
      now = now.add(const Duration(seconds: 20));

      expect(await service.currentPosition(), same(actual));
      expect(modes, [true]);
      expect(sources.single.hasListener, isTrue);
      await subscription.cancel();
      await flush();
      expect(sources.single.hasListener, isFalse);
    },
  );

  test(
    'concurrent attendance requests share a cancellable temporary stream',
    () async {
      final first = service.currentPosition();
      final second = service.currentPosition();
      expect(second, same(first));
      await flush();
      final actual = fix();
      sources.single.add(actual);

      expect(await first, same(actual));
      expect(await second, same(actual));
      expect(modes, [false]);
      expect(sources.single.hasListener, isFalse);
    },
  );

  test(
    'a request waits on existing live GPS without another native client',
    () async {
      final subscription = service.positions().listen((_) {});
      await flush();
      final pending = service.currentPosition();
      await flush();
      final actual = fix();
      sources.single.add(actual);

      expect(await pending, same(actual));
      expect(modes, [true]);
      expect(sources.single.hasListener, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'old, mocked and future fixes cannot satisfy attendance or enter cache',
    () async {
      final pending = service.currentPosition();
      var completed = false;
      unawaited(pending.then((_) => completed = true));
      await flush();
      sources.single.add(fix(at: now.subtract(const Duration(seconds: 31))));
      sources.single.add(fix(mocked: true));
      sources.single.add(fix(at: now.add(const Duration(seconds: 6))));
      await flush();
      expect(completed, isFalse);

      final actual = fix();
      sources.single.add(actual);
      expect(await pending, same(actual));
    },
  );

  test('expired cache waits for an actual new fix', () async {
    final subscription = service.positions().listen((_) {});
    await flush();
    sources.single.add(fix());
    now = now.add(const Duration(seconds: 31));
    final pending = service.currentPosition();
    await flush();
    final actual = fix();
    sources.single.add(actual);

    expect(await pending, same(actual));
    expect(modes, [true]);
    await subscription.cancel();
  });

  test('timeout releases temporary GPS and permits a clean retry', () async {
    final failed = service.currentPosition();
    await expectLater(failed, throwsA(isA<TimeoutException>()));
    await flush();
    expect(sources.single.hasListener, isFalse);

    final retry = service.currentPosition();
    await flush();
    sources.last.add(fix());
    expect(await retry, isA<Position>());
    await flush();
    expect(modes, [false, false]);
    expect(sources.last.hasListener, isFalse);
  });

  test(
    'short timeout keeps existing duty GPS alive until recovery is due',
    () async {
      final subscription = service.positions().listen((_) {});
      await flush();
      await expectLater(
        service.currentPosition(),
        throwsA(isA<TimeoutException>()),
      );
      expect(modes, [true]);
      expect(sources.single.hasListener, isTrue);
      await subscription.cancel();
    },
  );

  test(
    'silent native stream switches provider and delivers a real fix',
    () async {
      final primary = StreamController<Position>.broadcast(sync: true);
      final fallback = StreamController<Position>.broadcast(sync: true);
      var fallbackStarts = 0;
      final fallbackReady = Completer<void>();
      final recovering = DeviceLocationService(
        source: (_) => primary.stream,
        fallbackSource: (background) {
          expect(background, isTrue);
          fallbackStarts++;
          fallbackReady.complete();
          return fallback.stream;
        },
        now: () => now,
        recoveryDelay: const Duration(milliseconds: 10),
        requestTimeout: const Duration(seconds: 3),
      );
      final received = <Position>[];
      final live = recovering.positions().listen(received.add);
      final pending = recovering.currentPosition(fresh: true);
      await fallbackReady.future.timeout(const Duration(seconds: 2));
      await flush();
      expect(primary.hasListener, isFalse);
      expect(fallbackStarts, 1);
      final actual = fix();
      fallback.add(actual);
      expect(await pending, same(actual));
      expect(received, [actual]);
      await live.cancel();
      await flush();
      expect(fallback.hasListener, isFalse);
      await primary.close();
      await fallback.close();
    },
  );

  test('fresh request bypasses the cached Time In fix', () async {
    final live = service.positions().listen((_) {});
    await flush();
    sources.single.add(fix());
    now = now.add(const Duration(seconds: 2));
    final pending = service.currentPosition(fresh: true);
    var completed = false;
    unawaited(pending.then((_) => completed = true));
    await flush();
    expect(completed, isFalse);
    final actual = fix();
    sources.single.add(actual);
    expect(await pending, same(actual));
    await live.cancel();
  });

  test(
    'manual retry replaces the source without detaching duty listeners',
    () async {
      final received = <Position>[];
      final live = service.positions().listen(received.add);
      await flush();
      await service.restart();
      expect(sources.first.hasListener, isFalse);
      expect(sources.last.hasListener, isTrue);
      final actual = fix();
      sources.last.add(actual);
      await flush();
      expect(received, [actual]);
      await live.cancel();
    },
  );

  test(
    'Time In upgrades temporary GPS; Time Out removes background capture',
    () async {
      final pending = service.currentPosition();
      await flush();
      final live = service.positions().listen((_) {});
      await flush();
      expect(modes, [false, true]);
      expect(sources.first.hasListener, isFalse);
      expect(sources.last.hasListener, isTrue);
      sources.last.add(fix());
      await pending;

      await live.cancel();
      await flush();
      expect(sources.last.hasListener, isFalse);
    },
  );

  test('native error releases GPS and reaches the caller', () async {
    final pending = service.currentPosition();
    final result = expectLater(pending, throwsA(isA<StateError>()));
    await flush();
    sources.single.addError(StateError('GPS disabled'));
    await result;
    await flush();
    expect(sources.single.hasListener, isFalse);
  });

  test('mocked update invalidates a previously usable cached fix', () async {
    final subscription = service.positions().listen((_) {});
    await flush();
    sources.single.add(fix());
    sources.single.add(fix(mocked: true));
    final pending = service.currentPosition();
    await expectLater(
      pending,
      throwsA(
        isA<TimeoutException>().having(
          (error) => error.message,
          'reason',
          contains('Mock or simulated'),
        ),
      ),
    );
    await subscription.cancel();
  });

  test(
    'slow native cancellation cannot extend the GPS request deadline',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<Position>(
        onCancel: () => cancelled.future,
      );
      final slow = DeviceLocationService(
        source: (_) => source.stream,
        now: () => now,
        requestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        slow.currentPosition().timeout(const Duration(milliseconds: 200)),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.duration,
            'device deadline',
            const Duration(milliseconds: 20),
          ),
        ),
      );
      expect(cancelled.isCompleted, isFalse);
      cancelled.complete();
      await flush();
      await source.close();
    },
  );

  test(
    'failed native cancellation does not poison future GPS requests',
    () async {
      final first = StreamController<Position>(
        onCancel: () => Future<void>.error(StateError('cancel failed')),
      );
      final next = StreamController<Position>.broadcast(sync: true);
      var attempts = 0;
      final recovering = DeviceLocationService(
        source: (_) => ++attempts == 1 ? first.stream : next.stream,
        now: () => now,
        requestTimeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        recovering.currentPosition(),
        throwsA(isA<TimeoutException>()),
      );
      await flush();
      final retry = recovering.currentPosition();
      await flush();
      next.add(fix());
      expect(await retry, isA<Position>());
      await flush();
      expect(attempts, 2);
      expect(next.hasListener, isFalse);
      await first.close();
      await next.close();
    },
  );

  test(
    'Time Out detaches promptly while native cancellation is pending',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<Position>(
        onCancel: () => cancelled.future,
      );
      final slow = DeviceLocationService(source: (_) => source.stream);
      final live = slow.positions().listen((_) {});
      await flush();

      await live.cancel().timeout(const Duration(milliseconds: 200));
      expect(cancelled.isCompleted, isFalse);
      cancelled.complete();
      await flush();
      await source.close();
    },
  );

  test(
    'cancelled consumers do not restart GPS after a delayed upgrade',
    () async {
      final cancelled = Completer<void>();
      final source = StreamController<Position>(
        onCancel: () => cancelled.future,
      );
      var starts = 0;
      final slow = DeviceLocationService(
        source: (_) {
          starts++;
          return source.stream;
        },
        requestTimeout: const Duration(milliseconds: 20),
      );
      final result = expectLater(
        slow.currentPosition(),
        throwsA(isA<TimeoutException>()),
      );
      await flush();
      final live = slow.positions().listen((_) {});
      await flush();
      await live.cancel();
      await result;
      cancelled.complete();
      await flush();
      expect(starts, 1);
      await source.close();
    },
  );
}
