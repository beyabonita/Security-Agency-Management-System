import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_application_1/widgets/guard_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  test('agency marks and Android foreground preserve real transparency', () {
    for (final path in [
      'assets/branding/twenty_twenty_security_agency_shield.png',
      'assets/branding/sentinel_link_mark.png',
      'assets/branding/sentinel_link_app_icon.png',
      'web/icons/sentinel-link-mark.png',
      'web/favicon.png',
      'web/icons/Icon-192.png',
      'web/icons/Icon-512.png',
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png',
      'android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png',
    ]) {
      final image = img.decodePng(File(path).readAsBytesSync())!;
      expect(image.numChannels, 4, reason: path);
      for (final point in [
        (0, 0),
        (image.width - 1, 0),
        (0, image.height - 1),
        (image.width - 1, image.height - 1),
      ]) {
        expect(
          image.getPixel(point.$1, point.$2).a,
          0,
          reason: '$path transparent corner',
        );
      }
      expect(
        image.getPixel(image.width ~/ 2, image.height ~/ 2).a,
        greaterThan(0),
        reason: '$path contains the shield',
      );
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('Guard mark has no opaque frame in $brightness mode', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
            body: Center(child: SentinelBrandMark(size: 80)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      final containers = tester.widgetList<Container>(
        find.descendant(
          of: find.byType(SentinelBrandMark),
          matching: find.byType(Container),
        ),
      );
      for (final container in containers) {
        expect(container.color?.a ?? 0, 0);
        final decoration = container.decoration;
        if (decoration is BoxDecoration) {
          expect(decoration.color?.a ?? 0, 0);
          expect(decoration.boxShadow ?? [], isEmpty);
        }
      }
      expect(tester.takeException(), isNull);
    });
  }
}
