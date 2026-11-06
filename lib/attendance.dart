import 'dart:async';

import 'package:flutter/material.dart';
import 'widgets/overtime_timeout_dialog.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/models/geofence_site.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/attendance_state_controller.dart';
import 'package:flutter_application_1/services/device_location_service.dart';
import 'package:flutter_application_1/services/geofence_service.dart';
import 'package:flutter_application_1/services/location_integrity_service.dart';
import 'package:flutter_application_1/services/schedule_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';
import 'package:flutter_application_1/widgets/attendance_punch_action.dart';
import 'package:flutter_application_1/widgets/attendance_actual_times.dart';
import 'package:flutter_application_1/models/contract_period.dart';
import 'package:flutter_application_1/services/device_verification_service.dart';
import 'package:flutter_application_1/services/user_profile_service.dart';
import 'package:flutter_application_1/widgets/attendance_face_capture_dialog.dart';

/// Public, no-key tile source used by the Guard attendance map.
///
/// Keep this independent from Supabase credentials: a map-provider key must
/// never be required before a Guard can verify a duty location.
const attendanceMapTileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class Attendance extends StatefulWidget {
  const Attendance({super.key, this.onAttendanceRecorded});
  final VoidCallback? onAttendanceRecorded;

  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance> with WidgetsBindingObserver {
  Timer? _dutyRefreshTimer;
  Timer? _gpsRefreshTimer;
  StreamSubscription<Position>? _gpsUpdates;
  Timer? _shiftEndTimer;
  bool _loadingDutyContext = false;
  bool locationGranted = false;
  bool withinAllowedArea = false;
  LatLng? _currentPosition;
  String? _locationError;
  String? _matchedSiteLabel;
  double? _accuracyMeters;
  double? _distanceToNearestMeters;
  DeviceVerificationResult? _deviceVerification;
  DateTime? _positionCapturedAt;
  List<GeofenceSite> _sites = [];
  Map<String, dynamic>? _activeSchedule;
  bool _loadingSites = true;
  bool _refreshingLocation = false;
  Future<Position?>? _locationRequest;
  String? _punchingAction;
  late final AttendanceStateController _attendance;
  StreamSubscription<AttendanceSession?>? _sessionChanges;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _attendance = AttendanceStateController(
      loadSession: () async {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw StateError('Sign in to record attendance.');
        return AttendanceService.loadLatestSession(user.id);
      },
    );
    _attendance.addListener(_scheduleAttendanceBoundary);
    _dutyRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (_punchingAction == null) {
        _loadAssignedSites();
        _attendance.refresh();
      }
    });
    _attendance.refresh();
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      _sessionChanges = AttendanceService.latestSessionStream(
        user.id,
      ).listen(_attendance.accept, onError: (_) => _attendance.refresh());
    }
    _loadAssignedSites();
    _initLocation();
    unawaited(_verifyDevice());
    _gpsRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
          _punchingAction == null) {
        unawaited(_initLocation());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initLocation();
      _attendance.refresh();
      _loadAssignedSites();
    } else if (state == AppLifecycleState.paused) {
      // The app-wide duty subscription keeps its native service. Verification
      // alone must not keep collecting after the attendance screen is hidden.
      unawaited(_gpsUpdates?.cancel());
      _gpsUpdates = null;
    }
  }

  @override
  void dispose() {
    _shiftEndTimer?.cancel();
    _gpsRefreshTimer?.cancel();
    _gpsUpdates?.cancel();
    _dutyRefreshTimer?.cancel();
    _sessionChanges?.cancel();
    _attendance.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _mapController.dispose();
    super.dispose();
  }

  void _scheduleAttendanceBoundary() {
    _shiftEndTimer?.cancel();
    final session = _attendance.session;
    if (session == null || !session.isActiveAt(DateTime.now())) return;
    _shiftEndTimer = Timer(
      session.scheduledEndAt.difference(DateTime.now()),
      () {
        if (!mounted) return;
        setState(() {});
        _loadAssignedSites();
      },
    );
  }

  Future<void> _loadAssignedSites() async {
    if (_loadingDutyContext || !mounted) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _loadingSites = false);
      return;
    }
    _loadingDutyContext = true;
    try {
      final dutyContext = await ScheduleService.loadAttendanceContext(user.id);
      final sites = dutyContext.sites;
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _activeSchedule = dutyContext.primarySchedule;
        _loadingSites = false;
      });
      if (_currentPosition != null) {
        final inside = GeofenceService.isWithinAnySite(
          _currentPosition!,
          sites,
        );
        final nearest = GeofenceService.nearestSite(_currentPosition!, sites);
        final distMeters = GeofenceService.distanceMetersToNearestSite(
          _currentPosition!,
          sites,
        );
        setState(() {
          withinAllowedArea = inside;
          _matchedSiteLabel = inside ? nearest?.label : null;
          _distanceToNearestMeters = distMeters;
        });
      }
      if (sites.isEmpty && mounted) {
        setState(
          () => _locationError =
              'No active duty schedule right now. Check My Schedule or ask your Operational Head.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSites = false;
        _locationError =
            'Could not load your current duty schedule. Refresh and try again.';
      });
    } finally {
      _loadingDutyContext = false;
    }
  }

  Future<void> _initLocation() async {
    try {
      final permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 10),
      );
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        if (mounted) setState(() => locationGranted = true);
        await _fetchCurrentLocation();
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationError =
              'Could not check location permission. Tap Enable location access to retry.',
        );
      }
    }
  }

  Future<void> _requestLocationPermission() async {
    setState(() => _locationError = null);
    try {
      var permission = await Geolocator.checkPermission().timeout(
        const Duration(seconds: 10),
      );
      if (permission == LocationPermission.deniedForever) {
        await Geolocator.openAppSettings();
        return;
      }
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission().timeout(
          const Duration(seconds: 30),
        );
      }
      if (!mounted) return;
      final allowed =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      setState(() => locationGranted = allowed);
      if (!allowed) {
        setState(
          () => _locationError =
              'Location permission denied. Allow it in device settings.',
        );
        return;
      }
      await _fetchCurrentLocation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _locationError =
              'Could not check location access. Retry or open device settings.',
        );
      }
    }
  }

  Future<Position?> _fetchCurrentLocation({List<GeofenceSite>? sites}) {
    if (_locationRequest != null) return _locationRequest!;
    final operation = _loadCurrentLocation(sites: sites);
    _locationRequest = operation;
    return operation.whenComplete(() {
      if (identical(_locationRequest, operation)) _locationRequest = null;
    });
  }

  Future<Position?> _loadCurrentLocation({List<GeofenceSite>? sites}) async {
    if (mounted) {
      setState(() {
        _locationError = null;
        _refreshingLocation = true;
      });
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 10));
      if (!serviceEnabled) {
        if (!mounted) return null;
        setState(() {
          _locationError = 'Enable location services on your device.';
          withinAllowedArea = false;
        });
        return null;
      }

      _gpsUpdates ??= DeviceLocationService.instance.foregroundPositions().listen(
        (_) {
          if (mounted && !_refreshingLocation) {
            unawaited(_fetchCurrentLocation());
          }
        },
        onError: (_) {
          // Keep the screen usable; the timer and native service recover GPS.
        },
        onDone: () {
          _gpsUpdates = null;
        },
      );
      final position = await DeviceLocationService.instance.currentPosition();
      final integrityError = LocationIntegrityService.validationError(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        capturedAt: position.timestamp,
        isMocked: position.isMocked,
      );
      final current = LatLng(position.latitude, position.longitude);
      final activeSites = sites ?? _sites;
      // Location quality and location matching are separate checks. A guard
      // may be physically inside the post but still need a more accurate GPS
      // fix before attendance can be recorded.
      final inside =
          activeSites.isNotEmpty &&
          GeofenceService.isWithinAnySite(current, activeSites);
      final nearest = GeofenceService.nearestSite(current, activeSites);
      final distMeters = GeofenceService.distanceMetersToNearestSite(
        current,
        activeSites,
      );
      if (!mounted) return null;
      setState(() {
        locationGranted = true;
        _currentPosition = current;
        withinAllowedArea = activeSites.isNotEmpty && inside;
        _matchedSiteLabel = inside ? nearest?.label : null;
        _distanceToNearestMeters = distMeters;
        _accuracyMeters = position.accuracy;
        _positionCapturedAt = position.timestamp;
        _locationError = integrityError;
      });
      _mapController.move(current, 16);
      return integrityError == null ? position : null;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        withinAllowedArea = false;
        _matchedSiteLabel = null;
        _locationError = e is TimeoutException
            ? e.message ??
                  'Acquiring GPS automatically. Keep precise location enabled; attendance updates when a usable fix arrives.'
            : e is PermissionDeniedException
            ? 'Location permission is denied. Enable it in device settings.'
            : 'GPS is reconnecting automatically. Check that location services are on.';
        if (e is PermissionDeniedException) locationGranted = false;
      });
      return null;
    } finally {
      if (mounted) setState(() => _refreshingLocation = false);
    }
  }

  Future<void> _punch(String action) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || _punchingAction != null) return;

    setState(() => _punchingAction = action);

    try {
      final openSession = await AttendanceService.loadOpenSession(user.id);
      final blockReason = AttendanceService.blockReasonForAction(
        action,
        openSession,
      );
      if (blockReason != null) {
        _showSnack(blockReason, isError: true);
        return;
      }
      bool? claimOvertime;
      if (action == 'clock_out' &&
          DateTime.now().isAfter(openSession!.scheduledEndAt)) {
        if (!mounted) return;
        claimOvertime = await askOvertimeTimeout(
          context,
          AttendanceActualTimes.timestamp(openSession.scheduledEndAt),
        );
        if (!mounted || claimOvertime == null) return;
      }

      if (action == 'clock_in') {
        final profile = await UserProfileService.getProfile(user.id);
        if (!mounted) return;
        if (profile == null) {
          throw Exception('Could not verify your contract. Please retry.');
        }
        final contractReason = ContractPeriod.fromProfile(
          profile,
        ).timeInBlockReason(DateTime.now());
        if (contractReason != null) {
          _showSnack(contractReason, isError: true);
          return;
        }
      }

      final dutyContext = await ScheduleService.loadAttendanceContext(user.id);
      // Time Out must use the original session post, never another nearby
      // post belonging to a new or overlapping schedule.
      final activeSites = action == 'clock_out'
          ? await GeofenceService.loadSitesForUser([openSession!.locationId])
          : dutyContext.sites;
      if (!mounted) return;
      setState(() {
        _sites = activeSites;
        _activeSchedule = dutyContext.primarySchedule;
        _loadingSites = false;
      });
      if (activeSites.isEmpty) {
        _showSnack(
          'No scheduled duty post is available for attendance right now. Ask your Operations Head to check your schedule and deployment.',
          isError: true,
        );
        return;
      }

      final position = await _fetchCurrentLocation(sites: activeSites);
      if (!mounted) return;
      if (position == null) {
        _showSnack(
          _locationError ?? 'Could not verify a fresh location for attendance.',
          isError: true,
        );
        return;
      }
      if (action == 'clock_out' && position.accuracy > 100) {
        _showSnack(
          'Time Out needs GPS accuracy of 100 m or better. GPS will retry automatically.',
          isError: true,
        );
        return;
      }
      final current = LatLng(position.latitude, position.longitude);
      final inside = GeofenceService.isWithinAnySite(current, activeSites);
      final distMeters = GeofenceService.distanceMetersToNearestSite(
        current,
        activeSites,
      );
      final nearestSite = GeofenceService.nearestSite(current, activeSites);

      final devCheck = await _verifyDevice();
      if (!mounted) return;
      if (!devCheck.verified) {
        _showSnack(
          devCheck.message ??
              "We couldn't recognize this device. Please try again using your authorized device.",
          isError: true,
        );
        return;
      }

      if (!inside) {
        await _promptForceAttendance(
          action: action,
          position: position,
          nearestSite: nearestSite,
          distanceMeters: distMeters,
          openSession: openSession,
          claimOvertime: claimOvertime,
          deviceVerification: devCheck,
        );
        return;
      }

      String? facePhotoDataUrl;
      if (action == 'clock_in') {
        facePhotoDataUrl = await captureAttendanceFaceVerification(
          context,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracyMeters: position.accuracy,
          locationLabel: nearestSite?.label ?? _matchedSiteLabel,
          deviceLabel: '${devCheck.deviceInfo} (${devCheck.deviceId})',
          actionLabel: 'Time In Face Verification',
        );
        if (!mounted || facePhotoDataUrl == null) {
          _showSnack(
            'Live geotagged face verification photo is required to Time In.',
            isError: true,
          );
          return;
        }
      }

      var recordedSession = await AttendanceService.recordEvent(
        action: action,
        sessionId: openSession?.id,
        claimOvertime: claimOvertime,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      try {
        recordedSession = await AttendanceService.attachVerificationMetadata(
          sessionId: recordedSession.id,
          deviceId: devCheck.deviceId,
          deviceInfo: devCheck.deviceInfo,
          facePhotoDataUrl: facePhotoDataUrl,
          distanceFromPostMeters: distMeters,
        );
      } catch (_) {}
      _attendance.accept(recordedSession);
      widget.onAttendanceRecorded?.call();
      if (!mounted) return;
      _showSnack(
        recordedSession.overtimeApprovalPending
            ? 'Overtime Time Out submitted. Your Operations Head has been notified.'
            : action == 'clock_out' && claimOvertime == false
            ? 'Time Out recorded using your scheduled end. No overtime requested.'
            : '${action == 'clock_in' ? 'Time In' : 'Time Out'} recorded successfully.',
        isError: false,
      );
      // Time Out completes only this scheduled period. Refresh the context
      // before another punch so the next Morning/Afternoon/Overtime labels
      // replace the completed period instead of staying cached on screen.
      if (action == 'clock_out') {
        setState(() => _activeSchedule = null);
      }
      await _loadAssignedSites();
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        e is PostgrestException
            ? e.message
            : e is TimeoutException
            ? 'Attendance could not be confirmed in time. Check the updated duty record before retrying.'
            : e.toString().replaceFirst('Exception: ', ''),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          _punchingAction = null;
          // Verify uncertain results without discarding confirmed attendance.
        });
        _attendance.refresh();
      }
    }
  }

  Future<DeviceVerificationResult> _verifyDevice({bool forceRefresh = false}) async {
    final res = await DeviceVerificationService.verifyCurrentDevice(
      forceRefresh: forceRefresh,
    );
    if (mounted) {
      setState(() => _deviceVerification = res);
    }
    return res;
  }

  Future<void> _promptForceAttendance({
    required String action,
    required Position position,
    required GeofenceSite? nearestSite,
    required double? distanceMeters,
    required AttendanceSession? openSession,
    required bool? claimOvertime,
    required DeviceVerificationResult deviceVerification,
  }) async {
    final siteLabel = nearestSite?.label ?? 'Scheduled Duty Post';
    final distText = distanceMeters != null
        ? '${distanceMeters.round()} m away from $siteLabel'
        : 'Outside $siteLabel geofence';

    if (action == 'clock_out' && openSession != null) {
      final confirmOut = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Outside Location Time Out'),
          content: Text(
            'You are currently $distText.\n\n'
            'Submit this Time Out subject to Operations Head Force Attendance review?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Submit Force Time Out'),
            ),
          ],
        ),
      );
      if (confirmOut != true || !mounted) return;
      final session = await AttendanceService.requestForceAttendanceClockOut(
        sessionId: openSession.id,
        latitude: position.latitude,
        longitude: position.longitude,
        claimOvertime: claimOvertime,
      );
      _attendance.accept(session);
      widget.onAttendanceRecorded?.call();
      if (!mounted) return;
      _showSnack(
        'Outside-location Time Out recorded and sent to Operations Head for approval.',
        isError: false,
      );
      setState(() => _activeSchedule = null);
      await _loadAssignedSites();
      return;
    }

    var reasonDraft = 'Seminar / Off-Site Assignment';
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force Attendance (Outside Post)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dual-Point Proximity Check: $distText.\n\n'
              'You can still Time In outside your designated post (e.g., Seminar, Training, or Roving Duty) subject to Operations Head Force Attendance approval.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: reasonDraft,
              onChanged: (value) => reasonDraft = value,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Reason for Outside-Post Time In *',
                hintText: 'e.g., Agency Seminar, Roving Post, Client Errand',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(reasonDraft.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Continue to Face Capture'),
          ),
        ],
      ),
    );
    if (reason == null || reason.length < 5 || !mounted) {
      if (reason != null && reason.length < 5) {
        _showSnack(
          'Please enter a reason of at least 5 characters for Force Attendance.',
          isError: true,
        );
      }
      return;
    }

    final facePhotoDataUrl = await captureAttendanceFaceVerification(
      context,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      locationLabel: '$siteLabel (FORCE ATTENDANCE - ${distanceMeters?.round() ?? 0}m)',
      deviceLabel: '${deviceVerification.deviceInfo} (${deviceVerification.deviceId})',
      actionLabel: 'Force Attendance Face Verification',
    );
    if (!mounted || facePhotoDataUrl == null) {
      _showSnack(
        'Geotagged face verification photo is required for Force Attendance.',
        isError: true,
      );
      return;
    }

    final recorded = await AttendanceService.requestForceAttendanceClockIn(
      latitude: position.latitude,
      longitude: position.longitude,
      reason: reason,
      deviceId: deviceVerification.deviceId,
      deviceInfo: deviceVerification.deviceInfo,
      facePhotoDataUrl: facePhotoDataUrl,
    );
    _attendance.accept(recorded);
    widget.onAttendanceRecorded?.call();
    if (!mounted) return;
    _showSnack(
      'Force Attendance Time In recorded (Pending Operations Head approval).',
      isError: false,
    );
    await _loadAssignedSites();
  }

  void _showSnack(String msg, {required bool isError}) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? AppColors.error : AppColors.success,
      ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final minute = now.minute.toString().padLeft(2, '0');
    final period = now.hour >= 12 ? 'PM' : 'AM';
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    return '${weekdays[now.weekday - 1]}, $month/$day/${now.year}  ${hour.toString().padLeft(2, '0')}:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final positionFresh =
        _positionCapturedAt != null &&
        DateTime.now().difference(_positionCapturedAt!).abs() <=
            LocationIntegrityService.maxFixAge;
    final locationVerified = positionFresh && _locationError == null;
    final statusColor = !locationVerified || _sites.isEmpty
        ? AppColors.of(context).warning
        : withinAllowedArea
        ? AppColors.of(context).success
        : AppColors.of(context).error;

    return Scaffold(
      backgroundColor: AppColors.of(context).scaffold,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            GuardPageTopBar(
              title: 'Attendance & Duty Log',
              subtitle: 'Scheduled-post verification',
              onBack: () => Navigator.pop(context),
              trailing: _refreshingLocation
                  ? const SizedBox(
                      width: 44,
                      height: 44,
                      child: Padding(
                        padding: EdgeInsets.all(11),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : GuardIconButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Refresh location',
                      color: AppColors.of(context).accent,
                      onPressed: _fetchCurrentLocation,
                    ),
            ),

            const SizedBox(height: 16),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    // ── Time display ──────────────────────────────────
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: AppColors.card(context: context, radius: 14),
                      child: StreamBuilder<void>(
                        stream: Stream.periodic(const Duration(seconds: 1)),
                        builder: (_, __) => Text(
                          _formatNow(),
                          style: TextStyle(
                            color: AppColors.of(context).textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // ── Sites status ──────────────────────────────────
                    if (_loadingSites)
                      LinearProgressIndicator(
                        color: AppColors.of(context).accent,
                        backgroundColor: AppColors.of(context).border,
                      )
                    else
                      GuardStatusBanner(
                        message: !locationVerified
                            ? 'Duty location not verified yet'
                            : _sites.isEmpty
                            ? 'No active duty site right now'
                            : withinAllowedArea
                            ? 'Within ${_matchedSiteLabel ?? "your duty site"}${_distanceToNearestMeters != null ? " (${_distanceToNearestMeters!.round()} m from post center)" : ""}'
                            : 'Outside scheduled post${_distanceToNearestMeters != null ? " (${_distanceToNearestMeters!.round()} m away)" : ""} — Force Attendance available',
                        color: statusColor,
                        icon: _sites.isEmpty
                            ? Icons.event_busy_outlined
                            : withinAllowedArea
                            ? Icons.location_on_rounded
                            : Icons.location_off_outlined,
                      ),
                    if (_deviceVerification != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: (_deviceVerification!.verified
                                  ? AppColors.of(context).success
                                  : AppColors.of(context).error)
                              .withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (_deviceVerification!.verified
                                    ? AppColors.of(context).success
                                    : AppColors.of(context).error)
                                .withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _deviceVerification!.verified
                                  ? Icons.phonelink_lock_rounded
                                  : Icons.phonelink_erase_rounded,
                              size: 16,
                              color: _deviceVerification!.verified
                                  ? AppColors.of(context).success
                                  : AppColors.of(context).error,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _deviceVerification!.verified
                                    ? 'Verified Device: ${_deviceVerification!.deviceInfo} (${_deviceVerification!.deviceId})'
                                    : (_deviceVerification!.message ??
                                          "We couldn't recognize this device. Please try again using your authorized device."),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.of(context).text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // ── Error ─────────────────────────────────────────
                    if (_locationError != null) ...[
                      const SizedBox(height: 10),
                      GuardStatusBanner(
                        title: 'Location needs attention',
                        message: _locationError!,
                        color: AppColors.of(context).error,
                        icon: Icons.warning_amber_rounded,
                      ),
                      if (_accuracyMeters != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Last GPS accuracy: ${_accuracyMeters!.round()} m. Move to an open area if the signal remains unstable.',
                          style: TextStyle(
                            color: AppColors.of(context).textMuted,
                            fontSize: 11,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],

                    const SizedBox(height: 14),

                    // ── Map ───────────────────────────────────────────
                    Container(
                      height: 220,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: AppColors.of(context).border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0D451014),
                            blurRadius: 18,
                            offset: Offset(0, 7),
                          ),
                        ],
                      ),
                      child: _buildMap(),
                    ),

                    const SizedBox(height: 14),

                    // ── Location button ───────────────────────────────
                    if (!locationGranted || !locationVerified)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _refreshingLocation
                              ? null
                              : locationGranted
                              ? () => _fetchCurrentLocation()
                              : _requestLocationPermission,
                          icon: const Icon(Icons.location_on_rounded),
                          label: Text(
                            locationGranted
                                ? 'Retry GPS'
                                : 'Enable location access',
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // ── Assigned sites chips ──────────────────────────
                    if (_sites.isNotEmpty) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _sites
                              .map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.of(
                                      context,
                                    ).accent.withValues(alpha: 0.09),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.of(
                                        context,
                                      ).accent.withValues(alpha: 0.24),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.place_rounded,
                                        color: AppColors.of(context).accent,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        s.label,
                                        style: TextStyle(
                                          color: AppColors.of(context).accent,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Schedule-linked Time In / Time Out ─────────────
                    ListenableBuilder(
                      listenable: _attendance,
                      builder: (context, _) {
                        final openSession = AttendanceService.sessionForDuty(
                          _attendance.session,
                          _activeSchedule?['id']?.toString(),
                        );
                        final missingTimeOut =
                            _attendance.latestSession?.isMissingTimeOutAt(
                              DateTime.now(),
                            ) ??
                            false;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (missingTimeOut && openSession == null) ...[
                              GuardStatusBanner(
                                message:
                                    'Missing Time Out. Ask your Operations Head to verify the actual end time.',
                                color: AppColors.of(context).accent,
                                icon: Icons.info_outline_rounded,
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (_attendance.error != null)
                              GuardStatusBanner(
                                message:
                                    'Could not confirm attendance. Retry before recording a punch.',
                                color: AppColors.of(context).error,
                                icon: Icons.sync_problem_rounded,
                              ),
                            if (_attendance.error != null)
                              TextButton(
                                onPressed: _attendance.refresh,
                                child: const Text('Retry attendance'),
                              ),
                            if (openSession != null &&
                                openSession.forceAttendancePending) ...[
                              GuardStatusBanner(
                                message:
                                    'Force Attendance Pending: Waiting for Operations Head approval (${openSession.forceAttendanceReason ?? "Outside post"}).',
                                color: AppColors.of(context).warning,
                                icon: Icons.pending_actions_rounded,
                              ),
                              const SizedBox(height: 10),
                            ],
                            AttendancePunchAction(
                              hasOpenDuty: openSession != null,
                              loading: _attendance.initialLoading,
                              busy: _punchingAction != null,
                              enabled:
                                  _attendance.error == null &&
                                  _attendance.hasConfirmedSession &&
                                  (openSession != null ||
                                      (_activeSchedule != null &&
                                          !ScheduleService.isScheduleEnded(
                                            _activeSchedule!,
                                          ))) &&
                                  (openSession != null || !_loadingSites),
                              onPunch: _punch,
                            ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap() {
    final center =
        _currentPosition ??
        (_sites.isNotEmpty
            ? _sites.first.point
            : const LatLng(14.5995, 120.9842));
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: attendanceMapTileUrlTemplate,
          userAgentPackageName: 'com.sentinellink.app',
          maxNativeZoom: 19,
        ),
        CircleLayer(
          circles: [
            for (final site in _sites)
              CircleMarker(
                point: site.point,
                radius: site.radiusMeters,
                useRadiusInMeter: true,
                color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                borderColor: const Color(0xFFDC2626),
                borderStrokeWidth: 2,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final site in _sites)
              Marker(
                point: site.point,
                width: 36,
                height: 36,
                child: const Icon(
                  Icons.place_rounded,
                  color: Color(0xFFF87171),
                  size: 28,
                ),
              ),
            if (_currentPosition != null)
              Marker(
                point: _currentPosition!,
                width: 40,
                height: 40,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFDC2626),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFDC2626).withValues(alpha: 0.5),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: Material(
            color: const Color(0xEFFFFFFF),
            child: InkWell(
              onTap: () async {
                try {
                  await launchUrl(
                    Uri.parse('https://www.openstreetmap.org/copyright'),
                    mode: LaunchMode.externalApplication,
                  );
                } catch (_) {
                  if (mounted) {
                    _showSnack(
                      'Could not open map information.',
                      isError: true,
                    );
                  }
                }
              },
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                child: Text(
                  '© OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10, color: Color(0xFF334155)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
