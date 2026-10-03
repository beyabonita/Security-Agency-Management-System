// Asset integration only: preserve the supplied artwork and alpha channel.
// Run: dart run scripts/update_agency_branding.dart "path/to/LOGO.png"
// Then: dart run flutter_launcher_icons
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError('Supply the path to the transparent agency PNG.');
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final bytes = File(arguments.single).readAsBytesSync();
  final image = img.decodePng(bytes);
  if (image == null || image.width != image.height) {
    throw ArgumentError('The agency master must be a square PNG.');
  }
  if (image.numChannels != 4 || image.getPixel(0, 0).a != 0) {
    throw ArgumentError('Use the transparent PNG, not a flattened copy.');
  }
  File(
    '${root.path}/assets/branding/twenty_twenty_security_agency_shield.png',
  ).writeAsBytesSync(bytes);
  for (final entry in {
    'assets/branding/sentinel_link_mark.png': 1024,
    'assets/branding/sentinel_link_app_icon.png': 1024,
    'assets/branding/sentinel_link_logo.png': 1024,
    'web/icons/sentinel-link-mark.png': 512,
  }.entries) {
    final resized = img.copyResize(
      image,
      width: entry.value,
      height: entry.value,
      interpolation: img.Interpolation.average,
    );
    File('${root.path}/${entry.key}').writeAsBytesSync(img.encodePng(resized));
    stdout.writeln('Updated ${entry.key} (${entry.value}px, transparent).');
  }
}
