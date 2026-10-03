import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'android_location_bridge.dart';

/// Shares one device GPS subscription between duty tracking and attendance.
/// Attendance borrows recent real fixes, or briefly listens for the next one.
class DeviceLocationService {
  DeviceLocationService({
    Stream<Position> Function(bool background)? source,
    Stream<Position> Function(bool background)? fallbackSource,
    DateTime Function()? now,
    this.requestTimeout = const Duration(seconds: 20),
    this.recoveryDelay = const Duration(minutes: 2),
  }) : _source = source ?? _devicePositions,
       _fallbackSource = fallbackSource ?? source ?? _fallbackPositions,
       _platformService = source == null && AndroidLocationBridge.supported,
       _now = now ?? DateTime.now;

  static final instance = DeviceLocationService();
  static const maxCacheAge = Duration(seconds: 30);

  final Stream<Position> Function(bool background) _source;
  final Stream<Position> Function(bool background) _fallbackSource;
  final DateTime Function() _now;
  final Duration requestTimeout;
  final Duration recoveryDelay;
  final bool _platformService;
  final _updates = StreamController<Position>.broadcast(sync: true);
  StreamSubscription<Position>? _native;
  Future<void> _transition = Future<void>.value();
  Future<Position>? _request;
  Position? _latest;
  String? _latestProblem;
  int _backgroundListeners = 0;
  int _foregroundWaiters = 0;
  int _generation = 0;
  bool _background = false;
  bool _restartNeeded = false;
  bool _useFallback = false;

  static Stream<Position> _devicePositions(bool background) =>
      _openDevicePositions(background, false);

  static Stream<Position> _fallbackPositions(bool background) =>
      _openDevicePositions(background, true);

