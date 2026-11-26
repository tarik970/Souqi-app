import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'dart:async';
import '../../core/backup/backup_crypto.dart';
import '../../core/backup/backup_file.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../data/backup/backup_service.dart';
import '../../l10n/generated/app_localizations.dart';

/// A NEW backup password, typed twice, under the warning that a forgotten
/// one cannot be recovered. Pops the password, or null.
class BackupPasswordDialog extends StatefulWidget {
  const BackupPasswordDialog({super.key, required this.title, this.intro});

  final String title;
  final String? intro;

  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  final _secondFocus = FocusNode();
  bool _visible = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    _secondFocus.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final first = _first.text;
    if (!isValidBackupPassword(first)) {
      setState(() => _error = l10n.backupPasswordTooShort(backupPasswordMinLength));
      return;
    }
    if (normalizeBackupPassword(first) !=
        normalizeBackupPassword(_second.text)) {
      setState(() => _error = l10n.backupPasswordMismatch);
      return;
    }
    Navigator.of(context).pop(first);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    Widget eye() => IconButton(
          tooltip: _visible ? l10n.backupPasswordHide : l10n.backupPasswordShow,
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
        );
    return AlertDialog(
      key: const ValueKey('backup-password-dialog'),
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.intro != null) ...[
            Text(widget.intro!),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('backup-password-1'),
            controller: _first,
            autofocus: true,
            obscureText: !_visible,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _secondFocus.requestFocus(),
            decoration: InputDecoration(
              labelText: l10n.backupPasswordLabel,
              helperText: l10n.backupPasswordMin(backupPasswordMinLength),
              suffixIcon: eye(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('backup-password-2'),
            controller: _second,
            focusNode: _secondFocus,
            obscureText: !_visible,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.backupPasswordAgain,
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.backupPasswordWarning,
                  key: const ValueKey('backup-password-warning'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('backup-password-ok'),
          onPressed: _submit,
          child: Text(l10n.backupPasswordOk),
        ),
      ],
    );
  }
}

/// "Created 24/11/2026 21:30 · 1,204 invoices · 85 customers…"
List<String> backupFacts(
  AppLocalizations l10n,
  BackupManifest manifest, {
  required String locale,
}) {
  String n(int value) => formatMinor(value, decimals: 0, locale: locale);
  final counts = manifest.counts;
  return [
    l10n.backupInfoDate(
      DateFormat.yMd(locale).add_jm().format(manifest.createdAt.toLocal()),
    ),
    l10n.backupInfoApp(manifest.appVersion),
    l10n.backupInfoInvoices(n(counts.invoices)),
    l10n.backupInfoCustomers(n(counts.customers)),
    l10n.backupInfoProducts(n(counts.products)),
    l10n.backupInfoCodes(n(counts.codes)),
    l10n.backupInfoDebts(n(counts.debtEntries)),
  ];
}

/// The password of the backup being restored. Tries it itself, so a wrong
/// one is said in the dialog and can be typed again; nothing is written by
/// a wrong password. Pops the [UnlockedBackup], a [CorruptBackupException]
/// for a file altered after it was made, or null.
class BackupUnlockDialog extends ConsumerStatefulWidget {
  const BackupUnlockDialog({
    super.key,
    required this.manifest,
    required this.unlock,
  });

  final BackupManifest manifest;
  final Future<UnlockedBackup> Function(String password) unlock;

  @override
  ConsumerState<BackupUnlockDialog> createState() => _BackupUnlockDialogState();
}

class _BackupUnlockDialogState extends ConsumerState<BackupUnlockDialog> {
  final _password = TextEditingController();
  bool _visible = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    if (_password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final unlocked = await widget.unlock(_password.text);
      if (mounted) Navigator.of(context).pop(unlocked);
    } on WrongBackupPasswordException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = l10n.backupWrongPassword;
      });
    } on CorruptBackupException catch (e) {
      if (mounted) Navigator.of(context).pop(e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('backup-unlock-dialog'),
      title: Text(l10n.restoreTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final fact in backupFacts(l10n, widget.manifest, locale: locale))
            Text(fact, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('backup-unlock-password'),
            controller: _password,
            autofocus: true,
            enabled: !_busy,
            obscureText: !_visible,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.backupPasswordLabel,
              errorText: _error,
              suffixIcon: IconButton(
                tooltip:
                    _visible ? l10n.backupPasswordHide : l10n.backupPasswordShow,
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('backup-unlock-ok'),
          onPressed: _busy ? null : _submit,
          child: Text(l10n.restoreNext),
        ),
      ],
    );
  }
}

/// The last word before a restore: what the backup holds, and that it
/// REPLACES everything on this phone. Nothing happens without the tick.
class RestoreConfirmDialog extends ConsumerStatefulWidget {
  const RestoreConfirmDialog({super.key, required this.manifest});

  final BackupManifest manifest;

  @override
  ConsumerState<RestoreConfirmDialog> createState() =>
      _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends ConsumerState<RestoreConfirmDialog> {
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('restore-confirm-dialog'),
      icon: Icon(Icons.warning_amber, color: theme.colorScheme.error),
      title: Text(l10n.restoreConfirmTitle),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.restoreConfirmWarning,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          for (final fact in backupFacts(l10n, widget.manifest, locale: locale))
            Text(fact),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('restore-confirm-check'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _understood,
            title: Text(l10n.restoreConfirmCheck),
            onChanged: (v) => setState(() => _understood = v ?? false),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('restore-confirm-ok'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed:
              _understood ? () => Navigator.of(context).pop(true) : null,
          child: Text(l10n.restoreConfirmButton),
        ),
      ],
    );
  }
}

/// A message that has to be read (the file is damaged, from a newer app…).
class BackupMessageDialog extends StatelessWidget {
  const BackupMessageDialog({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('backup-message-dialog'),
      title: Text(title),
      scrollable: true,
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}

/// A dialog that cannot be dismissed while [work] runs.
Future<T> runWithProgress<T>(
  BuildContext context,
  String text,
  Future<T> Function() work,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  // Its own route, removed by name at the end: a route pushed over it
  // meanwhile (the report notification opens a screen) must not be popped
  // in its place, leaving a dialog that can never be dismissed.
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('backup-progress'),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    ),
  );
  unawaited(navigator.push(route));
  try {
    return await work();
  } finally {
    // After a restore the whole app has started over: that navigator, and
    // the dialog with it, are gone already.
    if (navigator.mounted && route.isActive) navigator.removeRoute(route);
  }
}
