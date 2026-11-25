/// The app's one doorway to Android: Bluetooth printing, the direct WhatsApp
/// intent, saving to Downloads and the share sheet.
///
/// Everything goes through the [NativeBridge] interface so screens and
/// services can be tested with a fake. The Android half lives in
/// android/app/src/main/kotlin/com/souqi/souqi/ (MainActivity.kt and
/// PrinterConnection.kt).
library;

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

/// Why an output action could not be completed. Each value has one clear,
/// localized message (see `output_messages.dart`).
enum OutputFailure {
  noPrinterSelected,
  bluetoothUnsupported,
  bluetoothOff,
  bluetoothPermissionDenied,
  printerUnreachable,
  printerWriteFailed,
  storagePermissionDenied,
  unknown,
}

class OutputException implements Exception {
  const OutputException(this.failure, [this.detail]);

  final OutputFailure failure;

  /// Technical detail from the platform, for the "unknown" message only.
  final String? detail;

  @override
  String toString() => 'OutputException(${failure.name}, $detail)';
}

class BluetoothStatus {
  const BluetoothStatus({
    required this.supported,
    required this.enabled,
    required this.permissionGranted,
  });

  /// False on a device with no Bluetooth radio.
  final bool supported;
  final bool enabled;

  /// Android 12+: BLUETOOTH_CONNECT / BLUETOOTH_SCAN ("Nearby devices").
  /// Always true on older versions, where the permission is install-time.
  final bool permissionGranted;
}

class PairedDevice {
  const PairedDevice({
    required this.name,
    required this.address,
    this.looksLikePrinter = false,
  });

  final String name;
  final String address;

  /// The device advertises the "imaging" Bluetooth class. Many printers do,
  /// many cheap ones do not — a sorting hint, never a filter.
  final bool looksLikePrinter;
}

/// A text file the user picked, already read.
class PickedTextFile {
  const PickedTextFile({required this.name, required this.content});

  final String name;
  final String content;
}

const whatsAppPackage = 'com.whatsapp';
const whatsAppBusinessPackage = 'com.whatsapp.w4b';

abstract class NativeBridge {
  Future<BluetoothStatus> bluetoothStatus();

  /// Asks for the Bluetooth runtime permission (Android 12+). Returns whether
  /// it is granted afterwards.
  Future<bool> requestBluetoothPermission();

  /// Devices already paired in the phone's Bluetooth settings.
  Future<List<PairedDevice>> pairedDevices();

  /// Connects to [address] (reusing an open connection) and writes [bytes]
  /// in [chunkSize]-byte pieces with [chunkDelayMs] between them. Throws
  /// [OutputException].
  Future<void> printBytes(
    String address,
    Uint8List bytes, {
    int chunkSize,
    int chunkDelayMs,
  });

  Future<void> disconnectPrinter();

  Future<void> openBluetoothSettings();

  Future<void> openAppSettings();

  /// Which of WhatsApp / WhatsApp Business are installed (package names).
  Future<List<String>> whatsAppPackages();

  /// Opens [package] directly on the chat of [internationalPhone] with the
  /// file attached. Returns false when the device cannot do that, so the
  /// caller can fall back to the share sheet.
  Future<bool> sendToWhatsApp({
    required String package,
    required String internationalPhone,
    required String filePath,
    required String mimeType,
    String? text,
  });

  /// Opens [package] on the chat of [internationalPhone] with [text] already
  /// typed into the message box, ready to edit and send — nothing is sent by
  /// the app itself. Returns false when the device cannot open the chat.
  Future<bool> openWhatsAppChat({
    required String package,
    required String internationalPhone,
    String? text,
  });

  /// Opens the phone's dialer on [phone] (the number as the shop typed it).
  /// The seller presses Call there; the app needs no call permission.
  /// Returns false when the device has no dialer.
  Future<bool> dial(String phone);

  /// Copies the file into Downloads/Souqi through MediaStore and returns the
  /// path to show the user. Throws [OutputException].
  Future<String> saveToDownloads({
    required String filePath,
    required String fileName,
    required String mimeType,
  });

  /// The system share sheet.
  Future<void> shareFile({
    required String filePath,
    required String mimeType,
    String? text,
  });

  /// Opens the system file picker and returns the chosen file read as text
  /// (a .txt or .csv list of card codes), or null when the user backs out.
  /// Throws [OutputException] when the file cannot be read or is not text.
  Future<PickedTextFile?> pickTextFile();

  /// A short beep confirming a scanned card. Never throws.
  Future<void> beep();
}

class MethodChannelNativeBridge implements NativeBridge {
  const MethodChannelNativeBridge();

