import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_text.dart' show formatBasisPoints;
import '../stats/stats_providers.dart';
import 'debt_providers.dart';
import 'debt_widgets.dart';

/// The debt figures of the statistics screen, for the period on screen:
/// outstanding now, new debt, collected, collection rate, debts by age and
/// the ten largest balances.
///
/// Nothing at all while the debt ledger is off; a locked row while the "PIN
/// to open debts" setting is on and the PIN has not been entered — and then
/// the figures are not even read.
class DebtStatsCard extends ConsumerWidget {
  const DebtStatsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!featureOn(Feature.debt)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final pinRequired = ref.watch(debtRequirePinProvider).value;
    if (pinRequired == null) return const SizedBox.shrink();

    Widget card(List<Widget> children) => Card(
          key: const ValueKey('stats-debts'),
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(l10n.debtsTitle, style: theme.textTheme.titleSmall),
              ),
              ...children,
            ],
          ),
        );

    if (pinRequired && !ref.watch(debtUnlockedProvider)) {
      return card([
        ListTile(
          key: const ValueKey('stats-debts-locked'),
          leading: const Icon(Icons.lock_outline),
          title: Text(l10n.debtLockedMessage),
          trailing: TextButton(
            key: const ValueKey('stats-debts-unlock'),
            onPressed: () => requireDebtAccess(context),
            child: Text(l10n.unlock),
          ),
        ),
      ]);
    }

    final stats = ref.watch(debtStatsProvider).value;
    if (stats == null) return const SizedBox.shrink();
    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = ref.watch(baseMoneyProvider);
    final rate = stats.collectionRateBasisPoints;

    Widget row(String label, String value, {required String keyName}) =>
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  value,
                  key: ValueKey(keyName),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );

    return card([
      row(
        l10n.statsOutstandingNow,
        money(stats.outstandingBaseMinor),
        keyName: 'stats-debt-outstanding',
      ),
      row(
        l10n.statsNewDebt,
        money(stats.newDebtBaseMinor),
        keyName: 'stats-debt-new',
      ),
      row(
        l10n.statsCollected,
        money(stats.collectedBaseMinor),
        keyName: 'stats-debt-collected',
      ),
      row(
        l10n.statsCollectionRate,
        rate == null ? '—' : '${formatBasisPoints(rate, locale: locale)}%',
        keyName: 'stats-debt-rate',
      ),
      if (stats.outstandingBaseMinor > 0) ...[
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.agingTitle,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AgingGrid(aging: stats.aging),
        ),
      ],
      if (stats.topDebtors.isNotEmpty) ...[
        const Divider(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            l10n.statsTopDebtors,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        for (final debtor in stats.topDebtors)
          Padding(
            key: ValueKey('stats-debtor-${debtor.customerId}'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    debtor.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  money(debtor.balanceBaseMinor),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
      ],
    ]);
  }
}
