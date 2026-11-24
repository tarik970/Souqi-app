import 'dart:typed_data';
import 'dart:ui' as ui;

/// Widest logo worth keeping: it is printed at under half the paper width,
/// which is 288 dots on 80 mm paper and shared at 2×.
const int maxLogoWidth = 512;

/// Turns a picked image (any format the platform can decode) into the PNG
/// that is stored with the settings: downscaled to at most [maxWidth] pixels
/// wide. Throws if the bytes are not a decodable image.
Future<Uint8List> prepareLogo(Uint8List source, {int maxWidth = maxLogoWidth}) async {
  final probe = await ui.instantiateImageCodec(source);
  final ui.Image original;
  try {
    original = (await probe.getNextFrame()).image;
  } finally {
    probe.dispose();
  }

  var image = original;
  if (original.width > maxWidth) {
    final scaled = await ui.instantiateImageCodec(source, targetWidth: maxWidth);
    try {
      image = (await scaled.getNextFrame()).image;
    } finally {
      scaled.dispose();
    }
    original.dispose();
  }
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('could not encode the logo');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}
