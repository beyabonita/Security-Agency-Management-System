import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_session.dart';

/// Follows attendance automatically: current duty, bounded writes, no offline queue.
class LiveLocationController extends ChangeNotifier {
  static const maxAccuracyMeters = 500;
  static const movingUpdateInterval = Duration(seconds: 5);
  static const stationaryUpdateInterval = Duration(seconds: 30);
  LiveLocationController({
    required this.loadDuty,
    required this.positions,
    required this.permission,
    required this.publish,
    required this.remove,
    this.currentPosition,
    this.configureDuty,
    this.publishTimeout = const Duration(seconds: 12),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;
  final Future<AttendanceSession?> Function() loadDuty;
  final Stream<Position> Function() positions;
  final Future<bool> Function() permission;
  final Future<void> Function(String, Position) publish;
  final Future<void> Function(String) remove;
  final Future<Position> Function()? currentPosition;
  final Future<void> Function(DateTime?)? configureDuty;
  final Duration publishTimeout;
  final DateTime Function() now;
  StreamSubscription<Position>? _gps;
  Timer? _timer;
  Timer? _dutyEndTimer;
  AttendanceSession? _duty;
  AttendanceSession? _recordedDuty;
  Future<void>? _write;
  Future<void>? _captureStopping;
  Future<void>? _requestingFix;
  int _captureGeneration = 0;
  // Explicit stop cleanup is separate from rebuilding or leaving a page.
  int _removalGeneration = 0;
  DateTime? lastSent;
  DateTime? _lastPublishedFixAt;
  Position? _lastPublishedPosition;
  bool enabled = false, _refreshing = false, _disposed = false;
  bool _refreshAgain = false;
  int _generation = 0;
  String status = 'Location sharing is off.';
  bool get isCapturing => _gps != null && _duty != null;
  Future<void> attendanceRecorded(AttendanceSession session) async {
    _recordedDuty = session;
    if (enabled) {
      await refresh(requestFresh: true);
    } else {
      await start();
    }
  }

  void _status(String value) {
    status = value;
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    if (enabled || _disposed) return;
    enabled = true;
    final generation = ++_generation;
    _status('Checking duty for automatic location sharing…');
    try {
      _timer = Timer.periodic(const Duration(seconds: 15), (_) => refresh());
      await refresh();
    } catch (_) {
      if (generation == _generation) {
        enabled = false;
        _status('Could not start GPS. Check device permissions and retry.');
      }
    }
  }

  Future<void> refresh({bool requestFresh = false}) async {
    if (!enabled || _disposed) return;
    if (_refreshing) {
      _refreshAgain = true;
      return;
    }
    _refreshing = true;
    final generation = _generation;
    try {
      final fetched =
          _recordedDuty ??
          await loadDuty().timeout(const Duration(seconds: 15));
      // A just-completed attendance RPC supersedes an older in-flight read.
      final duty = _recordedDuty ?? fetched;
      if (_recordedDuty != null) _refreshAgain = false;
      _recordedDuty = null;
      if (!enabled || generation != _generation || _disposed) return;
      if (duty == null ||
          !duty.isOpen ||
          duty.clockOutAt != null ||
          !duty.scheduledEndAt.isAfter(now())) {
        await _stopCapture();
        if (generation == _generation) {
          _status('Location sharing starts automatically when you Time In.');
        }
        return;
      }
      if (_duty?.id != duty.id) await _stopCapture();
      if (!enabled || generation != _generation || _disposed) return;
      await _captureStopping;
      if (!enabled || generation != _generation || _disposed) return;
      if (_gps == null) {
        _status('Checking location permission…');
        final allowed = await permission().timeout(const Duration(seconds: 20));
        if (_disposed || !enabled || generation != _generation) return;
        // A permission prompt can outlast the remaining shift. Recheck the
        // actual deadline before starting native GPS with the earlier result.
        if (!duty.scheduledEndAt.isAfter(now())) {
          await _stopCapture();
          if (generation == _generation && enabled) {
            _status('Duty ended. Location sharing has stopped.');
          }
          return;
        }
        if (!allowed) {
          _status(
            'Allow location permission and enable GPS. Tracking resumes automatically.',
          );
          return;
        }
      }
      _duty = duty;
      _scheduleDutyEnd(duty, generation);
      await configureDuty?.call(duty.scheduledEndAt);
      if (!enabled ||
          _disposed ||
          generation != _generation ||
          !duty.scheduledEndAt.isAfter(now())) {
        return;
      }
      if (_gps == null) {
        final captureGeneration = _captureGeneration;
        _gps = positions().listen(
          (p) => _send(p, generation, captureGeneration),
          onError: (Object error) {
            unawaited(_stopCapture(removeLocation: false));
            _status(
              'GPS interrupted: $error. Retrying automatically while on duty.',
            );
          },
          onDone: () {
            _gps = null;
          },
          cancelOnError: true,
        );
        _status('On duty · waiting for an accurate GPS fix…');
      }
      if (requestFresh ||
          lastSent == null ||
          now().difference(lastSent!) >= const Duration(seconds: 30)) {
        unawaited(_requestFreshFix(generation, _captureGeneration));
      }
    } catch (error) {
      if (generation == _generation) {
        if (_recordedDuty != null) {
          _refreshAgain = true;
          return;
        }
        if (_duty != null &&
            _duty!.scheduledEndAt.isAfter(now()) &&
            !_accessDenied(error)) {
          // Preserve the already-authorized shift and native foreground service
          // through network loss. No offline queue; the server checks every fix.
          _status(
            'Connection interrupted. GPS remains active until duty end; reconnecting automatically.',
          );
        } else {
          await _stopCapture(removeLocation: false);
          _status(
            'Unable to verify duty. Sharing paused; retrying automatically.',
          );
        }
      }
    } finally {
      _refreshing = false;
      if (_refreshAgain) {
        _refreshAgain = false;
        unawaited(refresh(requestFresh: true));
      }
    }
  }

  static bool _accessDenied(Object error) =>
      error is PostgrestException &&
      ['42501', 'PGRST301', 'PGRST302', 'PGRST303'].contains(error.code);

  void _scheduleDutyEnd(AttendanceSession duty, int generation) {
    _dutyEndTimer?.cancel();
    _dutyEndTimer = Timer(duty.scheduledEndAt.difference(now()), () async {
      if (_disposed ||
          !enabled ||
          generation != _generation ||
          _duty?.id != duty.id) {
        return;
      }
      // Stop locally at the known deadline even if the next network check
      // hangs or fails. The server independently enforces the same boundary.
      await _stopCapture();
      if (!_disposed && enabled && generation == _generation && _duty == null) {
        _status('Duty ended. Location sharing has stopped.');
      }
    });
  }

  Future<void> _requestFreshFix(int generation, int captureGeneration) async {
    if (currentPosition == null || _requestingFix != null) return;
    final operation = () async {
      try {
        final position = await currentPosition!().timeout(
          const Duration(seconds: 25),
        );
        await _send(position, generation, captureGeneration);
      } catch (error) {
        if (enabled &&
            !_disposed &&
            generation == _generation &&
            captureGeneration == _captureGeneration &&
            (lastSent == null ||
                now().difference(lastSent!) > const Duration(seconds: 45))) {
          _status(
            error is TimeoutException && error.message != null
                ? '${error.message} GPS recovery will retry automatically while on duty.'
                : 'Waiting for GPS. Retrying automatically while on duty; check precise location permission and move to an open area.',
          );
        }
      }
    }();
    _requestingFix = operation;
    try {
      await operation;
    } finally {
      if (identical(_requestingFix, operation)) _requestingFix = null;
    }
  }

  static String? fixProblem(Position p, AttendanceSession duty, DateTime now) {
    if (p.isMocked) {
      return 'Simulated GPS detected. Use a physical phone with mock location turned off to share a live location.';
    }
    if (!p.latitude.isFinite ||
        !p.longitude.isFinite ||
        p.latitude.abs() > 90 ||
        p.longitude.abs() > 180) {
      return 'GPS returned invalid coordinates. Tap Retry GPS.';
    }
    if (!p.accuracy.isFinite || p.accuracy <= 0) {
      return 'GPS did not report usable accuracy. Enable precise location and tap Retry GPS.';
    }
    if (p.accuracy > maxAccuracyMeters) {
      return 'GPS accuracy is ${p.accuracy.round()} m; 500 m or better is needed for the live map. Enable precise location or move to an open area.';
    }
    if (p.timestamp.isAfter(now.add(const Duration(seconds: 5)))) {
      return 'GPS time is ahead of the device clock. Enable automatic date and time, then retry.';
    }
    if (now.difference(p.timestamp) > const Duration(seconds: 45) ||
        p.timestamp.isBefore(duty.clockInAt)) {
      return 'The phone returned an old GPS fix. Requesting a fresh location…';
    }
    return null;
  }

  Future<void> _send(Position p, int generation, int captureGeneration) async {
    final duty = _duty;
    if (!enabled ||
        _disposed ||
        generation != _generation ||
        captureGeneration != _captureGeneration ||
        duty == null ||
        _write != null) {
      return;
    }
    if (!duty.scheduledEndAt.isAfter(now())) {
      await refresh();
      return;
    }
    final problem = fixProblem(p, duty, now());
    if (problem != null) {
      _status(problem);
      return;
    }
    if (_lastPublishedFixAt != null &&
        !p.timestamp.isAfter(_lastPublishedFixAt!)) {
      return;
    }
    if (lastSent != null) {
      final elapsed = now().difference(lastSent!);
      if (elapsed < movingUpdateInterval) return;
      final previous = _lastPublishedPosition;
      final moved =
          previous == null ||
          Geolocator.distanceBetween(
                previous.latitude,
                previous.longitude,
                p.latitude,
                p.longitude,
              ) >=
              5;
      if (!moved && elapsed < stationaryUpdateInterval) return;
    }
    final delivery = Future<void>.sync(() => publish(duty.id, p));
    final removalGeneration = _removalGeneration;
    var timedOut = false;
    // A transport timeout must not freeze every subsequent GPS upload. If an
    // old request eventually reaches the server after stop, clean up that
    // session's point again. Never remove a newer active duty's location.
    unawaited(
      delivery.then((_) async {
        if (timedOut &&
            removalGeneration != _removalGeneration &&
            (!enabled || _duty?.id != duty.id)) {
          try {
            await remove(duty.id);
          } catch (_) {
            /* Server duty expiry applies. */
          }
        }
      }, onError: (Object _) {}),
    );
    final operation = delivery.timeout(
      publishTimeout,
      onTimeout: () {
        timedOut = true;
        throw TimeoutException('Location upload timed out.', publishTimeout);
      },
    );
    _write = operation;
    try {
      await operation;
      if (generation == _generation &&
          captureGeneration == _captureGeneration &&
          enabled &&
          _duty?.id == duty.id) {
        lastSent = now();
        _lastPublishedFixAt = p.timestamp;
        _lastPublishedPosition = p;
        _status(
          p.accuracy > 100
              ? 'Sharing approximate on-duty location · accuracy ${p.accuracy.round()} m. The map shows the accuracy circle.'
              : 'Sharing on-duty location · accuracy ${p.accuracy.round()} m',
        );
      }
    } catch (error) {
      if (generation == _generation && enabled) {
        if (_accessDenied(error)) {
          unawaited(_stopCapture(removeLocation: false));
        }
        _status(
          error is PostgrestException
              ? 'Location not delivered: ${error.message}'
              : 'Location not delivered. Check connection; retrying with a fresh fix.',
        );
      }
    } finally {
      if (identical(_write, operation)) _write = null;
    }
  }

  Future<void> _stopCapture({bool removeLocation = true}) async {
    if (_captureStopping != null) {
      await _captureStopping;
      if (!removeLocation) return;
    }
    final operation = _finishCapture(removeLocation: removeLocation);
    _captureStopping = operation;
    try {
      await operation;
    } finally {
      if (identical(_captureStopping, operation)) _captureStopping = null;
    }
  }

  Future<void> _finishCapture({required bool removeLocation}) async {
    ++_captureGeneration;
    final subscription = _gps;
    _gps = null;
    final old = _duty;
    // A retry pauses capture without deleting the last real point from the map.
    // Its original timestamp continues aging; backend duty/access filters apply.
    if (removeLocation) {
      if (old != null) ++_removalGeneration;
      _dutyEndTimer?.cancel();
      _dutyEndTimer = null;
      _duty = null;
      lastSent = null;
      _lastPublishedFixAt = null;
      _lastPublishedPosition = null;
      if (old != null) {
        try {
          await configureDuty?.call(null);
        } catch (_) {
          /* Still detach native GPS if the platform channel is lost. */
        }
      }
    }
    await subscription?.cancel();
    try {
      await _write;
    } catch (_) {
      /* Removal must follow an in-flight write. */
    }
    if (removeLocation && old != null) {
      try {
        await remove(old.id);
      } catch (_) {
        /* Server expiry/clock-out still applies. */
      }
    }
  }

  Future<void> stop() async {
    _recordedDuty = null;
    enabled = false;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _dutyEndTimer?.cancel();
    _dutyEndTimer = null;
    await _stopCapture();
    _status('Location sharing is off.');
  }

  @override
  void dispose() {
    _disposed = true;
    enabled = false;
    ++_generation;
    _timer?.cancel();
    _timer = null;
    _dutyEndTimer?.cancel();
    _dutyEndTimer = null;
    // Navigating/rebuilding a page is not Time Out. Explicit sign-out uses stop.
    unawaited(_stopCapture(removeLocation: false));
    super.dispose();
  }
}
