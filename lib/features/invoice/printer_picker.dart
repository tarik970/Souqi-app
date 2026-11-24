import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_output.dart';
import 'invoice_providers.dart';
import 'output_messages.dart';

/// Lists the Bluetooth devices already paired with the phone and returns the
/// one the user picks. Pairing itself happens in the system settings (a
/// button opens them) — the app never scans, so it needs no location access.
Future<PairedDevice?> showPrinterPicker(BuildContext context) {
  return showDialog<PairedDevice>(
    context: context,
    builder: (_) => const _PrinterPickerDialog(),
  );
}

class _PrinterPickerDialog extends ConsumerStatefulWidget {
  const _PrinterPickerDialog();

  @override
  ConsumerState<_PrinterPickerDialog> createState() =>
      _PrinterPickerDialogState();
}

class _PrinterPickerDialogState extends ConsumerState<_PrinterPickerDialog>
    with WidgetsBindingObserver {
  List<PairedDevice>? _devices;
  OutputException? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from the Bluetooth or app settings: look again. This must
  /// not ask for the permission itself — closing the system permission
  /// dialog also resumes the app, and a denied request would re-open it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_loading) {
      _load(askPermission: false);
    }
  }

  Future<void> _load({bool askPermission = true}) async {
    _loading = true;
    setState(() {
      _devices = null;
      _error = null;
    });
    // Read before the first await: the dialog can be closed while the system
    // permission prompt is up, and `ref` must not be used after that.
    final output = ref.read(invoiceOutputProvider);
    final bridge = ref.read(nativeBridgeProvider);
    try {
      await output.ensureBluetoothReady(askPermission: askPermission);
      final devices = await bridge.pairedDevices();
      if (!mounted) return;
      setState(() => _devices = devices);
    } on OutputException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bridge = ref.read(nativeBridgeProvider);
    final selected = ref.watch(invoiceSettingsProvider).value?.printerAddress;
    final devices = _devices;
    final error = _error;

    final Widget content;
    if (error != null) {
      content = Text(outputFailureMessage(l10n, error));
    } else if (devices == null) {
      content = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (devices.isEmpty) {
      content = Text(l10n.noPairedDevices);
    } else {
      content = SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: devices.length,
          itemBuilder: (context, index) {
            final device = devices[index];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                device.looksLikePrinter ? Icons.print : Icons.bluetooth,
              ),
              title: Text(device.name.isEmpty ? device.address : device.name),
              subtitle: Text(
                device.address,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall,
              ),
              trailing: device.address == selected
                  ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                  : null,
              onTap: () => Navigator.of(context).pop(device),
            );
          },
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.pairedDevicesTitle),
      content: content,
      actions: [
        if (error?.failure == OutputFailure.bluetoothPermissionDenied)
          TextButton(
            onPressed: bridge.openAppSettings,
            child: Text(l10n.openAppSettings),
          )
        else if (error?.failure != OutputFailure.bluetoothUnsupported)
          TextButton(
            onPressed: bridge.openBluetoothSettings,
            child: Text(l10n.openBluetoothSettings),
          ),
        TextButton(onPressed: _load, child: Text(l10n.refresh)),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
