import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/attendance_session.dart';
import '../services/android_location_bridge.dart';
import '../services/attendance_service.dart';
import '../services/device_location_service.dart';
import '../services/live_location_controller.dart';
import '../supabase_config.dart';

const liveTrackingEnabled = bool.fromEnvironment(
  'LIVE_TRACKING_ENABLED',
  defaultValue: true,
);
bool isTrackingEndpoint(String url) =>
    isLocalTrackingEndpoint(url) ||
    url == 'https://uqtupmpofjqrnefgrexm.supabase.co';
bool isLocalTrackingEndpoint(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      ['http', 'https'].contains(uri.scheme) &&
      ['localhost', '127.0.0.1', '10.0.2.2', '::1'].contains(uri.host);
}

/// App-level owner. Routes, dashboard rebuilds, and screen lock never stop duty
/// capture. There is deliberately no location panel or manual retry control.
class DutyTrackingScope extends StatefulWidget {
  const DutyTrackingScope({
    super.key,
    required this.child,
    this.controller,
    this.attendanceEvents,
    this.configureLocation,
    this.handoffPositions,
  });
  final Widget child;
  final LiveLocationController? controller;
  final Stream<AttendanceSession>? attendanceEvents;
  final Future<void> Function(DateTime?)? configureLocation;
  final Stream<Position> Function()? handoffPositions;
  static DutyTrackingScopeState? of(BuildContext context) =>
      context.findAncestorStateOfType<DutyTrackingScopeState>();
  @override
  State<DutyTrackingScope> createState() => DutyTrackingScopeState();
}

