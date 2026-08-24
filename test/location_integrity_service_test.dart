import 'package:flutter_application_1/services/location_integrity_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 22, 9, 0);

  String? validate({
    double latitude = 14.5995,
    double longitude = 120.9842,
    double accuracyMeters = 12,
    DateTime? capturedAt,
    bool isMocked = false,
  }) => LocationIntegrityService.validationError(
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    capturedAt: capturedAt ?? now,
    isMocked: isMocked,
    now: now,
  );

  test('accepts a fresh, accurate, non-mocked location fix', () {
    expect(validate(), isNull);
  });

  test('rejects mock locations', () {
    expect(validate(isMocked: true), contains('Mock or simulated'));
  });

  test('allows a positive GPS accuracy and rejects missing accuracy', () {
    expect(validate(accuracyMeters: 251), isNull);
    expect(validate(accuracyMeters: 0), contains('usable GPS accuracy'));
  });

  test('rejects stale and invalid coordinate fixes', () {
    expect(
      validate(capturedAt: now.subtract(const Duration(seconds: 46))),
      contains('too old'),
    );
    expect(validate(latitude: 91), contains('invalid location coordinates'));
  });
}
