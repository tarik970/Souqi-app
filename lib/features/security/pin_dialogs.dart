import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/security/pin_hash.dart';
import '../../data/repositories/pin_repository.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';

/// Whether a PIN is set — for the settings tile.
final pinIsSetProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinRepositoryProvider).isSet(),
);

/// The gate in front of every sensitive action: revealing a code, reprinting
/// an invoice that carries codes, voiding, exporting, the audit log.
///
/// Asks for the PIN and returns true only when it was entered correctly.
/// When no PIN has been chosen yet the user is asked to choose one first —
/// choosing it counts as entering it.
///
/// [reason] is one line saying why the PIN is being asked for.
Future<bool> requirePin(BuildContext context, {String? reason}) async {
  final pins =
      ProviderScope.containerOf(context, listen: false).read(pinRepositoryProvider);
  final isSet = await pins.isSet();
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => isSet
        ? PinEntryDialog(reason: reason)
        : SetPinDialog(firstUse: true, reason: reason),
  );
  return ok == true;
}

/// Makes sure a PIN exists before the first card code is loaded, so that
/// codes never sit in stock unprotected. Does not ask for an existing PIN.
Future<bool> ensurePinIsSet(BuildContext context, {String? reason}) async {
  final pins =
      ProviderScope.containerOf(context, listen: false).read(pinRepositoryProvider);
  if (await pins.isSet()) return true;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => SetPinDialog(firstUse: true, reason: reason),
  );
  return ok == true;
}

/// Digits only — Western, Arabic-Indic or Persian, whatever the keyboard
/// gives; [normalizePin] makes them the same PIN.
final _pinDigits = FilteringTextInputFormatter.allow(RegExp('[0-9٠-٩۰-۹]'));

/// "0:30", "12:05".
String formatLockTime(Duration left) {
  final seconds = left.inSeconds < 1 ? 1 : left.inSeconds;
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

class _PinField extends StatelessWidget {
  const _PinField({
    super.key,
    required this.controller,
    required this.label,
    this.errorText,
    this.autofocus = false,
    this.enabled = true,
    this.onSubmitted,
    this.textInputAction,
    this.focusNode,
  });

  final FocusNode? focusNode;
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final bool autofocus;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      keyboardType: TextInputType.number,
      textInputAction: textInputAction,
      textDirection: TextDirection.ltr,
      maxLength: pinMaxLength,
      inputFormatters: [_pinDigits],
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        errorMaxLines: 3,
        counterText: '',
      ),
    );
  }
}

/// Asks for the current PIN. Pops `true` when it is right; stays open on a
/// wrong one, saying how many attempts are left or how long the lock lasts.
class PinEntryDialog extends ConsumerStatefulWidget {
  const PinEntryDialog({super.key, this.reason});

  final String? reason;

  @override
  ConsumerState<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends ConsumerState<PinEntryDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    final l10n = AppLocalizations.of(context);
    final pin = _controller.text;
    if (!isValidPin(pin)) {
      setState(() => _error = l10n.pinInvalid);
      return;
    }
    final pins = ref.read(pinRepositoryProvider);
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await pins.verify(pin);
    if (!mounted) return;
    switch (result) {
      case PinCorrect():
        Navigator.of(context).pop(true);
      case PinWrong(:final attemptsLeft):
        _controller.clear();
        setState(() {
          _checking = false;
          _error = l10n.pinWrong(attemptsLeft);
        });
      case PinLocked(:final until):
        _controller.clear();
        setState(() {
          _checking = false;
          _error = l10n.pinLocked(
            formatLockTime(until.difference(DateTime.now())),
          );
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = widget.reason;
    return AlertDialog(
      key: const ValueKey('pin-entry-dialog'),
      scrollable: true,
      title: Text(l10n.pinEnterTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null && reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(reason),
            ),
          _PinField(
            key: const ValueKey('pin-entry-field'),
            controller: _controller,
            label: l10n.pinLabel,
            errorText: _error,
            autofocus: true,
            enabled: !_checking,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('pin-entry-ok'),
          onPressed: _checking ? null : _submit,
          child: Text(l10n.pinConfirmAction),
        ),
      ],
    );
  }
}

/// Chooses a PIN: typed twice, 4 to 6 digits. Saves it and pops `true`.
///
/// [firstUse]: opened because an action needs a PIN and there is none yet,
/// rather than from the settings.
class SetPinDialog extends ConsumerStatefulWidget {
  const SetPinDialog({
    super.key,
    this.firstUse = false,
    this.isChange = false,
    this.reason,
  });

  final bool firstUse;

  /// Replaces an existing PIN (the old one was already asked for).
  final bool isChange;
  final String? reason;

  @override
  ConsumerState<SetPinDialog> createState() => _SetPinDialogState();
}

class _SetPinDialogState extends ConsumerState<SetPinDialog> {
  final _pin = TextEditingController();
  final _again = TextEditingController();
  final _againFocus = FocusNode();
  String? _pinError;
  String? _againError;
  bool _saving = false;

  @override
  void dispose() {
    _pin.dispose();
    _again.dispose();
    _againFocus.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final pin = _pin.text;
    if (!isValidPin(pin)) {
      setState(() {
        _pinError = l10n.pinInvalid;
        _againError = null;
      });
      return;
    }
    if (normalizePin(_again.text) != normalizePin(pin)) {
      setState(() {
        _pinError = null;
        _againError = l10n.pinMismatch;
      });
      return;
    }
    // Finishes even if the dialog is dismissed while the hash is computed.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _pinError = null;
      _againError = null;
    });
    await container.read(pinRepositoryProvider).set(pin);
    await container.read(auditRepositoryProvider).log(
          widget.isChange ? AuditAction.pinChange : AuditAction.pinSet,
        );
    container.invalidate(pinIsSetProvider);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = widget.reason;
    return AlertDialog(
      key: const ValueKey('pin-set-dialog'),
      scrollable: true,
      title: Text(widget.isChange ? l10n.pinChangeTitle : l10n.pinSetTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (reason != null && reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(reason),
            ),
          Text(widget.firstUse ? l10n.pinNeededIntro : l10n.pinSetIntro),
          const SizedBox(height: 8),
          _PinField(
            key: const ValueKey('pin-new-field'),
            controller: _pin,
            label: l10n.pinNewLabel,
            errorText: _pinError,
            autofocus: true,
            enabled: !_saving,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _againFocus.requestFocus(),
          ),
          const SizedBox(height: 8),
          _PinField(
            key: const ValueKey('pin-again-field'),
            controller: _again,
            focusNode: _againFocus,
            label: l10n.pinConfirmLabel,
            errorText: _againError,
            enabled: !_saving,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pinForgetWarning,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('pin-set-save'),
          onPressed: _saving ? null : _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
