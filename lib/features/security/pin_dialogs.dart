import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/security/pin_hash.dart';
import '../../data/repositories/pin_repository.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import 'pin_recovery.dart';

/// Whether a PIN is set — for the settings tile.
final pinIsSetProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinRepositoryProvider).isSet(),
);

/// A PIN is set but has no recovery code (it was chosen before recovery
/// codes existed) — for the banner in the settings.
final pinLacksRecoveryProvider = FutureProvider<bool>(
  (ref) => ref.watch(pinRepositoryProvider).lacksRecoveryCode(),
);

/// Call after the PIN or its recovery code was set, changed or removed.
void refreshPinState(ProviderContainer container) {
  container
    ..invalidate(pinIsSetProvider)
    ..invalidate(pinLacksRecoveryProvider);
}

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

/// The PIN when one is set; with none, nothing is asked (and none is forced
/// on the shop) — for actions that must not be done by just anyone holding
/// an unlocked phone, but are not card codes: bulk price changes, backups.
Future<bool> requirePinIfSet(BuildContext context, {String? reason}) async {
  final pins =
      ProviderScope.containerOf(context, listen: false).read(pinRepositoryProvider);
  if (!await pins.isSet()) return true;
  if (!context.mounted) return false;
  return requirePin(context, reason: reason);
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
///
/// "Forgot PIN?" sits next to the title, in the part of the dialog that does
/// not scroll: on a small phone with the keyboard up the content does, and
/// the way back in must not be something to scroll for.
///
/// A PIN WITHOUT A RECOVERY CODE (one chosen before recovery codes existed)
/// gets an offer here, once: "Create a recovery code now". Taking it turns
/// this prompt into the confirmation — the PIN is entered as usual and the
/// recovery code is shown before the dialog closes. [createRecoveryCode]
/// opens the dialog with that already chosen (the banner in the settings).
class PinEntryDialog extends ConsumerStatefulWidget {
  const PinEntryDialog({
    super.key,
    this.reason,
    this.createRecoveryCode = false,
  });

  final String? reason;

  /// Entering the PIN creates a recovery code for it and shows it.
  final bool createRecoveryCode;

  @override
  ConsumerState<PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends ConsumerState<PinEntryDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _checking = false;

  /// This PIN has no recovery code and no prompt has offered one yet.
  bool _offer = false;

  /// The correct PIN will be followed by a new recovery code.
  late bool _createRecovery = widget.createRecoveryCode;

  @override
  void initState() {
    super.initState();
    if (!widget.createRecoveryCode) _loadOffer();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadOffer() async {
    // Asking IS taking: the offer is made on one prompt only.
    final offer = await ref.read(pinRepositoryProvider).takeRecoveryOffer();
    if (offer && mounted) setState(() => _offer = true);
  }

  Future<void> _submit() async {
    if (_checking) return;
    final l10n = AppLocalizations.of(context);
    final pin = _controller.text;
    if (!isValidPin(pin)) {
      setState(() => _error = l10n.pinInvalid);
      return;
    }
    // Taken before the first await: the recovery code that may follow is
    // shown and logged even if this dialog is gone by then.
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final pins = container.read(pinRepositoryProvider);
    final createRecovery = _createRecovery;
    setState(() {
      _checking = true;
      _error = null;
    });
    final result = await pins.verify(pin);
    switch (result) {
      case PinCorrect():
        if (createRecovery) {
          final code = await pins.issueRecoveryCode(pin);
          if (code != null) {
            await container
                .read(auditRepositoryProvider)
                .log(AuditAction.recoveryCodeCreate);
            refreshPinState(container);
            await showRecoveryCode(navigator, code);
          }
        }
        if (mounted) Navigator.of(context).pop(true);
      case PinWrong(:final attemptsLeft):
        if (!mounted) return;
        _controller.clear();
        setState(() {
          _checking = false;
          _error = l10n.pinWrong(attemptsLeft);
        });
      case PinLocked(:final until):
        if (!mounted) return;
        _controller.clear();
        setState(() {
          _checking = false;
          _error = l10n.pinLocked(
            formatLockTime(until.difference(DateTime.now())),
          );
        });
    }
  }

  /// "Forgot PIN?": the recovery code, then a new PIN. A PIN that was just
  /// chosen that way counts as entered — the action that asked goes ahead.
  Future<void> _forgot() async {
    final navigator = Navigator.of(context);
    final reset = await showDialog<bool>(
      context: context,
      builder: (_) => const PinRecoveryDialog(),
    );
    if (reset == true && mounted) navigator.pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final reason = widget.reason;
    return AlertDialog(
      key: const ValueKey('pin-entry-dialog'),
      // NOT `scrollable: true`: that would put the title — and "Forgot
      // PIN?" beside it — into the scrolling part. The title stays put, the
      // buttons stay put, and only the content between them scrolls.
      //
      // Tight paddings, and a title that is always ONE line (scaled down
      // when a large system font makes it wider than the dialog): on a
      // 360×640 phone with the keyboard up there are under 300 px for the
      // whole dialog, and what the title and the buttons do not take is
      // what is left for the PIN field.
      titlePadding: const EdgeInsetsDirectional.fromSTEB(24, 16, 16, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      title: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(l10n.pinEnterTitle, maxLines: 1),
          ),
          // Beside the title when there is room, under it when there is
          // not (a large system font) — never out of sight.
          TextButton(
            key: const ValueKey('pin-forgot'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: _checking ? null : _forgot,
            child: Text(l10n.pinForgot),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (reason != null && reason.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(reason),
              ),
            if (_createRecovery)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  l10n.recoveryCreateArmed,
                  key: const ValueKey('pin-recovery-armed'),
                  style: TextStyle(color: theme.colorScheme.primary),
                ),
              )
            else if (_offer)
              _RecoveryOffer(
                onAccept: _checking
                    ? null
                    : () => setState(() => _createRecovery = true),
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

/// The one-time offer on a PIN prompt: this PIN has no recovery code — make
/// one now?
class _RecoveryOffer extends StatelessWidget {
  const _RecoveryOffer({required this.onAccept});

  final VoidCallback? onAccept;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        key: const ValueKey('pin-recovery-offer'),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${l10n.recoveryMissingTitle}. ${l10n.recoveryMissingMessage}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onErrorContainer),
              ),
              TextButton(
                key: const ValueKey('pin-recovery-create'),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onAccept,
                child: Text(
                  l10n.recoveryCreateNow,
                  textAlign: TextAlign.start,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chooses a PIN: typed twice, 4 to 6 digits. Saves it, shows the recovery
/// code that goes with the new PIN (once — see [RecoveryCodeDialog]) and
/// pops `true`.
///
/// [firstUse]: opened because an action needs a PIN and there is none yet,
/// rather than from the settings.
class SetPinDialog extends ConsumerStatefulWidget {
  const SetPinDialog({
    super.key,
    this.firstUse = false,
    this.isChange = false,
    this.reset,
    this.reason,
  });

  final bool firstUse;

  /// Replaces an existing PIN (the old one was already asked for).
  final bool isChange;

  /// Replaces a FORGOTTEN PIN: the code that authorises it. The repository
  /// checks the code again when the new PIN is saved.
  final PinReset? reset;
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
    // The recovery code is shown through the NAVIGATOR, not through this
    // dialog: once the PIN is saved, the one chance to see its recovery code
    // must not depend on this dialog still being on screen.
    final navigator = Navigator.of(context);
    final pins = container.read(pinRepositoryProvider);
    final reset = widget.reset;
    final String? recovery;
    switch (reset?.kind) {
      case null:
        recovery = await pins.set(pin);
      case PinResetKind.recoveryCode:
        recovery = await pins.resetWithRecovery(code: reset!.code, newPin: pin);
      case PinResetKind.signedCode:
        final authority = container.read(signedPinResetProvider);
        recovery = authority == null
            ? null
            : await pins.resetWithSignedCode(
                code: reset!.code,
                newPin: pin,
                authority: authority,
              );
    }
    if (recovery == null) {
      // The code that opened this dialog was refused after all (used up, or
      // locked out meanwhile): nothing was changed.
      if (!mounted) return;
      setState(() {
        _saving = false;
        _pinError = l10n.recoveryRefused;
      });
      return;
    }
    await container.read(auditRepositoryProvider).log(switch (reset?.kind) {
          PinResetKind.recoveryCode => AuditAction.pinRecover,
          PinResetKind.signedCode => AuditAction.pinResetSigned,
          null => widget.isChange ? AuditAction.pinChange : AuditAction.pinSet,
        });
    refreshPinState(container);
    await showRecoveryCode(navigator, recovery);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reason = widget.reason;
    return AlertDialog(
      key: const ValueKey('pin-set-dialog'),
      scrollable: true,
      title: Text(
        widget.isChange || widget.reset != null
            ? l10n.pinChangeTitle
            : l10n.pinSetTitle,
      ),
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
