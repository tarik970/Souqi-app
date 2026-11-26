import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../core/widgets/numeric_input.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../data/repositories/archive_repository.dart';
import 'storage_providers.dart';

/// Settings → Archive → "Auto-delete old invoices".
///
/// Off by default. Choosing a number of days writes `auto_delete_days` and
/// runs the cleanup straight away, so the seller sees the effect of the
/// choice now instead of discovering it at tomorrow's first launch. After
/// that, [HousekeepingController.applyRetentionDaily] takes over at startup.
class RetentionTile extends ConsumerWidget {
  const RetentionTile({super.key});

  /// The offered periods, in days. 0 is "off"; -1 opens the custom field.
  static const List<int> presets = [0, 30, 90, 180, 365];
  static const int customValue = -1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final days = ref.watch(retentionDaysProvider).value ?? 0;

    String label(int value) => value == 0
        ? l10n.retentionOff
        : l10n.retentionDays(
            formatMinor(value, decimals: 0, locale: locale),
          );

    return ListTile(
      key: const ValueKey('setting-auto-delete'),
      leading: const Icon(Icons.auto_delete_outlined),
      title: Text(l10n.settingAutoDelete),
      // The picker sits UNDER the explanation and is as wide as the tile,
      // like the shop type and the due-soon window: as a trailing widget it
      // squeezed the hint into a narrow column at a large system font.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingAutoDeleteHint),
          DropdownButton<int>(
            key: const ValueKey('setting-auto-delete-dropdown'),
            // A number the user typed is shown alongside the presets rather
            // than snapping to the nearest one.
            value: presets.contains(days) ? days : customValue,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in presets)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    label(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              DropdownMenuItem(
                value: customValue,
                child: Text(
                  presets.contains(days) ? l10n.retentionCustom : label(days),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: (value) => _choose(context, ref, value, current: days),
          ),
        ],
      ),
    );
  }

  Future<void> _choose(
    BuildContext context,
    WidgetRef ref,
    int? value, {
    required int current,
  }) async {
    if (value == null) return;
    var days = value;
    if (days == customValue) {
      final typed = await showDialog<int>(
        context: context,
        builder: (_) => _CustomDaysDialog(initial: current),
      );
      if (typed == null) return;
      days = typed;
    }
    if (!context.mounted) return;
    await _apply(context, ref, days);
  }

  /// Writes the setting and sweeps once, now.
  Future<void> _apply(BuildContext context, WidgetRef ref, int days) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    // The Settings screen can be popped while the delete runs; the container
    // outlives it, and the cleanup must finish either way.
    final container = ProviderScope.containerOf(context, listen: false);

    // WHAT THE CHOICE DELETES RIGHT NOW is counted first and confirmed: one
    // slip of the finger in this list ("30 days" for "365 days") would
    // otherwise remove eleven months of invoices before any question.
    final housekeeping = container.read(housekeepingProvider.notifier);
    if (days > 0) {
      final cutoff = await housekeeping.retentionCutoff(days);
      final doomed = cutoff == null
          ? 0
          : await container
              .read(archiveRepositoryProvider)
              .countMatching(ArchiveFilter(to: cutoff));
      if (doomed > 0) {
        if (!context.mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            key: const ValueKey('retention-confirm'),
            scrollable: true,
            title: Text(l10n.retentionConfirmTitle),
            content: Text(l10n.retentionConfirmMessage(
              formatMinor(doomed, decimals: 0, locale: locale),
              formatMinor(days, decimals: 0, locale: locale),
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                key: const ValueKey('retention-confirm-delete'),
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(l10n.delete),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

    await container
        .read(settingsRepositoryProvider)
        .setInt(SettingsKeys.autoDeleteDays, days);
    container.invalidate(retentionDaysProvider);
    if (days <= 0) return;

    final deleted = await housekeeping.applyRetention();
    if (deleted == 0) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.retentionNotice(
          formatMinor(deleted, decimals: 0, locale: locale),
          formatMinor(days, decimals: 0, locale: locale),
        )),
      ));
  }
}

/// "Delete invoices older than … days". Owns its controller for its whole
/// life, so nothing can rebuild on a disposed one while the dialog closes.
class _CustomDaysDialog extends StatefulWidget {
  const _CustomDaysDialog({required this.initial});

  final int initial;

  @override
  State<_CustomDaysDialog> createState() => _CustomDaysDialogState();
}

class _CustomDaysDialogState extends State<_CustomDaysDialog> {
  late final _controller = TextEditingController(
    text: widget.initial > 0 ? '${widget.initial}' : '',
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    // Arabic-Indic digits are digits too; and a number of days beyond a
    // century is a typo, not a retention.
    final days = int.tryParse(normalizeDigits(_controller.text.trim()));
    if (days == null || days <= 0 || days > maxRetentionDays) {
      setState(() => _error = AppLocalizations.of(context).invalidNumber);
      return;
    }
    Navigator.of(context).pop(days);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.retentionCustomTitle),
      // Scrolls: with the keyboard up on a small phone at a large system
      // font the title, the field and the buttons do not all fit.
      scrollable: true,
      content: SelectAllOnFocus(
        controller: _controller,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          textDirection: TextDirection.ltr,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.retentionCustomHint,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
