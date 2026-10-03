import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/services/android_location_bridge.dart';
import 'package:flutter_application_1/services/device_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const command = MethodChannel('sentinel/duty_location');
  const events = MethodChannel('sentinel/duty_location/positions');
  final commands = <MethodCall>[];
  final streamCalls = <MethodCall>[];
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    commands.clear();
    streamCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(command, (call) async {
          commands.add(call);
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, (call) async {
          streamCalls.add(call);
          return null;
        });
  });
  tearDown(() async {
    await AndroidLocationBridge.setDutyEnd(null);
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(command, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(events, null);
  });
  test(
    'attendance upgrades to duty and survives attendance disposal without restarting Android',
    () async {
      final service = DeviceLocationService(
        requestTimeout: const Duration(milliseconds: 20),
      );
      final attendance = service.foregroundPositions().listen((_) {});
      await flush();
      await flush();
      final end = DateTime.now().add(const Duration(hours: 1));
      await AndroidLocationBridge.setDutyEnd(end);
      final duty = service.positions().listen((_) {});
      await flush();
      await attendance.cancel();
      await flush();
      expect(streamCalls.where((call) => call.method == 'listen').length, 1);
      expect(streamCalls.where((call) => call.method == 'cancel'), isEmpty);
      expect(commands.last.arguments['dutyEnd'], end.millisecondsSinceEpoch);
      await expectLater(
        service.currentPosition(),
        throwsA(isA<TimeoutException>()),
      );
      expect(streamCalls.where((call) => call.method == 'cancel'), isEmpty);
      await AndroidLocationBridge.setDutyEnd(null);
      await duty.cancel();
      await flush();
      await flush();
      expect(streamCalls.where((call) => call.method == 'cancel').length, 1);
    },
  );
}
