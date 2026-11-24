import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_providers.dart';
import 'invoice_settings_screen.dart';

/// The one clear sentence shown for each way an output action can fail.
String outputFailureMessage(
  AppLocalizations l10n,
  OutputException error, {
  String? printerName,
}) {
  return switch (error.failure) {
    OutputFailure.noPrinterSelected => l10n.errorNoPrinter,
    OutputFailure.bluetoothUnsupported => l10n.errorBluetoothUnsupported,
    OutputFailure.bluetoothOff => l10n.errorBluetoothOff,
    OutputFailure.bluetoothPermissionDenied => l10n.errorBluetoothPermission,
    OutputFailure.printerUnreachable =>
      l10n.errorPrinterUnreachable(printerName ?? ''),
    OutputFailure.printerWriteFailed => l10n.errorPrinterWrite,
    OutputFailure.storagePermissionDenied => l10n.errorStoragePermission,
    OutputFailure.unknown => l10n.errorOutputUnknown(error.detail ?? ''),
  };
}

/// Shows [error] in a snack bar with the action that fixes it, when there is
/// one: Bluetooth off → the Bluetooth settings, permission denied → the app
/// settings, no printer → the invoice settings.
void showOutputError(
  BuildContext context,
  WidgetRef ref,
  OutputException error, {
  bool offerInvoiceSettings = true,
}) {
  final l10n = AppLocalizations.of(context);
  final bridge = ref.read(nativeBridgeProvider);
  final printerName = ref.read(invoiceSettingsProvider).value?.printerName;
  final navigator = Navigator.of(context);

  final action = switch (error.failure) {
    OutputFailure.bluetoothOff => SnackBarAction(
        label: l10n.openBluetoothSettings,
        onPressed: bridge.openBluetoothSettings,
      ),
    OutputFailure.bluetoothPermissionDenied ||
    OutputFailure.storagePermissionDenied =>
      SnackBarAction(
        label: l10n.openAppSettings,
        onPressed: bridge.openAppSettings,
      ),
    OutputFailure.noPrinterSelected when offerInvoiceSettings => SnackBarAction(
        label: l10n.choosePrinter,
        onPressed: () => navigator.push(
          MaterialPageRoute(builder: (_) => const InvoiceSettingsScreen()),
        ),
      ),
    _ => null,
  };

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          outputFailureMessage(l10n, error, printerName: printerName),
        ),
        duration: const Duration(seconds: 6),
        action: action,
      ),
    );
}