  static Stream<Position> _openDevicePositions(bool background, bool fallback) {
    if (AndroidLocationBridge.supported) {
      return AndroidLocationBridge.positions();
    }
    final LocationSettings settings;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      settings = AndroidSettings(
        forceLocationManager: fallback,
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig: background
            ? const ForegroundNotificationConfig(
                notificationTitle: 'On-duty location sharing',
                notificationText:
                    'Your authorized supervisors can see your duty location until Time Out or scheduled duty end.',
                enableWakeLock: true,
              )
            : null,
      );
    } else if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      settings = AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
        showBackgroundLocationIndicator: background,
        allowBackgroundLocationUpdates: background,
      );
    } else {
      settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      );
    }
    return Geolocator.getPositionStream(locationSettings: settings);
  }

  /// A subscription keeps on-duty background GPS active until cancelled.
  Stream<Position> positions() => _listen(background: true);
  Stream<Position> foregroundPositions() => _listen(background: false);
  Stream<Position> _listen({
    required bool background,
  }) => Stream<Position>.multi((listener) {
    if (background) {
      _backgroundListeners++;
    } else {
      _foregroundWaiters++;
    }
    final subscription = _updates.stream.listen(
      listener.add,
      onError: listener.addError,
    );
    unawaited(_reconcileSource());
    listener.onCancel = () async {
      await subscription.cancel();
      if (background) {
        _backgroundListeners--;
      } else {
        _foregroundWaiters--;
      }
      // Detach immediately on Time Out; native shutdown can finish separately.
      unawaited(_reconcileSource());
    };
  }, isBroadcast: true);

  /// Does not start a second native location request when tracking is active.
  /// Cached timestamps and accuracy are preserved for callers' own checks.
  Future<Position> currentPosition({bool fresh = false}) {
    final cached = _latest;
    if (!fresh && cached != null && _fixProblem(cached) == null) {
      if (_platformService && _foregroundWaiters > 0) {
        unawaited(_reconcileSource());
      }
      return Future<Position>.value(cached);
    }
    return _request ??= _waitForPosition(notBefore: fresh ? _now() : null);
  }

  /// Retry the native provider, rather than waiting on the same stalled stream.
  /// Existing subscribers remain attached and receive the recovered real fixes.
  Future<void> restart() {
    _latest = null;
    _restartNeeded = true;
    _useFallback = !_useFallback;
    return _reconcileSource();
  }

  Future<Position> _waitForPosition({DateTime? notBefore}) async {
    final result = Completer<Position>();
    String? lastProblem = _latestProblem;
    final subscription = _updates.stream.listen(
      (position) {
        if (result.isCompleted) return;
        lastProblem = _fixProblem(position);
        if (lastProblem == null &&
            notBefore != null &&
            position.timestamp.isBefore(notBefore)) {
          lastProblem = 'Waiting for a newly measured GPS location.';
        }
        if (lastProblem == null) result.complete(position);
      },
      onError: (Object error, StackTrace stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    _foregroundWaiters++;
    unawaited(_reconcileSource());
    final recovery = _platformService
        ? null
        : Timer(recoveryDelay, () {
            if (!result.isCompleted) unawaited(restart());
          });
    try {
      return await result.future.timeout(
        requestTimeout,
        onTimeout: () => throw TimeoutException(
          lastProblem ??
              'Acquiring GPS automatically. Keep precise location enabled; recovery continues without tapping Retry.',
          requestTimeout,
        ),
      );
    } finally {
      recovery?.cancel();
      await subscription.cancel();
      _foregroundWaiters--;
      // A slow native cancellation must not extend the caller's deadline.
      // Source transitions remain serialized so a retry cannot overlap it.
      unawaited(_reconcileSource());
      _request = null;
    }
  }

  String? _fixProblem(Position position) {
    if (position.isMocked) {
      return 'Mock or simulated locations cannot be used. Turn off mock location and retry.';
    }
    if (!position.latitude.isFinite ||
        !position.longitude.isFinite ||
        position.latitude.abs() > 90 ||
        position.longitude.abs() > 180 ||
        !position.accuracy.isFinite ||
        position.accuracy <= 0) {
      return 'GPS did not provide usable coordinates and accuracy. Retry GPS.';
    }
    final now = _now();
    if (position.timestamp.isAfter(now.add(const Duration(seconds: 5)))) {
      return 'GPS time is ahead of the device clock. Enable automatic date and time, then retry.';
    }
    if (now.difference(position.timestamp) > maxCacheAge) {
      return 'GPS has only provided an old location. Move to an open area and retry.';
    }
    return null;
  }

  Future<void> _reconcileSource() {
    _transition = _transition
        .then((_) async {
          var needed = _backgroundListeners + _foregroundWaiters > 0;
          var background = _backgroundListeners > 0;
          if (_native != null &&
              (!needed ||
                  (!_platformService && background != _background) ||
                  _restartNeeded)) {
            ++_generation;
            final previous = _native;
            _native = null;
            await previous?.cancel();
            // Consumers may leave while the platform finishes cancelling.
            needed = _backgroundListeners + _foregroundWaiters > 0;
            background = _backgroundListeners > 0;
          }
          if (_platformService && needed) {
            await AndroidLocationBridge.configure();
            _background = background;
          }
          if (!needed || _native != null) return;
          _restartNeeded = false;
          _background = background;
          final generation = ++_generation;
          try {
            _native = (_useFallback ? _fallbackSource : _source)(background)
                .listen(
                  (position) {
                    if (generation != _generation) return;
                    _latestProblem = _fixProblem(position);
                    _latest = _latestProblem == null ? position : null;
                    _updates.add(position);
                  },
                  onError: (Object error, StackTrace stack) {
                    if (generation != _generation) return;
                    _restartNeeded = true;
                    _latest = null;
                    _updates.addError(error, stack);
                  },
                  onDone: () {
                    if (generation != _generation) return;
                    _native = null;
                    _updates.addError(
                      StateError(
                        'GPS stopped. Check location services and retry.',
                      ),
                    );
                  },
                );
          } catch (error, stack) {
            _updates.addError(error, stack);
          }
        })
        .catchError((Object error, StackTrace stack) {
          // Keep later retries usable if the platform fails while cancelling GPS.
          _updates.addError(error, stack);
        });
    return _transition;
  }
}
