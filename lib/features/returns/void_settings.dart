import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../security/audit_providers.dart';
import '../security/pin_dialogs.dart';
import 'returns_providers.dart';

/// Settings → Archive → "Voiding invoices": an invoice can be voided while
/// it is at most this many days old (30 unless changed); "No limit" lets any
/// invoice be voided.
///
/// The owner's setting: changing it asks for the PIN when one is set, and is
/// written to the audit log. (Returns have no such limit.)
class VoidAgeLimitTile extends ConsumerWidget {
  const VoidAgeLimitTile({super.key});

  /// The offered limits, in days; 0 = no limit, listed last.
  static const List<int> presets = [1, 3, 7, 14, 30, 60, 90, 180, 365, 0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final days = ref.watch(voidMaxAgeDaysProvider).value ?? 30;
    // A number stored by hand is shown alongside the presets.
    final limited = {...presets.where((d) => d > 0), if (days > 0) days}
        .toList()
      ..sort();
    final options = [...limited, 0];

    return ListTile(
      key: const ValueKey('setting-void-age'),
      leading: const Icon(Icons.event_busy_outlined),
      title: Text(l10n.settingVoidAge),
      // The picker sits UNDER the explanation, like the other day pickers:
      // beside it, it squeezes the text on a small phone at a large font.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.settingVoidAgeHint),
          DropdownButton<int>(
            key: const ValueKey('setting-void-age-dropdown'),
            value: days,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in options)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    value == 0 ? l10n.voidAgeNoLimit : l10n.daysCount(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) async {
              if (value == null || value == days) return;
              // The screen can be closed while the write runs.
              final container =
                  ProviderScope.containerOf(context, listen: false);
              if (!await requirePinIfSet(
                context,
                reason: l10n.pinReasonVoidAge,
              )) {
                return;
              }
              await container
                  .read(settingsRepositoryProvider)
                  .setInt(SettingsKeys.voidMaxAgeDays, value);
              await container
                  .read(auditRepositoryProvider)
                  .log(AuditAction.voidAgeLimit, details: {'days': value});
              container
                ..invalidate(voidMaxAgeDaysProvider)
                ..invalidate(auditLogProvider);
            },
          ),
        ],
      ),
    );
  }
}
