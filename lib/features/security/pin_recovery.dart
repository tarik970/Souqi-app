import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../core/security/pin_hash.dart';
import '../../data/repositories/pin_repository.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_output.dart';
import '../invoice/invoice_providers.dart';
import '../invoice/output_messages.dart';
import '../license/license_providers.dart';
import 'pin_dialogs.dart';

/// What authorises replacing a forgotten PIN.
enum PinResetKind {
  /// The recovery code shown when the PIN was chosen.
  recoveryCode,

  /// A developer-signed, device-bound reset code (phase 5b).
  signedCode,
}

/// The code a forgotten PIN is being replaced with, on its way from the
/// "Forgot PIN?" dialog to the "new PIN" dialog. Deliberately without a
/// `toString`: it is a secret.
class PinReset {
  const PinReset.recovery(this.code) : kind = PinResetKind.recoveryCode;

  const PinReset.signed(this.code) : kind = PinResetKind.signedCode;

  final PinResetKind kind;
  final String code;
}

/// Shows the recovery code of a PIN that was just saved. Returns when the
/// user has ticked "I saved it" and continued.
///
/// Pushed on [navigator] itself, so it appears even if the dialog that
/// saved the PIN is gone by now: this is the only time the code exists.
Future<void> showRecoveryCode(NavigatorState navigator, String code) async {
  if (!navigator.mounted) return;
  await navigator.push(
    DialogRoute<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (_) => RecoveryCodeDialog(code: code),
    ),
  );
}

enum _RecoveryOutput { print, share, save }

/// The one-time recovery code of a new PIN: shown once, large, with Print,
/// Share and Save — and no way on but ticking "I saved it".
///
/// Neither a tap outside nor the back button closes it: closing it by a slip
/// of the thumb would lose the only copy of the way back in.
class RecoveryCodeDialog extends ConsumerStatefulWidget {
  const RecoveryCodeDialog({super.key, required this.code});

  /// The code without separators.
  final String code;

  @override
  ConsumerState<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends ConsumerState<RecoveryCodeDialog> {
  bool _saved = false;
  _RecoveryOutput? _running;

  /// What the last Print / Share / Save came to, said inside the dialog (a
  /// snack bar would sit dimmed behind it).
  String? _message;
  bool _messageIsError = false;

  static const _fileName = 'souqi-pin-recovery-code.txt';

  /// The text file: what the code is, the code, the date.
  String _fileText(AppLocalizations l10n, String locale) => [
        '${l10n.appTitle} — ${l10n.recoverySlipTitle}',
        formatRecoveryCode(widget.code),
        DateFormat.yMd(locale).format(DateTime.now()),
        l10n.recoverySlipHint,
        '',
      ].join('\n');

  Future<void> _run(_RecoveryOutput action) async {
    if (_running != null) return;
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final output = ref.read(invoiceOutputProvider);
    final printerName = ref.read(invoiceSettingsProvider).value?.printerName;
    setState(() {
      _running = action;
      _message = null;
    });
    String? message;
    var isError = false;
    try {
      switch (action) {
        case _RecoveryOutput.print:
          await output.printRecoveryCode(widget.code);
          message = l10n.printSent;
        case _RecoveryOutput.share:
          await output.shareTextFile(
            fileName: _fileName,
            text: _fileText(l10n, locale),
          );
        case _RecoveryOutput.save:
          message = l10n.savedToPhone(await output.saveTextFile(
            fileName: _fileName,
            text: _fileText(l10n, locale),
          ));
      }
    } on OutputException catch (e) {
      message = outputFailureMessage(l10n, e, printerName: printerName);
      isError = true;
    }
    if (!mounted) return;
    setState(() {
      _running = null;
      _message = message;
      _messageIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final code = formatRecoveryCode(widget.code);
    final busy = _running != null;

    Widget action(_RecoveryOutput value, IconData icon, String label) =>
        OutlinedButton.icon(
          key: ValueKey('recovery-${value.name}'),
          onPressed: busy ? null : () => _run(value),
          icon: _running == value
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 18),
          label: Text(label),
        );

    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('recovery-code-dialog'),
        scrollable: true,
        title: Text(l10n.recoveryCodeTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.recoveryCodeIntro),
            const SizedBox(height: 16),
            // Groups wrap between each other, never inside one; the code is
            // left-to-right in both app languages.
            Directionality(
              textDirection: TextDirection.ltr,
              child: Wrap(
                key: const ValueKey('recovery-code'),
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (final group in code.split('-'))
                    Text(
                      group,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                action(_RecoveryOutput.print, Icons.print_outlined,
                    l10n.recoveryPrint),
                action(_RecoveryOutput.share, Icons.share_outlined,
                    l10n.recoveryShare),
                action(_RecoveryOutput.save, Icons.download_outlined,
                    l10n.exportSave),
              ],
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _message!,
                  key: const ValueKey('recovery-message'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _messageIsError ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            CheckboxListTile(
              key: const ValueKey('recovery-saved'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.recoveryCodeSaved),
              value: _saved,
              onChanged: (value) => setState(() => _saved = value ?? false),
            ),
          ],
        ),
        actions: [
          FilledButton(
            key: const ValueKey('recovery-continue'),
            // Nothing to press until the box is ticked.
            onPressed: _saved ? () => Navigator.of(context).pop() : null,
            child: Text(l10n.pinConfirmAction),
          ),
        ],
      ),
    );
  }
}

/// "Forgot PIN?": asks for the recovery code, then for a new PIN, then shows
/// the NEW recovery code — the old one stops working when the new PIN is
/// saved. Pops `true` once the PIN has been replaced.
///
/// Wrong codes are counted like wrong PINs, with the same lock-out, on a
/// counter of their own.
///
/// THE DEVELOPER'S RESET CODE (`signedPinResetProvider`, licensing): for
/// the shop that lost the recovery code too. The dialog shows this phone's
/// REQUEST CODE to send to the developer, and takes the reset code that
/// comes back — pasted into the same field, or scanned as a QR code. Text
/// that is not shaped like a recovery code is checked as a reset code:
/// signed by the developer, for this phone, not older than 48 hours, and
/// never used before.
class PinRecoveryDialog extends ConsumerStatefulWidget {
  const PinRecoveryDialog({super.key});

