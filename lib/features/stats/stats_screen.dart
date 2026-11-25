import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../data/repositories/archive_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';
import 'stats_providers.dart';

/// Sales statistics for a period, against the period before it.
///
/// Every amount is in the BASE currency, taken from the figures each invoice
/// stored at the time of the sale. Today's exchange rate never moves last
/// month's total.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  /// The periods statistics offer. "All" is left out: a total with nothing
  /// to compare it against is not a statistic.
  static const List<ArchivePeriod> periods = [
    ArchivePeriod.today,
    ArchivePeriod.thisWeek,
    ArchivePeriod.thisMonth,
    ArchivePeriod.custom,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(statsPeriodProvider);
    final report = ref.watch(statsReportProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navStats)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final value in periods) ...[
                  if (value != periods.first) const SizedBox(width: 8),
                  ChoiceChip(
                    key: ValueKey('stats-period-${value.name}'),
                    label: Text(_periodLabel(l10n, value)),
                    selected: period.preset == value,
                    onSelected: (_) => _select(context, ref, value),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: report.when(
              data: (data) => _Report(report: data),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
      ),
    );
  }

  static String _periodLabel(AppLocalizations l10n, ArchivePeriod period) =>
      switch (period) {
        ArchivePeriod.all => l10n.periodAll,
        ArchivePeriod.today => l10n.periodToday,
        ArchivePeriod.yesterday => l10n.periodYesterday,
        ArchivePeriod.thisWeek => l10n.periodThisWeek,
        ArchivePeriod.thisMonth => l10n.periodThisMonth,
        ArchivePeriod.custom => l10n.periodCustom,
      };

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ArchivePeriod value,
  ) async {
    if (value != ArchivePeriod.custom) {
      ref.read(statsPeriodProvider.notifier).setPreset(value);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null || !context.mounted) return;
    ref
        .read(statsPeriodProvider.notifier)
        .setCustomRange(picked.start, picked.end);
  }
}

class _Report extends ConsumerWidget {
  const _Report({required this.report});

  final StatsReport report;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final base = report.baseCurrency;
    final showByCurrency = ref.watch(currencyBreakdownProvider);

    String money(int minor) => formatMinor(
          minor,
          decimals: base.decimalPlaces,
          locale: locale,
          symbol: base.symbol.isEmpty ? base.code : base.symbol,
        );
    String count(int value) =>
        formatMinor(value, decimals: 0, locale: locale);

    final range = report.period.range;
    final dates = DateFormat.yMd(locale);

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.periodRangeLabel(
                  dates.format(range.from),
                  // The range's end is exclusive; the label names the last
                  // day that is actually included.
                  dates.format(range.to.subtract(const Duration(days: 1))),
                ),
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 2),
              Text(
                l10n.statsBaseCurrencyNote(base.code),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
        _StatCard(
          keyName: 'stats-total',
          label: l10n.statsTotalSales,
          value: money(report.current.totalBaseMinor),
          comparison: report.totalComparison,
          format: money,
          emphasize: true,
        ),
        _StatCard(
          keyName: 'stats-count',
          label: l10n.statsInvoiceCount,
          value: count(report.current.invoiceCount),
          comparison: report.countComparison,
          format: count,
        ),
        _StatCard(
          keyName: 'stats-average',
          label: l10n.statsAverageInvoice,
          value: money(report.current.averageBaseMinor),
          comparison: report.averageComparison,
          format: money,
        ),
        _StatCard(
          keyName: 'stats-discounts',
          label: l10n.statsTotalDiscounts,
          value: money(report.current.discountBaseMinor),
          comparison: report.discountComparison,
          format: money,
        ),
        if (report.current.invoiceCount == 0)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.statsNoData, textAlign: TextAlign.center),
          )
        else ...[
          _ProductTable(
            keyName: 'stats-top-sales',
            title: l10n.statsTopBySales,
            rows: report.topBySales,
            trailing: (p) => l10n.statsSalesCount(count(p.salesCount)),
          ),
          _ProductTable(
            keyName: 'stats-top-amount',
            title: l10n.statsTopByAmount,
            rows: report.topByAmount,
            trailing: (p) => money(p.amountBaseMinor),
          ),
          // Renewals and customers: only when the feature is on AND the
          // period has any — a grocery shop's statistics stay as they were.
          if (accountsEnabled && report.renewals.count > 0)
            _RowsCard(
              keyName: 'stats-renewals',
              title: l10n.statsRenewals,
              rows: [
                (
                  title: l10n.statsInvoicesCount(count(report.renewals.count)),
                  subtitle: null,
                  trailing: money(report.renewals.totalBaseMinor),
                ),
              ],
            ),
          if (accountsEnabled && report.topPackages.isNotEmpty)
            _RowsCard(
              keyName: 'stats-top-packages',
              title: l10n.statsTopPackages,
              rows: [
                for (final package in report.topPackages)
                  (
                    title: package.name,
                    subtitle: l10n.statsSalesCount(count(package.salesCount)),
                    trailing: money(package.amountBaseMinor),
                  ),
              ],
            ),
          if (customersEnabled && report.topCustomers.isNotEmpty)
            _RowsCard(
              keyName: 'stats-top-customers',
              title: l10n.statsTopCustomers,
              rows: [
                for (final customer in report.topCustomers)
                  (
                    title: customer.name,
                    subtitle:
                        l10n.statsInvoicesCount(count(customer.invoiceCount)),
                    trailing: money(customer.totalBaseMinor),
                  ),
              ],
            ),
          SwitchListTile(
            key: const ValueKey('stats-by-currency-switch'),
            title: Text(l10n.statsShowByCurrency),
            value: showByCurrency,
            onChanged: (_) =>
                ref.read(currencyBreakdownProvider.notifier).toggle(),
          ),
          if (showByCurrency) _CurrencyBreakdown(rows: report.byCurrency),
        ],
      ],
    );
  }
}

