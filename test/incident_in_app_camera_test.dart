import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/incident_in_app_camera.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers a photo fallback when no camera is detected', (
    tester,
  ) async {
    Uint8List? captured;
    final expected = Uint8List.fromList([1, 2, 3, 4]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncidentInAppCamera(
            height: 420,
            onPhotoCaptured: (bytes) => captured = bytes,
            availableCamerasLoader: () async => <CameraDescription>[],
            fallbackPhotoLoader: () async => expected,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera unavailable'), findsOneWidget);
    expect(find.text('Capture or choose photo'), findsOneWidget);
    expect(
      find.text('Capture a photo, or retry the camera to record a video.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Capture or choose photo'));
    await tester.pumpAndSettle();

    expect(captured, same(expected));
  });

  testWidgets('translates a browser camera error into useful guidance', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IncidentInAppCamera(
            height: 420,
            onPhotoCaptured: (_) {},
            availableCamerasLoader: () async => throw CameraException(
              'cameraNotFound',
              'No camera found for the given camera options.',
            ),
            fallbackPhotoLoader: () async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No camera was detected. Connect a camera or use the photo option below.',
      ),
      findsOneWidget,
    );
    expect(
      find.text('No camera found for the given camera options.'),
      findsNothing,
    );
  });
}
