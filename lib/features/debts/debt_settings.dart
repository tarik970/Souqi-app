import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';
import '../security/pin_dialogs.dart';
import 'debt_providers.dart';
import 'debt_text.dart';
import 'opening_balances_screen.dart';

/// Settings → Debts → "Days to pay": how long a new debt is given before it
/// counts as overdue, for a customer without a number of their own
/// (default 30).
class DebtDueDaysTile extends ConsumerWidget {
  const DebtDueDaysTile({super.key});

  static const List<int> presets = [7, 10, 14, 15, 30, 45, 60, 90];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final days = ref.watch(debtDefaultDueDaysProvider).value ?? 30;
    final options = {...presets, days}.toList()..sort();

    return ListTile(
      key: const ValueKey('setting-debt-due-days'),
      leading: const Icon(Icons.event_available_outlined),
      title: Text(l10n.defaultDueDaysLabel),
      // The picker sits UNDER the explanation, like the other day pickers:
      // beside it, it squeezes the text on a small phone at a large font.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.defaultDueDaysHint),
          DropdownButton<int>(
            key: const ValueKey('setting-debt-due-days-dropdown'),
            value: days,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in options)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    l10n.daysCount(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              // The screen can be closed while the write runs.
              final container =
                  ProviderScope.containerOf(context, listen: false);
              await container
                  .read(settingsRepositoryProvider)
                  .setInt(SettingsKeys.debtDefaultDueDays, value);
              container.invalidate(debtDefaultDueDaysProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// Settings → Debts → "PIN to open debts" (off by default): the debtors
/// list and customer accounts then ask for the PIN. Selling on credit never
/// does.
///
/// Switching it ON makes sure a PIN exists first; switching it OFF asks for
/// the PIN — taking a lock off is exactly what the lock is for.
class DebtRequirePinTile extends ConsumerWidget {
  const DebtRequirePinTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final on = ref.watch(debtRequirePinProvider).value ?? false;
    return SwitchListTile(
      key: const ValueKey('setting-debt-require-pin'),
      secondary: const Icon(Icons.lock_outline),
      title: Text(l10n.debtRequirePinTitle),
      subtitle: Text(l10n.debtRequirePinSubtitle),
      value: on,
      onChanged: (value) async {
        final container = ProviderScope.containerOf(context, listen: false);
        final allowed = value
            ? await ensurePinIsSet(context, reason: l10n.debtRequirePinTitle)
            : await requirePin(context, reason: l10n.pinReasonDebtAccess);
        if (!allowed) return;
        await container
            .read(settingsRepositoryProvider)
            .setBool(SettingsKeys.debtRequirePin, value);
        // Whoever just set the lock (or entered the PIN to remove it) is
        // the one holding the key.
        container.read(debtUnlockedProvider.notifier).unlock();
        container.invalidate(debtRequirePinProvider);
      },
    );
  }
}

/// Settings → Debts → "Debt reminder message": the text the WhatsApp
/// reminder opens the customer's chat with.
class DebtReminderTile extends ConsumerWidget {
  const DebtReminderTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('setting-debt-reminder'),
      leading: const Icon(Icons.chat_outlined),
      title: Text(l10n.debtReminderTitle),
      subtitle: Text(l10n.debtReminderHint),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(context),
    );
  }

  Future<void> _edit(BuildContext context) async {
    // Everything is read through the container: the dialog can outlive this
    // tile, and a confirmed text must still be saved.
    final container = ProviderScope.containerOf(context, listen: false);
    final stored = await container.read(debtReminderTemplateProvider.future);
    final settings = await container.read(invoiceSettingsProvider.future);
    if (!context.mounted) return;
    // The default follows the INVOICE language: the reminder is read by the
    // customer, like the invoice, not by the seller.
    final fallback = defaultDebtReminderTemplate(settings.language);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => DebtReminderDialog(
        initial: stored.trim().isEmpty ? fallback : stored,
        defaultText: fallback,
      ),
    );
    if (text == null) return;
    final cleaned = text.trim();
    // Left as the default: store nothing, so it keeps following the invoice
    // language if that is changed later.
    await container.read(settingsRepositoryProvider).setString(
          SettingsKeys.debtReminderText,
          cleaned == fallback.trim() ? '' : cleaned,
        );
    container.invalidate(debtReminderTemplateProvider);
  }
}

/// Edits the debt reminder text. Owns its controller for its whole life and
/// returns the text through [Navigator.pop]; nothing when cancelled.
class DebtReminderDialog extends StatefulWidget {
  const DebtReminderDialog({
    super.key,
    required this.initial,
    required this.defaultText,
  });

  final String initial;
  final String defaultText;

  @override
  State<DebtReminderDialog> createState() => _DebtReminderDialogState();
}

class _DebtReminderDialogState extends State<DebtReminderDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('debt-reminder-dialog'),
      title: Text(l10n.debtReminderTitle),
      // Scrolls: with the keyboard up on a small phone there is room for
      // the text field or for the buttons, not both.
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('debt-reminder-field'),
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reminderPlaceholdersHint(debtReminderPlaceholders.join(' ')),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('debt-reminder-use-default'),
          onPressed: () => _controller.text = widget.defaultText,
          child: Text(l10n.reminderResetDefault),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('debt-reminder-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// Settings → Debts → "Opening balances": the bulk entry screen for a shop
/// moving from a paper notebook.
class OpeningBalancesTile extends StatelessWidget {
  const OpeningBalancesTile({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('setting-opening-balances'),
      leading: const Icon(Icons.playlist_add),
      title: Text(l10n.openingBalancesTitle),
      subtitle: Text(l10n.openingBalancesIntro),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const OpeningBalancesScreen()),
      ),
    );
  }
}
