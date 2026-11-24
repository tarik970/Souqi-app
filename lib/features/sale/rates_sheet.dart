import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';
import '../currencies/update_rate_dialog.dart';

/// Quick exchange-rate update from the sale screen.
///
/// With a single non-base currency the rate dialog opens straight away (two
/// taps from the sale screen); otherwise a list of the currencies with their
/// rate and when it was last updated.
Future<void> openRatesQuickAction(
  BuildContext context,
  WidgetRef ref, {
  required String baseCode,
  required List<Currency> currencies,
}) async {
  final others = [
    for (final currency in currencies)
      if (currency.code != baseCode && currency.isActive) currency,
  ];
  if (others.isEmpty) return;
  if (others.length == 1) {
    await showUpdateRateDialog(
      context,
      ref,
      currency: others.first,
      baseCode: baseCode,
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    builder: (_) => RatesSheet(baseCode: baseCode, currencies: others),
  );
}

class RatesSheet extends ConsumerWidget {
  const RatesSheet({
    super.key,
    required this.baseCode,
    required this.currencies,
  });

  final String baseCode;
  final List<Currency> currencies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    // Re-read from the provider so a saved rate updates this list in place.
    final live = ref.watch(currenciesProvider).value;
    final rows = live == null
        ? currencies
        : [
            for (final currency in live)
              if (currency.code != baseCode && currency.isActive) currency,
          ];

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.currency_exchange),
                const SizedBox(width: 12),
                Text(l10n.ratesTitle, style: theme.textTheme.titleLarge),
              ],
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: rows.length,
              itemBuilder: (context, index) {
                final currency = rows[index];
                return ListTile(
                  title: Text(l10n.rateDisplay(
                    currency.code,
                    formatRateValue(currency.rate, locale: locale),
                    baseCode,
                  )),
                  subtitle: Text(currency.rateUpdatedAt == null
                      ? l10n.rateNeverUpdated
                      : l10n.rateUpdatedAt(DateFormat.yMd(locale)
                          .add_jm()
                          .format(currency.rateUpdatedAt!.toLocal()))),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => showUpdateRateDialog(
                    context,
                    ref,
                    currency: currency,
                    baseCode: baseCode,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
