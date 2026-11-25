import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/printing/print_job.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_output.dart';
import 'invoice_providers.dart';
import 'output_messages.dart';
import 'printer_widgets.dart';

/// What the printer picker returns: the device, and the command language
/// the user chose for it.
class PrinterChoice {
  const PrinterChoice(this.device, this.language);

  final PairedDevice device;
  final PrinterLanguage language;
}

/// Lists the Bluetooth devices already paired with the phone; picking one
/// asks for its language (Receipt / Label) right there, and both are
/// returned. Pairing itself happens in the system settings (a button opens
/// them) — the app never scans, so it needs no location access.
Future<PrinterChoice?> showPrinterPicker(BuildContext context) {
  return showDialog<PrinterChoice>(
    context: context,
    builder: (_) => const _PrinterPickerDialog(),
  );
}

/// Opens the picker and stores what was chosen: the printer becomes the
/// default one, and its language is remembered under its address.
Future<void> chooseAndRememberPrinter(
  BuildContext context,
  WidgetRef ref,
) async {
  // Read before the await: `ref` must not be used once the dialog is up.
  final settings = ref.read(invoiceSettingsProvider.notifier);
  final choice = await showPrinterPicker(context);
  if (choice == null) return;
  final device = choice.device;
  await settings.change(
    (s) => s
        .copyWith(
          printerAddress: () => device.address,
          printerName: () =>
              device.name.isEmpty ? device.address : device.name,
        )
        .withPrinterLanguage(choice.language),
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

  /// The device tapped in the list; the dialog then asks for its language.
  PairedDevice? _picked;
  PrinterLanguage _language = PrinterLanguage.escPos;

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
    if (state == AppLifecycleState.resumed && !_loading && _picked == null) {
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

  void _pick(PairedDevice device) {
    setState(() {
      _picked = device;
      // A printer chosen before comes back with the language it had.
      _language = ref
              .read(invoiceSettingsProvider)
              .value
              ?.languageOf(device.address) ??
          PrinterLanguage.escPos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final picked = _picked;
    return picked == null ? _buildList(context) : _buildLanguage(context, picked);
  }

  /// Step 2: the language of the printer that was just tapped.
  Widget _buildLanguage(BuildContext context, PairedDevice device) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(device.name.isEmpty ? device.address : device.name),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.printerLanguageLabel, style: theme.textTheme.titleSmall),
              PrinterLanguageSelector(
                value: _language,
                contentPadding: EdgeInsets.zero,
                onChanged: (language) => setState(() => _language = language),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.printerLanguageHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() => _picked = null),
          child: Text(MaterialLocalizations.of(context).backButtonTooltip),
        ),
        FilledButton(
          key: const ValueKey('printer-language-confirm'),
          onPressed: () =>
              Navigator.of(context).pop(PrinterChoice(device, _language)),
          child: Text(l10n.done),
        ),
      ],
    );
  }

  /// Step 1: the paired devices.
  Widget _buildList(BuildContext context) {
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
              onTap: () => _pick(device),
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
