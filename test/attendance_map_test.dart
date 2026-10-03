import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/attendance.dart';

void main() {
  test('attendance map uses a public tile source without an API key', () {
    expect(attendanceMapTileUrlTemplate, contains('openstreetmap.org'));
    expect(attendanceMapTileUrlTemplate.toLowerCase(), isNot(contains('key')));
    expect(attendanceMapTileUrlTemplate, isNot(contains('stadiamaps')));
  });
}
