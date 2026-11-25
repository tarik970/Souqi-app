import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import 'audit_log_screen.dart';
import 'pin_dialogs.dart';

enum _PinChoice { change, remove }

/// Settings → Security → "PIN lock": choose a PIN, or — after entering the
/// current one — change or remove it.
class PinSettingsTile extends ConsumerWidget {
  const PinSettingsTile({super.key});

  Future<void> _open(BuildContext context, bool isSet) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    if (!isSet) {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => const SetPinDialog(),
      );
      if (saved == true) say(l10n.pinSaved);
      return;
    }

    final choice = await showModalBottomSheet<_PinChoice>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          key: const ValueKey('pin-options-sheet'),
          shrinkWrap: true,
          children: [
            ListTile(
              key: const ValueKey('pin-option-change'),
              leading: const Icon(Icons.password),
              title: Text(l10n.pinChangeAction),
              onTap: () => Navigator.of(context).pop(_PinChoice.change),
            ),
            ListTile(
              key: const ValueKey('pin-option-remove'),
              leading: const Icon(Icons.lock_open),
              title: Text(l10n.pinRemoveAction),
              onTap: () => Navigator.of(context).pop(_PinChoice.remove),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    // Either way the CURRENT PIN comes first.
    if (!await requirePin(context) || !context.mounted) return;

    switch (choice) {
      case _PinChoice.change:
        final saved = await showDialog<bool>(
          context: context,
          builder: (_) => const SetPinDialog(isChange: true),
        );
        if (saved == true) say(l10n.pinSaved);
      case _PinChoice.remove:
        // A confirmed removal is carried out even if this tile is gone.
        final container = ProviderScope.containerOf(context, listen: false);
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('pin-remove-dialog'),
            scrollable: true,
            title: Text(l10n.pinRemoveTitle),
            content: Text(l10n.pinRemoveMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.pinRemoveAction),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
        await container.read(pinRepositoryProvider).clear();
        await container
            .read(auditRepositoryProvider)
            .log(AuditAction.pinRemove);
        container.invalidate(pinIsSetProvider);
        say(l10n.pinRemoved);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isSet = ref.watch(pinIsSetProvider).value ?? false;
    return ListTile(
      key: const ValueKey('setting-pin'),
      leading: Icon(isSet ? Icons.lock_outline : Icons.lock_open),
      title: Text(l10n.pinLockTitle),
      subtitle: Text(isSet ? l10n.pinIsSet : l10n.pinNotSet),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _open(context, isSet),
    );
  }
}

/// Settings → Security → "Audit log". The PIN comes first.
class AuditLogTile extends StatelessWidget {
  const AuditLogTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('setting-audit-log'),
      leading: const Icon(Icons.fact_check_outlined),
      title: Text(l10n.auditLogTitle),
      subtitle: Text(l10n.auditLogHint),
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        final navigator = Navigator.of(context);
        if (!await requirePin(context)) return;
        if (!navigator.mounted) return;
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const AuditLogScreen()),
        );
      },
    );
  }
}