  static const _channel = MethodChannel('souqi/native');

  static const _failures = {
    'BT_UNSUPPORTED': OutputFailure.bluetoothUnsupported,
    'BT_OFF': OutputFailure.bluetoothOff,
    'BT_PERMISSION': OutputFailure.bluetoothPermissionDenied,
    'BT_UNREACHABLE': OutputFailure.printerUnreachable,
    'BT_WRITE': OutputFailure.printerWriteFailed,
    'STORAGE_PERMISSION': OutputFailure.storagePermissionDenied,
  };

  Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      throw OutputException(
        _failures[e.code] ?? OutputFailure.unknown,
        e.message ?? e.code,
      );
    } on MissingPluginException catch (e) {
      throw OutputException(OutputFailure.unknown, e.message);
    }
  }

  @override
  Future<BluetoothStatus> bluetoothStatus() async {
    final map = await _invoke<Map<Object?, Object?>>('btStatus') ?? const {};
    return BluetoothStatus(
      supported: map['supported'] == true,
      enabled: map['enabled'] == true,
      permissionGranted: map['permission'] == true,
    );
  }

  @override
  Future<bool> requestBluetoothPermission() async =>
      await _invoke<bool>('btRequestPermission') ?? false;

  @override
  Future<List<PairedDevice>> pairedDevices() async {
    final list = await _invoke<List<Object?>>('btPairedDevices') ?? const [];
    final devices = [
      for (final entry in list.whereType<Map<Object?, Object?>>())
        PairedDevice(
          name: (entry['name'] as String?) ?? '',
          address: (entry['address'] as String?) ?? '',
          looksLikePrinter: entry['imaging'] == true,
        ),
    ]..removeWhere((d) => d.address.isEmpty);
    // Stable sort: likely printers first, system order otherwise.
    return [
      ...devices.where((d) => d.looksLikePrinter),
      ...devices.where((d) => !d.looksLikePrinter),
    ];
  }

  @override
  Future<void> printBytes(
    String address,
    Uint8List bytes, {
    int chunkSize = 1024,
    int chunkDelayMs = 12,
  }) =>
      _invoke<void>('btPrint', {
        'address': address,
        'bytes': bytes,
        'chunkSize': chunkSize,
        'chunkDelayMs': chunkDelayMs,
      });

  @override
  Future<void> disconnectPrinter() => _invoke<void>('btDisconnect');

  @override
  Future<void> openBluetoothSettings() => _invoke<void>('openBluetoothSettings');

  @override
  Future<void> openAppSettings() => _invoke<void>('openAppSettings');

  @override
  Future<List<String>> whatsAppPackages() async {
    final list = await _invoke<List<Object?>>('whatsAppPackages') ?? const [];
    return list.whereType<String>().toList();
  }

  @override
  Future<bool> sendToWhatsApp({
    required String package,
    required String internationalPhone,
    required String filePath,
    required String mimeType,
    String? text,
  }) async =>
      await _invoke<bool>('sendToWhatsApp', {
        'package': package,
        'phone': internationalPhone,
        'path': filePath,
        'mimeType': mimeType,
        'text': text,
      }) ??
      false;

  @override
  Future<bool> openWhatsAppChat({
    required String package,
    required String internationalPhone,
    String? text,
  }) async =>
      await _invoke<bool>('openWhatsAppChat', {
        'package': package,
        'phone': internationalPhone,
        'text': text,
      }) ??
      false;

  @override
  Future<bool> dial(String phone) async =>
      await _invoke<bool>('dial', {'phone': phone}) ?? false;

  @override
  Future<String> saveToDownloads({
    required String filePath,
    required String fileName,
    required String mimeType,
  }) async =>
      await _invoke<String>('saveToDownloads', {
        'path': filePath,
        'fileName': fileName,
        'mimeType': mimeType,
      }) ??
      fileName;

  @override
  Future<PickedTextFile?> pickTextFile() async {
    final map = await _invoke<Map<Object?, Object?>>('pickTextFile');
    if (map == null) return null;
    return PickedTextFile(
      name: (map['name'] as String?) ?? '',
      content: (map['content'] as String?) ?? '',
    );
  }

  @override
  Future<void> beep() async {
    try {
      await _invoke<void>('beep');
    } on OutputException {
      // Feedback only: a phone that cannot beep still scans.
    }
  }

  @override
  Future<void> shareFile({
    required String filePath,
    required String mimeType,
    String? text,
  }) async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(filePath, mimeType: mimeType)],
        text: text == null || text.isEmpty ? null : text,
      ),
    );
  }
}
