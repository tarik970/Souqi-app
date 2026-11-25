import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/providers.dart';
import '../../core/utils/date_ranges.dart';
import '../../data/repositories/archive_repository.dart';
import '../../data/repositories/stats_repository.dart';
import '../../domain/models/currency.dart';

/// The period the statistics screen is showing: a preset, or a custom range.
class StatsPeriod {
  const StatsPeriod({required this.preset, required this.range});

  final ArchivePeriod preset;
  final DateRange range;

  @override
  bool operator ==(Object other) =>
      other is StatsPeriod && other.preset == preset && other.range == range;

  @override
  int get hashCode => Object.hash(preset, range);
}

class StatsPeriodNotifier extends Notifier<StatsPeriod> {
  @override
  StatsPeriod build() => StatsPeriod(
        preset: ArchivePeriod.today,
        range: resolvePeriod(ArchivePeriod.today)!,
      );

  /// [ArchivePeriod.all] and [ArchivePeriod.custom] have no preset dates;
  /// statistics always need a period, so they are ignored here — a custom
  /// range arrives through [setCustomRange].
  void setPreset(ArchivePeriod preset, {DateTime? now}) {
    final range = resolvePeriod(preset, now: now);
    if (range == null) return;
    state = StatsPeriod(preset: preset, range: range);
  }

  void setCustomRange(DateTime first, DateTime last) => state = StatsPeriod(
        preset: ArchivePeriod.custom,
        range: customRange(first, last),
      );
}

final statsPeriodProvider =
    NotifierProvider<StatsPeriodNotifier, StatsPeriod>(
  StatsPeriodNotifier.new,
);

/// Whether the breakdown of sales by invoice currency is expanded. Off by
/// default: a single-currency shop never needs it.
class CurrencyBreakdownNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final currencyBreakdownProvider =
    NotifierProvider<CurrencyBreakdownNotifier, bool>(
  CurrencyBreakdownNotifier.new,
);

/// Everything the statistics screen draws, for one period.
class StatsReport {
  const StatsReport({
    required this.period,
    required this.baseCurrency,
    required this.current,
    required this.previous,
    required this.topBySales,
    required this.topByAmount,
    required this.byCurrency,
    this.renewals = const RenewalStats(count: 0, totalBaseMinor: 0),
    this.topPackages = const [],
    this.topCustomers = const [],
    this.cardSales = const [],
  });

  final StatsPeriod period;

  /// Every amount in this report is in this currency's minor units.
  final Currency baseCurrency;

  final PeriodStats current;

  /// The equal-length period immediately before [current].
  final PeriodStats previous;

  final List<ProductStat> topBySales;
  final List<ProductStat> topByAmount;
  final List<CurrencyTotal> byCurrency;

  /// Renewals of customer accounts in the period (zero when the accounts
  /// feature is off).
  final RenewalStats renewals;

  /// The packages those renewals sold, by number of sales.
  final List<ProductStat> topPackages;

  /// Sales per customer, the biggest first (empty when customers are off).
  final List<CustomerStat> topCustomers;

  /// Prepaid cards sold per product, with the profit where the cost is
  /// known (empty when card stock is off).
  final List<CardSaleStat> cardSales;

  Comparison get totalComparison => Comparison(
        current: current.totalBaseMinor,
        previous: previous.totalBaseMinor,
      );

  Comparison get countComparison => Comparison(
        current: current.invoiceCount,
        previous: previous.invoiceCount,
      );

  Comparison get averageComparison => Comparison(
        current: current.averageBaseMinor,
        previous: previous.averageBaseMinor,
      );

  Comparison get discountComparison => Comparison(
        current: current.discountBaseMinor,
        previous: previous.discountBaseMinor,
      );
}

final statsReportProvider = FutureProvider<StatsReport>((ref) async {
  final period = ref.watch(statsPeriodProvider);
  final base = await ref.watch(baseCurrencyProvider.future);
  final repository = ref.watch(statsRepositoryProvider);
  final range = period.range;
  final before = range.previous;

  // Aggregate queries, all on idx_invoices_created. They are independent,
  // so they go out together. The customer and renewal ones are only asked
  // for when their feature is on: a flag that is off shows nothing anywhere.
  final customerStats = Future.wait([
    accountsEnabled
        ? repository.renewals(from: range.from, to: range.to)
        : Future.value(const RenewalStats(count: 0, totalBaseMinor: 0)),
    accountsEnabled
        ? repository.topProducts(
            from: range.from,
            to: range.to,
            baseDecimals: base.decimalPlaces,
            ranking: ProductRanking.sales,
            renewalsOnly: true,
          )
        : Future.value(const <ProductStat>[]),
    customersEnabled
        ? repository.topCustomers(from: range.from, to: range.to)
        : Future.value(const <CustomerStat>[]),
    voucherStockEnabled
        ? repository.cardSales(from: range.from, to: range.to)
        : Future.value(const <CardSaleStat>[]),
  ]);
  final results = await Future.wait([
    repository.summary(
      from: range.from,
      to: range.to,
      baseDecimals: base.decimalPlaces,
    ),
    repository.summary(
      from: before.from,
      to: before.to,
      baseDecimals: base.decimalPlaces,
    ),
    repository.topProducts(
      from: range.from,
      to: range.to,
      baseDecimals: base.decimalPlaces,
      ranking: ProductRanking.sales,
    ),
    repository.topProducts(
      from: range.from,
      to: range.to,
      baseDecimals: base.decimalPlaces,
      ranking: ProductRanking.amount,
    ),
    repository.byCurrency(from: range.from, to: range.to),
  ]);

  return StatsReport(
    period: period,
    baseCurrency: base,
    current: results[0] as PeriodStats,
    previous: results[1] as PeriodStats,
    topBySales: results[2] as List<ProductStat>,
    topByAmount: results[3] as List<ProductStat>,
    byCurrency: results[4] as List<CurrencyTotal>,
    renewals: (await customerStats)[0] as RenewalStats,
    topPackages: (await customerStats)[1] as List<ProductStat>,
    topCustomers: (await customerStats)[2] as List<CustomerStat>,
    cardSales: (await customerStats)[3] as List<CardSaleStat>,
  );
});
