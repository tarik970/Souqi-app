// Derives launcher-icon variants from assets/branding/souqi_icon_foreground.png:
//  - souqi_icon_legacy.png: foreground composed on the cream brand background
//    (#FAF6EC), for pre-Android-8 launchers that take one flat image.
//  - souqi_icon_monochrome.png: white silhouette (alpha preserved), for the
//    Android 13+ themed icon, which the launcher tints itself.
//
// Run with: dart run tool/make_brand_icons.dart
import 'dart:io';

import 'package:image/image.dart' as img;

void main() {
  const dir = 'assets/branding';
  final foreground =
      img.decodePng(File('$dir/souqi_icon_foreground.png').readAsBytesSync())!;

  // Legacy icon: cream background + foreground.
  final legacy = img.Image(
    width: foreground.width,
    height: foreground.height,
    numChannels: 4,
  );
  img.fill(legacy, color: img.ColorRgba8(0xFA, 0xF6, 0xEC, 0xFF));
  img.compositeImage(legacy, foreground);
  File('$dir/souqi_icon_legacy.png').writeAsBytesSync(img.encodePng(legacy));

  // Monochrome: every pixel white, alpha kept.
  final mono = img.Image.from(foreground);
  for (final pixel in mono) {
    if (pixel.a > 0) {
      pixel
        ..r = 255
        ..g = 255
        ..b = 255;
    }
  }
  File('$dir/souqi_icon_monochrome.png').writeAsBytesSync(img.encodePng(mono));

  stdout.writeln('Wrote souqi_icon_legacy.png and souqi_icon_monochrome.png');
}
