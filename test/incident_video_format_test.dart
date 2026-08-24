import 'package:flutter_application_1/services/incident_video_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps supported camera video content types', () {
    expect(
      IncidentVideoFormat.contentTypeFor(reportedMimeType: 'video/webm'),
      'video/webm',
    );
    expect(
      IncidentVideoFormat.contentTypeFor(reportedMimeType: 'video/quicktime'),
      'video/quicktime',
    );
  });

  test('uses the captured file extension when MIME metadata is absent', () {
    expect(
      IncidentVideoFormat.contentTypeFor(fileName: 'capture.webm'),
      'video/webm',
    );
    expect(
      IncidentVideoFormat.contentTypeFor(fileName: 'capture.MOV'),
      'video/quicktime',
    );
  });

  test('normalizes mobile M4V and defaults unknown recordings to MP4', () {
    expect(
      IncidentVideoFormat.contentTypeFor(reportedMimeType: 'video/x-m4v'),
      'video/mp4',
    );
    expect(
      IncidentVideoFormat.contentTypeFor(
        reportedMimeType: 'application/octet-stream',
        fileName: 'capture.unknown',
      ),
      'video/mp4',
    );
    expect(IncidentVideoFormat.extensionFor('video/webm'), 'webm');
    expect(IncidentVideoFormat.extensionFor('video/quicktime'), 'mov');
  });
}
