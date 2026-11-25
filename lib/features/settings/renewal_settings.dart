import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../customers/reminder_text.dart';
import '../invoice/invoice_providers.dart';

/// Settings → Customers & renewals → "Due-soon window": the N of "due in the
/// next N days" on the due list (default 3).
class DueSoonDaysTile extends ConsumerWidget {
  const DueSoonDaysTile({super.key});

  static const List<int> presets = [1, 2, 3, 5, 7, 10, 14, 30];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final days = ref.watch(dueSoonDaysProvider).value ?? 3;
    final options = {...presets, days}.toList()..sort();

    return ListTile(
      key: const ValueKey('setting-due-soon'),
      leading: const Icon(Icons.event_repeat),
      title: Text(l10n.settingDueSoonDays),
      // The picker sits UNDER the explanation, not beside it: as a trailing
      // widget it squeezed the text into a column a few characters wide on
      // a small phone at a large system font.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingDueSoonDaysHint),
          DropdownButton<int>(
            key: const ValueKey('setting-due-soon-dropdown'),
            value: days,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in options)
                DropdownMenuItem(
                  value: value,
                  child: Text(l10n.daysCount(value)),
                ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              // The screen can be closed while the write runs.
              final container =
                  ProviderScope.containerOf(context, listen: false);
              await container
                  .read(settingsRepositoryProvider)
                  .setInt(SettingsKeys.dueSoonDays, value);
              // The due list and the badge watch this and follow.
              container.invalidate(dueSoonDaysProvider);
            },
          ),
        ],
      ),
    );
  }
}

/// Settings → Customers & renewals → "Renewal reminder message": the text
/// the due list's WhatsApp button opens the customer's chat with.
class ReminderTextTile extends ConsumerWidget {
  const ReminderTextTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('setting-reminder-text'),
      leading: const Icon(Icons.chat_outlined),
      title: Text(l10n.settingReminderText),
      subtitle: Text(l10n.settingReminderTextHint),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => _edit(context),
    );
  }

  Future<void> _edit(BuildContext context) async {
    // Everything is read through the container: the dialog can outlive this
    // tile, and a confirmed text must still be saved.
    final container = ProviderScope.containerOf(context, listen: false);
    final stored = await container.read(reminderTemplateProvider.future);
    final settings = await container.read(invoiceSettingsProvider.future);
    if (!context.mounted) return;
    // The default follows the INVOICE language: the reminder is read by the
    // customer, like the invoice, not by the seller.
    final fallback = defaultReminderTemplate(settings.language);
    final text = await showDialog<String>(
      context: context,
      builder: (_) => ReminderTextDialog(
        initial: stored.trim().isEmpty ? fallback : stored,
        defaultText: fallback,
      ),
    );
    if (text == null) return;
    final cleaned = text.trim();
    // Left as the default: store nothing, so it keeps following the invoice
    // language if that is changed later.
    await container.read(settingsRepositoryProvider).setString(
          SettingsKeys.renewalReminderText,
          cleaned == fallback.trim() ? '' : cleaned,
        );
    container.invalidate(reminderTemplateProvider);
  }
}

/// Edits the reminder text. Owns its controller for its whole life and
/// returns the text through [Navigator.pop]; nothing when cancelled.
class ReminderTextDialog extends StatefulWidget {
  const ReminderTextDialog({
    super.key,
    required this.initial,
    required this.defaultText,
  });

  final String initial;
  final String defaultText;

  @override
  State<ReminderTextDialog> createState() => _ReminderTextDialogState();
}

class _ReminderTextDialogState extends State<ReminderTextDialog> {
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
      title: Text(l10n.reminderDialogTitle),
      // Scrolls: with the keyboard up on a small phone there is room for
      // the text field or for the buttons, not both.
      scrollable: true,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('reminder-text-field'),
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.reminderPlaceholdersHint(reminderPlaceholders.join(' ')),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('reminder-use-default'),
          onPressed: () => _controller.text = widget.defaultText,
          child: Text(l10n.reminderResetDefault),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
