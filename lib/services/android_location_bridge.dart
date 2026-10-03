import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Android owns the foreground service and its duty deadline, not a page.
class AndroidLocationBridge {
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const _commands = MethodChannel('sentinel/duty_location');
  static const _events = EventChannel('sentinel/duty_location/positions');
  static DateTime? _dutyEnd;

  static Future<void> setDutyEnd(DateTime? value) async {
    _dutyEnd = value;
    if (supported) await configure();
  }

  static Future<void> configure() async {
    if (!supported) return;
    await _commands.invokeMethod<void>('configure', {
      'dutyEnd': _dutyEnd?.millisecondsSinceEpoch,
    });
  }

  static Future<void> requestNotificationPermission() async {
    if (supported) await _commands.invokeMethod<void>('notificationPermission');
  }

  static Stream<Position> positions() => _events
      .receiveBroadcastStream({'dutyEnd': _dutyEnd?.millisecondsSinceEpoch})
      .map(Position.fromMap);
}
