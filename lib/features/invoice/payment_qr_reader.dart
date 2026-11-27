import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/printing/qr_bitmap.dart';
import '../../core/printing/raster.dart';
import '../security/pin_session.dart';
import 'invoice_providers.dart';

/// Where the owner takes the picture of their payment QR from.
enum QrImageSource { gallery, file, camera }

/// A picture chosen for the payment QR: where it sits on the phone (the
/// code reader reads the file) and its bytes.
class PickedQrImage {
  const PickedQrImage({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

typedef QrImagePicker = Future<PickedQrImage?> Function(QrImageSource source);

/// Opens the photo picker, the file picker or the camera. Null when the
/// owner backs out. Tests replace it.
///
/// The photo picker and the camera are other apps in front of this one and
/// do not go through the native bridge: the PIN locks are told here, by
/// hand, like the logo picker. The file picker IS the bridge's, which
/// announces it itself.
final qrImagePickerProvider = Provider<QrImagePicker>((ref) {
  return (source) async {
    if (source == QrImageSource.file) {
      final picked = await ref.read(nativeBridgeProvider).pickFile();
      if (picked == null) return null;
      final file = File(picked.path);
      return PickedQrImage(path: picked.path, bytes: await file.readAsBytes());
    }
    final guard = ref.read(pinBackgroundGuardProvider)..externalActionStarting();
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source == QrImageSource.camera
            ? ImageSource.camera
            : ImageSource.gallery,
      );
    } catch (_) {
      // Nothing was opened (no camera, no picker on this phone).
      guard.externalActionFailed();
      rethrow;
    }
    if (picked == null) return null;
    return PickedQrImage(path: picked.path, bytes: await picked.readAsBytes());
  };
});

typedef QrImageDecoder = Future<String?> Function(String path);

/// Reads the QR code in the picture at a path: ML Kit's own still-image
/// reader through mobile_scanner (the BUNDLED model — offline, no Google
/// Play services). Null when there is no readable code. Tests replace it.
final qrImageDecoderProvider = Provider<QrImageDecoder>(
  (ref) => (path) async {
    try {
      final capture = await MobileScannerPlatform.instance.analyzeImage(
        path,
        formats: const [BarcodeFormat.qrCode],
      );
      for (final barcode in capture?.barcodes ?? const <Barcode>[]) {
        final text = barcode.rawValue;
        if (text != null && text.trim().isNotEmpty) return text;
      }
      return null;
    } on Exception {
      return null;
    } on UnsupportedError {
      return null;
    }
  },
);

/// The longest side a picture is decoded at for "use the image as is": a
/// 12-megapixel photo is not needed to keep a 400-pixel square.
const int _maxDecodeSide = 1200;

/// The picture [bytes] as raw pixels (any format the phone decodes),
/// shrunk to at most [_maxDecodeSide]. Throws [FormatException] when the
/// bytes are not an image.
Future<RgbaImage> decodePicture(Uint8List bytes) async {
  final ui.ImmutableBuffer buffer;
  final ui.ImageDescriptor descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
  } catch (_) {
    throw const FormatException('not an image');
  }
  try {
    final width = descriptor.width;
    final height = descriptor.height;
    final longest = width > height ? width : height;
    final codec = longest <= _maxDecodeSide
        ? await descriptor.instantiateCodec()
        : width >= height
            ? await descriptor.instantiateCodec(targetWidth: _maxDecodeSide)
            : await descriptor.instantiateCodec(targetHeight: _maxDecodeSide);
    try {
      final image = (await codec.getNextFrame()).image;
      try {
        final data = await image.toByteData();
        if (data == null) throw const FormatException('not an image');
        return RgbaImage(
          width: image.width,
          height: image.height,
          rgba: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } finally {
    descriptor.dispose();
    buffer.dispose();
  }
}

/// "Use the image as is", from the picked bytes: cropped, black and white,
/// nearest neighbour ([qrBitmapFromImage]). Null when the picture has no
/// contrast to keep; throws [FormatException] when it is not an image.
Future<QrBitmap?> qrBitmapFromPicture(Uint8List bytes) async =>
    qrBitmapFromImage(await decodePicture(bytes));
