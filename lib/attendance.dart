import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_application_1/models/attendance_session.dart';
import 'package:flutter_application_1/models/geofence_site.dart';
import 'package:flutter_application_1/services/attendance_service.dart';
import 'package:flutter_application_1/services/geofence_service.dart';
import 'package:flutter_application_1/services/location_integrity_service.dart';
import 'package:flutter_application_1/services/schedule_service.dart';
import 'package:flutter_application_1/theme/app_colors.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';

class Attendance extends StatefulWidget {
  const Attendance({super.key});

  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance> {
  bool locationGranted = false;
  bool withinAllowedArea = false;
  LatLng? _currentPosition;
  String? _locationError;
  String? _matchedSiteLabel;
  double? _accuracyMeters;
  List<GeofenceSite> _sites = [];
  bool _loadingSites = true;
  bool _refreshingLocation = false;
  String? _punchingAction;
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadAssignedSites();
    _initLocation();
  }

  Future<void> _loadAssignedSites() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _loadingSites = false);
      return;
    }
    try {
      final sites = await ScheduleService.loadAttendanceSites(user.id);
      if (!mounted) return;
      setState(() {
        _sites = sites;
        _loadingSites = false;
      });
      if (_currentPosition != null) {
        final inside = GeofenceService.isWithinAnySite(
          _currentPosition!,
          sites,
        );
        final nearest = GeofenceService.nearestSite(_currentPosition!, sites);
        setState(() {
          withinAllowedArea = inside;
          _matchedSiteLabel = inside ? nearest?.label : null;
        });
      }
      if (sites.isEmpty && mounted) {
        setState(
          () => _locationError =
              'No active duty schedule right now. Check My Schedule or ask your admin.',
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSites = false;
        _locationError =
            'Could not load your current duty schedule. Refresh and try again.';
      });
    }
  }

  Future<void> _initLocation() async {
    final permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      await _fetchCurrentLocation();
    }
  }

  Future<void> _requestLocationPermission() async {
    setState(() => _locationError = null);
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        locationGranted = false;
        _locationError =
            'Location permission denied. Allow it in device settings.';
      });
      return;
    }
    await _fetchCurrentLocation();
  }

  Future<Position?> _fetchCurrentLocation({List<GeofenceSite>? sites}) async {
    if (mounted) {
      setState(() {
        _locationError = null;
        _refreshingLocation = true;
      });
    }
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return null;
        setState(() {
          locationGranted = false;
          _locationError = 'Enable location services on your device.';
        });
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );
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
      if (!mounted) return null;
      setState(() {
        locationGranted = true;
        _currentPosition = current;
        withinAllowedArea = activeSites.isNotEmpty && inside;
        _matchedSiteLabel = inside ? nearest?.label : null;
        _accuracyMeters = position.accuracy;
        _locationError = integrityError;
      });
      _mapController.move(current, 16);
      return integrityError == null ? position : null;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        locationGranted = false;
        _locationError = 'Could not get a fresh location: $e';
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

      final activeSites = await ScheduleService.loadAttendanceSites(user.id);
      if (!mounted) return;
      setState(() {
        _sites = activeSites;
        _loadingSites = false;
      });
      if (activeSites.isEmpty) {
        _showSnack(
          'No scheduled duty post is available for attendance right now. Ask your admin to check your schedule and deployment.',
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
      final current = LatLng(position.latitude, position.longitude);
      final inside = GeofenceService.isWithinAnySite(current, activeSites);
      if (!inside) {
        _showSnack(
          'You must be within the geofence of your scheduled duty post to record attendance.',
          isError: true,
        );
        return;
      }
      await AttendanceService.recordEvent(
        action: action,
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      _showSnack(
        '${action == 'clock_in' ? 'Time In' : 'Time Out'} recorded successfully ✓',
        isError: false,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''), isError: true);
    } finally {
      if (mounted) setState(() => _punchingAction = null);
    }
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
    final statusColor = _sites.isEmpty
        ? AppColors.warning
        : withinAllowedArea
        ? AppColors.success
        : AppColors.error;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
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
                      color: AppColors.primary,
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
                      decoration: AppColors.card(radius: 14),
                      child: StreamBuilder<void>(
                        stream: Stream.periodic(const Duration(seconds: 1)),
                        builder: (_, __) => Text(
                          _formatNow(),
                          style: const TextStyle(
                            color: AppColors.textMuted,
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
                      const LinearProgressIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.border,
                      )
                    else
                      GuardStatusBanner(
                        message: _sites.isEmpty
                            ? 'No active duty site right now'
                            : withinAllowedArea
                            ? 'Within ${_matchedSiteLabel ?? "your duty site"}'
                            : 'Outside your scheduled duty location',
                        color: statusColor,
                        icon: _sites.isEmpty
                            ? Icons.event_busy_outlined
                            : withinAllowedArea
                            ? Icons.location_on_rounded
                            : Icons.location_off_outlined,
                      ),

                    // ── Error ─────────────────────────────────────────
                    if (_locationError != null) ...[
                      const SizedBox(height: 10),
                      GuardStatusBanner(
                        title: 'Location needs attention',
                        message: _locationError!,
                        color: AppColors.error,
                        icon: Icons.warning_amber_rounded,
                      ),
                      if (_accuracyMeters != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Last GPS accuracy: ${_accuracyMeters!.round()} m. Move to an open area if the signal remains unstable.',
                          style: const TextStyle(
                            color: AppColors.textMuted,
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
                        border: Border.all(color: AppColors.border),
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
                    if (!locationGranted)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _refreshingLocation
                              ? null
                              : _requestLocationPermission,
                          icon: const Icon(Icons.location_on_rounded),
                          label: const Text('Enable location access'),
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
                                    color: AppColors.primary.withValues(
                                      alpha: 0.09,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.24,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.place_rounded,
                                        color: AppColors.primary,
                                        size: 14,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        s.label,
                                        style: const TextStyle(
                                          color: AppColors.primaryDark,
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
                    StreamBuilder<AttendanceSession?>(
                      stream: Supabase.instance.client.auth.currentUser == null
                          ? null
                          : AttendanceService.openSessionStream(
                              Supabase.instance.client.auth.currentUser!.id,
                            ),
                      builder: (context, recordSnap) {
                        final openSession = recordSnap.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            GuardStatusBanner(
                              message: openSession == null
                                  ? 'Your approved schedule controls when and where you can Time In.'
                                  : 'Open duty at ${openSession.locationLabel.isEmpty ? 'your scheduled post' : openSession.locationLabel}. Time Out at the same post.',
                              color: AppColors.primary,
                              icon: openSession == null
                                  ? Icons.info_outline_rounded
                                  : Icons.timelapse_rounded,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _PunchButton(
                                    label: 'Time In',
                                    icon: Icons.login_rounded,
                                    color: const Color(0xFF4ADE80),
                                    enabled:
                                        openSession == null &&
                                        _punchingAction == null,
                                    busy: _punchingAction == 'clock_in',
                                    recordedTime: openSession == null
                                        ? null
                                        : AttendanceService.formatTime(
                                            openSession.clockInAt,
                                          ),
                                    onTap: () => _punch('clock_in'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _PunchButton(
                                    label: 'Time Out',
                                    icon: Icons.logout_rounded,
                                    color: const Color(0xFFFBBF24),
                                    enabled:
                                        openSession != null &&
                                        _punchingAction == null,
                                    busy: _punchingAction == 'clock_out',
                                    onTap: () => _punch('clock_out'),
                                  ),
                                ),
                              ],
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
          urlTemplate:
              'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png',
          subdomains: const ['a', 'b', 'c', 'd'],
          userAgentPackageName: 'com.sentinellink.app',
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
      ],
    );
  }
}

// ─── Punch button ─────────────────────────────────────────────────────────────
class _PunchButton extends StatelessWidget {
  const _PunchButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.enabled = true,
    this.recordedTime,
    this.busy = false,
  });
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool enabled;
  final String? recordedTime;
  final bool busy;

  bool get _recorded =>
      recordedTime != null && recordedTime!.isNotEmpty && recordedTime != '—';

  @override
  Widget build(BuildContext context) {
    final displayColor = _recorded
        ? AppColors.textMuted
        : (enabled ? color : AppColors.textHint);
    return Semantics(
      button: true,
      enabled: enabled && !_recorded,
      label: busy ? 'Recording $label' : label,
      child: GestureDetector(
        onTap: enabled && !_recorded && !busy ? onTap : null,
        child: Opacity(
          opacity: enabled || _recorded ? 1 : 0.4,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: displayColor.withValues(
                alpha: _recorded ? 0.08 : (enabled ? 0.1 : 0.05),
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: displayColor.withValues(
                  alpha: _recorded ? 0.25 : (enabled ? 0.3 : 0.15),
                ),
              ),
            ),
            child: Column(
              children: [
                if (busy)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: displayColor,
                    ),
                  )
                else
                  Icon(
                    _recorded ? Icons.check_circle_rounded : icon,
                    color: _recorded ? AppColors.success : displayColor,
                    size: 24,
                  ),
                const SizedBox(height: 6),
                Text(
                  busy ? 'Recording…' : label,
                  style: TextStyle(
                    color: displayColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (_recorded) ...[
                  const SizedBox(height: 4),
                  Text(
                    recordedTime!,
                    style: const TextStyle(
                      color: AppColors.success,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
