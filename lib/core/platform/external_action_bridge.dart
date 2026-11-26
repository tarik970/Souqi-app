import 'dart:typed_data';

import 'native_bridge.dart';

/// The doorway to Android, with one thing added: it SAYS SO — before the
/// call — every time the app is about to put another app or a system screen
/// in front of itself (the share sheet, WhatsApp, the dialer, the file
/// picker, a settings page).
///
/// The PIN locks need to know: an app that went to the background behind
/// its own share sheet is not a phone someone walked away with (see
/// `PinBackgroundGuard`). Saying it HERE, in the one doorway, means no
/// screen can forget to.
///
/// Everything else passes straight through — including saving to Downloads
/// (written through MediaStore, no screen opens) and the Bluetooth
/// permission prompt (a dialog over the app, which never locked anything).
///
/// A NEW bridge method that opens another app goes through [_external].
class ExternalActionBridge implements NativeBridge {
  const ExternalActionBridge(
    this._inner, {
    required this.onStarting,
    required this.onNotStarted,
  });

  final NativeBridge _inner;

  /// Called just before the platform is asked to open something.
  final void Function() onStarting;

  /// Called when the platform answers that nothing was opened.
  final void Function() onNotStarted;

  /// [opened] reads the answer of a call that reports whether the other
  /// app really came up.
  Future<T> _external<T>(
    Future<T> Function() call, {
    bool Function(T answer)? opened,
  }) async {
    onStarting();
    final T answer;
    try {
      answer = await call();
    } catch (_) {
      onNotStarted();
      rethrow;
    }
    if (opened != null && !opened(answer)) onNotStarted();
    return answer;
  }

  @override
  Future<void> openBluetoothSettings() =>
      _external(_inner.openBluetoothSettings);

  @override
  Future<void> openAppSettings() => _external(_inner.openAppSettings);

  @override
  Future<bool> sendToWhatsApp({
    required String package,
    required String internationalPhone,
    required String filePath,
    required String mimeType,
    String? text,
  }) =>
      _external(
        () => _inner.sendToWhatsApp(
          package: package,
          internationalPhone: internationalPhone,
          filePath: filePath,
          mimeType: mimeType,
          text: text,
        ),
        opened: (answer) => answer,
      );

  @override
  Future<bool> openWhatsAppChat({
    required String package,
    required String internationalPhone,
    String? text,
  }) =>
      _external(
        () => _inner.openWhatsAppChat(
          package: package,
          internationalPhone: internationalPhone,
          text: text,
        ),
        opened: (answer) => answer,
      );

  @override
  Future<bool> dial(String phone) =>
      _external(() => _inner.dial(phone), opened: (answer) => answer);

  @override
  Future<void> shareFile({
    required String filePath,
    required String mimeType,
    String? text,
  }) =>
      _external(
        () => _inner.shareFile(
          filePath: filePath,
          mimeType: mimeType,
          text: text,
        ),
      );

  @override
  Future<PickedTextFile?> pickTextFile() => _external(_inner.pickTextFile);

  /// The file picker of a restore.
  @override
  Future<PickedFile?> pickFile() => _external(_inner.pickFile);

  // The daily debt report: the folder picker, the share sheet with both
  // files, a file manager on the folder, the battery-optimization dialog.

  @override
  Future<PickedFolder?> pickFolder() => _external(_inner.pickFolder);

  @override
  Future<void> shareFiles(List<ShareableFile> files, {String? text}) =>
      _external(() => _inner.shareFiles(files, text: text));

  @override
  Future<bool> openFolder(String? treeUri) => _external(
        () => _inner.openFolder(treeUri),
        opened: (answer) => answer,
      );

  @override
  Future<bool> requestBatteryExemption() => _external(
        _inner.requestBatteryExemption,
        opened: (answer) => answer,
      );

  // ---- Straight through: nothing leaves the app. ----

  @override
  Future<BluetoothStatus> bluetoothStatus() => _inner.bluetoothStatus();

  @override
  Future<bool> requestBluetoothPermission() =>
      _inner.requestBluetoothPermission();

  @override
  Future<List<PairedDevice>> pairedDevices() => _inner.pairedDevices();

  @override
  Future<void> printBytes(
    String address,
    Uint8List bytes, {
    int chunkSize = defaultPrintChunkSize,
    int chunkDelayMs = defaultPrintChunkDelayMs,
  }) =>
      _inner.printBytes(
        address,
        bytes,
        chunkSize: chunkSize,
        chunkDelayMs: chunkDelayMs,
      );

  @override
  Future<void> disconnectPrinter() => _inner.disconnectPrinter();

  @override
  Future<List<String>> whatsAppPackages() => _inner.whatsAppPackages();

  @override
  Future<String> saveToDownloads({
    required String filePath,
    required String fileName,
    required String mimeType,
    String? subfolder,
  }) =>
      _inner.saveToDownloads(
        filePath: filePath,
        fileName: fileName,
        mimeType: mimeType,
        subfolder: subfolder,
      );

  @override
  Future<void> beep() => _inner.beep();

  /// A permission dialog over the app, like the Bluetooth one: nothing
  /// leaves the app.
  @override
  Future<bool> requestNotificationPermission() =>
      _inner.requestNotificationPermission();

  @override
  Future<bool> requestLegacyStoragePermission() =>
      _inner.requestLegacyStoragePermission();
}