/// One headline figure with its comparison against the previous period.
class _StatCard extends ConsumerWidget {
  const _StatCard({
    required this.keyName,
    required this.label,
    required this.value,
    required this.comparison,
    required this.format,
    this.emphasize = false,
  });

  final String keyName;
  final String label;
  final String value;
  final Comparison comparison;

  /// Formats the previous period's figure the same way as [value].
  final String Function(int) format;

  final bool emphasize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);

    final percent = comparison.percent;
    // The direction is carried by an icon AND by words. Colour is only ever
    // the third signal: a thermal-printed page, a grey-scale screen or a
    // colour-blind reader must all still get it.
    final (icon, trend) = switch (comparison.direction) {
      TrendDirection.up => (
          Icons.arrow_upward,
          percent == null
              ? l10n.statsTrendNew
              : l10n.statsTrendUp(_percentText(percent, locale)),
        ),
      TrendDirection.down => (
          Icons.arrow_downward,
          percent == null
              ? l10n.statsTrendGone
              : l10n.statsTrendDown(_percentText(percent, locale)),
        ),
      TrendDirection.flat => (Icons.remove, l10n.statsTrendFlat),
    };

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              value,
              key: ValueKey('$keyName-value'),
              style: (emphasize
                      ? theme.textTheme.headlineMedium
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.outline),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$trend · ${l10n.statsPreviousValue(format(comparison.previous))}',
                    key: ValueKey('$keyName-trend'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One decimal place, localized ("12.5", "١٢٫٥").
  static String _percentText(double percent, String locale) => formatMinor(
        (percent.abs() * 10).round(),
        decimals: 1,
        locale: locale,
      );
}

class _ProductTable extends ConsumerWidget {
  const _ProductTable({
    required this.keyName,
    required this.title,
    required this.rows,
    required this.trailing,
  });

  final String keyName;
  final String title;
  final List<ProductStat> rows;
  final String Function(ProductStat) trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (rows.isEmpty) return const SizedBox.shrink();
    return Card(
      key: ValueKey(keyName),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          for (final row in rows)
            ListTile(
              dense: true,
              title: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              // An item that was sold without ever being saved as a product
              // is still a row here, grouped by its normalized name.
              subtitle: row.productId == null
                  ? Text(l10n.statsUnsavedItemBadge)
                  : null,
              trailing: Text(
                trailing(row),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

/// A titled card of "name … amount" rows: renewals, top packages, sales per
/// customer.
class _RowsCard extends StatelessWidget {
  const _RowsCard({
    required this.keyName,
    required this.title,
    required this.rows,
  });

  final String keyName;
  final String title;
  final List<({String title, String? subtitle, String trailing})> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: ValueKey(keyName),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(title, style: theme.textTheme.titleSmall),
          ),
          for (final row in rows)
            ListTile(
              dense: true,
              title: Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: row.subtitle == null ? null : Text(row.subtitle!),
              trailing: Text(
                row.trailing,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}

class _CurrencyBreakdown extends ConsumerWidget {
  const _CurrencyBreakdown({required this.rows});

  final List<CurrencyTotal> rows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final currencies = ref.watch(currenciesProvider).value ?? const <Currency>[];

    return Card(
      key: const ValueKey('stats-by-currency'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(l10n.statsByCurrency, style: theme.textTheme.titleSmall),
          ),
          for (final row in rows)
            ListTile(
              dense: true,
              title: Text(row.currencyCode),
              subtitle: Text(
                '${l10n.statsInvoiceCount}: '
                '${formatMinor(row.invoiceCount, decimals: 0, locale: locale)}',
              ),
              trailing: Text(
                formatMinor(
                  row.totalMinor,
                  decimals: currencies
                          .where((c) => c.code == row.currencyCode)
                          .firstOrNull
                          ?.decimalPlaces ??
                      0,
                  locale: locale,
                  symbol: row.currencyCode,
                ),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
    );
  }
}
