import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/printing/print_job.dart';
import '../../core/printing/printer_detect.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_output.dart';
import 'invoice_providers.dart';
import 'output_messages.dart';
import 'printer_widgets.dart';

/// What the printer picker returns: the device, and what is known about the
/// language it speaks.
class PrinterChoice {
  const PrinterChoice(this.device, this.language, {this.detection});

  final PairedDevice device;

  /// The language to print in. Null = NOT DECIDED: the printer could not be
  /// asked while the picker was open and nothing was chosen by hand — it is
  /// asked on the first print instead (`InvoiceOutput.resolvePrinter`).
  final PrinterLanguage? language;

  /// Set when [language] is what the app found out by itself and the user
  /// left as it was: a printer known by name then gets its whole profile.
  final PrinterDetection? detection;
}

/// Lists the Bluetooth devices already paired with the phone. Picking one
/// FINDS OUT its language (Receipt / Label) right there — by its name, or by
/// asking the printer — and shows it, still open to a choice by hand; both
/// are returned. Pairing itself happens in the system settings (a button
/// opens them) — the app never scans, so it needs no location access.
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
  await settings.change((s) {
    final chosen = s.copyWith(
      printerAddress: () => device.address,
      printerName: () => device.name.isEmpty ? device.address : device.name,
    );
    final detection = choice.detection;
    if (detection != null) return chosen.withDetection(detection);
    final language = choice.language;
    return language == null ? chosen : chosen.withPrinterLanguage(language);
  });
}

/// One line saying how the language of a printer was found out.
String printerDetectionText(AppLocalizations l10n, PrinterDetection detection) =>
    switch (detection.source) {
      DetectionSource.profile =>
        l10n.printerDetectedProfile(detection.profile?.id ?? ''),
      DetectionSource.answered => l10n.printerDetectedAnswered(
          printerLanguageName(l10n, detection.language),
        ),
      DetectionSource.silent => l10n.printerDetectedSilent,
    };

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

  /// The device tapped in the list; the dialog then shows its language.
  PairedDevice? _picked;
  PrinterLanguage _language = PrinterLanguage.escPos;

  /// The language on screen was chosen by hand (or remembered from before):
  /// what the printer says no longer changes it.
  bool _byHand = false;

  /// The printer is being asked.
  bool _detecting = false;

  /// What the printer (or its name) said.
  PrinterDetection? _detection;

  /// The printer could not be reached to be asked.
  bool _unreachable = false;

  /// Counts the questions, so that the answer to an abandoned one (Back,
  /// another device) is dropped.
  int _question = 0;

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
    final settings = ref.read(invoiceSettingsProvider).value;
    // A printer chosen before comes back with the language it had, and is
    // not asked again.
    final known = settings?.knowsPrinter(device.address) ?? false;
    setState(() {
      _picked = device;
      _language =
          settings?.languageOf(device.address) ?? PrinterLanguage.escPos;
      _byHand = known;
      _detection = null;
      _unreachable = false;
    });
    if (!known) _detect(device);
  }

  /// Finds out the language of [device] while its step is on screen. The
  /// dialog stays usable meanwhile: Done before the answer leaves the
  /// question for the first print.
  Future<void> _detect(PairedDevice device) async {
    final question = ++_question;
    // `ref` is only read before the await.
    final output = ref.read(invoiceOutputProvider);
    setState(() => _detecting = true);
    PrinterDetection? found;
    try {
      found = await output.detectPrinter(
        address: device.address,
        name: device.name,
      );
    } catch (_) {
      // Switched off, out of range, Bluetooth gone: asked at the first print.
      found = null;
    }
    if (!mounted || question != _question) return;
    setState(() {
      _detecting = false;
      _detection = found;
      _unreachable = found == null;
      if (found != null && !_byHand) _language = found.language;
    });
  }

  void _backToList() {
    _question++;
    setState(() {
      _picked = null;
      _detecting = false;
    });
  }

  void _confirm(PairedDevice device) {
    final detection = _detection;
    final PrinterChoice choice;
    if (_byHand) {
      choice = PrinterChoice(device, _language);
    } else if (detection != null) {
      choice = PrinterChoice(device, detection.language, detection: detection);
    } else {
      // Not answered (yet) and nothing chosen: decided at the first print.
      choice = PrinterChoice(device, null);
    }
    _question++;
    Navigator.of(context).pop(choice);
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
    final detection = _detection;
    final String? status = _detecting
        ? l10n.printerDetecting
        : detection != null
            ? printerDetectionText(l10n, detection)
            : _unreachable
                ? l10n.printerDetectUnreachable
                : null;
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
                onChanged: (language) => setState(() {
                  _language = language;
                  _byHand = true;
                }),
              ),
              if (status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Row(
                    key: const ValueKey('printer-detect-status'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_detecting)
                        const Padding(
                          padding: EdgeInsetsDirectional.only(end: 8, top: 2),
                          child: SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      Expanded(
                        child: Text(status, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
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
          onPressed: _backToList,
          child: Text(MaterialLocalizations.of(context).backButtonTooltip),
        ),
        FilledButton(
          key: const ValueKey('printer-language-confirm'),
          onPressed: () => _confirm(device),
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