  @override
  ConsumerState<PinRecoveryDialog> createState() => _PinRecoveryDialogState();
}

class _PinRecoveryDialogState extends ConsumerState<PinRecoveryDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _copyRequestCode(String requestCode) async {
    await Clipboard.setData(ClipboardData(text: requestCode));
  }

  /// The reset code as a QR code: read, put into the field and checked.
  Future<void> _scan() async {
    final scanned = await ref.read(licenseScannerProvider)(context);
    if (!mounted || scanned == null || scanned.trim().isEmpty) return;
    _controller.text = scanned.trim();
    await _submit();
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _checking = false;
      _error = message;
    });
  }

  Future<void> _submit() async {
    if (_checking) return;
    final l10n = AppLocalizations.of(context);
    final text = _controller.text.trim();
    final pins = ref.read(pinRepositoryProvider);
    final authority = ref.read(signedPinResetProvider);

    final PinReset reset;
    if (isRecoveryCodeShaped(text)) {
      setState(() {
        _checking = true;
        _error = null;
      });
      final check = await pins.checkRecovery(text);
      switch (check) {
        case PinCorrect():
          reset = PinReset.recovery(text);
        case PinWrong(:final attemptsLeft):
          return _fail(l10n.recoveryWrong(attemptsLeft));
        case PinLocked(:final until):
          return _fail(l10n.pinLocked(
            formatLockTime(until.difference(DateTime.now())),
          ));
      }
    } else if (authority != null && text.isNotEmpty) {
      setState(() {
        _checking = true;
        _error = null;
      });
      if (!await authority.verify(text)) return _fail(l10n.recoveryRefused);
      reset = PinReset.signed(text);
    } else {
      setState(() => _error = l10n.recoveryInvalid);
      return;
    }
    if (!mounted) return;
    setState(() => _checking = false);

    final done = await showDialog<bool>(
      context: context,
      builder: (_) => SetPinDialog(reset: reset),
    );
    if (done == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final signed = ref.watch(signedPinResetProvider) != null;
    final requestCode = signed ? ref.watch(requestCodeProvider) : null;
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('pin-recovery-dialog'),
      scrollable: true,
      title: Text(l10n.recoveryEnterTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(signed ? l10n.recoveryEnterIntroSigned : l10n.recoveryEnterIntro),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('recovery-field'),
            controller: _controller,
            autofocus: true,
            enabled: !_checking,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.characters,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.recoveryCodeTitle,
              hintText: 'XXXX-XXXX-XXXX',
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          if (requestCode != null) ...[
            const SizedBox(height: 16),
            Text(l10n.recoveryRequestIntro, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Directionality(
              textDirection: TextDirection.ltr,
              child: SelectableText(
                requestCode,
                key: const ValueKey('recovery-request-code'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  key: const ValueKey('recovery-request-copy'),
                  onPressed: () => _copyRequestCode(requestCode),
                  icon: const Icon(Icons.copy, size: 18),
                  label: Text(l10n.licenseCopy),
                ),
                TextButton.icon(
                  key: const ValueKey('recovery-scan'),
                  onPressed: _checking ? null : _scan,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: Text(l10n.licenseScan),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('recovery-ok'),
          onPressed: _checking ? null : _submit,
          child: Text(l10n.pinConfirmAction),
        ),
      ],
    );
  }
}