class DutyTrackingScopeState extends State<DutyTrackingScope>
    with WidgetsBindingObserver {
  late final LiveLocationController tracker;
  StreamSubscription<AuthState>? _auth;
  StreamSubscription<AttendanceSession>? _attendance;
  StreamSubscription<ServiceStatus>? _locationServices;
  String? _user;
  int _authRevision = 0;
  bool _askedPermission = false, _askedNotification = false;
  StreamSubscription<Position>? _handoff;
  Timer? _handoffDeadline;
  int _attendanceRevision = 0;
  Future<void>? _refreshingAuth;
  Future<void> _ensureFreshSession() async {
    final client = Supabase.instance.client;
    final session = client.auth.currentSession;
    if (session == null) {
      throw const AuthException('Sign in to share duty location.');
    }
    final expires = session.expiresAt;
    if (expires == null ||
        expires * 1000 > DateTime.now().millisecondsSinceEpoch + 60000) {
      return;
    }
    // Supabase's UI lifecycle pauses its automatic refresh in the background.
    // Duty uploads must still renew the guard's own session while screen-off.
    final operation = _refreshingAuth ??= client.auth
        .refreshSession()
        .then<void>((_) {});
    try {
      await operation;
    } finally {
      if (identical(_refreshingAuth, operation)) _refreshingAuth = null;
    }
  }

  void _releaseHandoff() {
    _handoffDeadline?.cancel();
    _handoffDeadline = null;
    unawaited(_handoff?.cancel());
    _handoff = null;
  }

  String? _debugStatus;
  void _reportStatus() {
    if (tracker.isCapturing) _releaseHandoff();
    if (kDebugMode && tracker.status != _debugStatus) {
      _debugStatus = tracker.status;
      debugPrint('[Duty GPS] ${tracker.status}');
    }
  }

  bool get _foreground =>
      WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> stopSharing() async {
    ++_attendanceRevision;
    _releaseHandoff();
    await tracker.stop();
  }

  Future<void> syncDuty() async {
    if (!mounted || (widget.controller == null && _user == null)) return;
    try {
      if (tracker.enabled) {
        await tracker.refresh(requestFresh: true);
      } else {
        await tracker.start();
      }
    } catch (_) {
      /* Controller automatically retries verified duty checks. */
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tracker = widget.controller ?? _createTracker();
    tracker.addListener(_reportStatus);
    if (widget.attendanceEvents != null) {
      _attendance = widget.attendanceEvents!.listen(
        (session) => unawaited(_onAttendance(session)),
      );
    }
    if (widget.controller != null) {
      unawaited(syncDuty());
      return;
    }
    if (!liveTrackingEnabled || !isTrackingEndpoint(SupabaseConfig.url)) return;
    final client = Supabase.instance.client;
    _user = client.auth.currentUser?.id;
    _auth = client.auth.onAuthStateChange.listen((state) async {
      final next = state.session?.user.id;
      if (next == _user) return;
      _user = next;
      _releaseHandoff();
      final revision = ++_authRevision;
      await tracker.stop();
      if (mounted && revision == _authRevision && next != null) {
        await syncDuty();
      }
    });
    _attendance ??= AttendanceService.recordedEvents.listen((session) {
      if (_user != null) unawaited(_onAttendance(session));
    });
    _locationServices = Geolocator.getServiceStatusStream().listen(
      (status) {
        if (status == ServiceStatus.enabled) unawaited(syncDuty());
      },
      onError: (_) {
        /* Native provider recovery remains active. */
      },
    );
    unawaited(syncDuty());
  }

  Future<void> _onAttendance(AttendanceSession session) async {
    final revision = ++_attendanceRevision;
    final user = _user;
    final configure =
        widget.configureLocation ?? AndroidLocationBridge.setDutyEnd;
    try {
      // Upgrade the running attendance collector immediately, before any
      // network refresh, so locking the phone after Time In is safe.
      if (session.isOpen && session.clockOutAt == null) {
        final configured = configure(session.scheduledEndAt);
        // Transfer ownership before awaiting any network/platform result.
        // Locking the phone immediately after Time In cannot drop the service.
        _releaseHandoff();
        _handoff =
            (widget.handoffPositions ??
                    DeviceLocationService.instance.positions)()
                .listen((_) {}, onError: (_) {});
        _handoffDeadline = Timer(const Duration(seconds: 30), _releaseHandoff);
        await configured;
        if (!mounted || revision != _attendanceRevision || user != _user) {
          return;
        }
        await tracker.attendanceRecorded(session);
      } else {
        _releaseHandoff();
        await tracker.stop();
        await configure(null);
      }
    } catch (_) {
      await syncDuty();
    }
  }

  LiveLocationController _createTracker() {
    final client = Supabase.instance.client;
    return LiveLocationController(
      loadDuty: () async {
        final id = client.auth.currentUser?.id;
        if (id == null) return null;
        await _ensureFreshSession();
        final profile = await client
            .from('profiles')
            .select('active,role')
            .eq('id', id)
            .maybeSingle()
            .timeout(const Duration(seconds: 10));
        if (profile == null ||
            profile['active'] != true ||
            profile['role'] != 'user') {
          return null;
        }
        return AttendanceService.loadOpenSession(id);
      },
      permission: () async {
        if (!await Geolocator.isLocationServiceEnabled()) return false;
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied &&
            !_askedPermission &&
            _foreground) {
          _askedPermission = true;
          permission = await Geolocator.requestPermission();
        }
        final allowed =
            permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
        if (allowed && !_askedNotification && _foreground) {
          _askedNotification = true;
          await AndroidLocationBridge.requestNotificationPermission();
        }
        return allowed;
      },
      configureDuty: AndroidLocationBridge.setDutyEnd,
      positions: DeviceLocationService.instance.positions,
      currentPosition: DeviceLocationService.instance.currentPosition,
      publish: (session, position) async {
        await _ensureFreshSession();
        await client.rpc(
          'publish_guard_location',
          params: {
            'p_session_id': session,
            'p_latitude': position.latitude,
            'p_longitude': position.longitude,
            'p_accuracy_meters': position.accuracy,
            'p_captured_at': position.timestamp.toUtc().toIso8601String(),
            'p_is_mocked': position.isMocked,
          },
        );
      },
      remove: (session) =>
          client.rpc('stop_guard_location', params: {'p_session_id': session}),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(syncDuty());
  }

  @override
  void dispose() {
    ++_authRevision;
    ++_attendanceRevision;
    _releaseHandoff();
    _auth?.cancel();
    _attendance?.cancel();
    _locationServices?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    tracker.removeListener(_reportStatus);
    tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
