import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/load_error_view.dart';
import '../../core/providers.dart';
import '../../core/utils/date_ranges.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';
import 'debt_output.dart';
import 'debt_papers.dart';
import 'debt_providers.dart';
import 'debt_widgets.dart';

/// The receipt of a payment as a [LedgerPaper].
LedgerPaper receiptPaper(ReceiptData data) => LedgerPaper(
      fileName: 'receipt-${data.payment.receiptNo ?? data.payment.id}',
      caption: (l10n) => l10n.receiptNoLabel('${data.payment.receiptNo ?? ''}'),
      customerPhone: data.customerPhone,
      build: (c, {padding, required copy}) => ReceiptView(
        receipt: data,
        settings: c.settings,
        currencies: c.currencies,
        logo: c.logo,
        isCopy: copy,
        padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
      ),
    );

/// An account statement as a [LedgerPaper].
LedgerPaper statementPaper(StatementData data, {required int customerId}) {
  final at = data.printedAt.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return LedgerPaper(
    fileName:
        'statement-$customerId-${at.year}${two(at.month)}${two(at.day)}',
    caption: (l10n) => '${l10n.accountStatement} — ${data.customerName}',
    customerPhone: data.customerPhone,
    build: (c, {padding, required copy}) => StatementView(
      data: data,
      settings: c.settings,
      currencies: c.currencies,
      logo: c.logo,
      isCopy: copy,
      padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
    ),
  );
}

/// What the receipt of payment [entryId] prints; null when there is no such
/// payment.
final receiptDataProvider =
    FutureProvider.autoDispose.family<ReceiptData?, int>((ref, entryId) async {
  // A receipt changes when its payment is reversed.
  ref.watch(ledgerRevisionProvider);
  final entry = await ref.watch(debtRepositoryProvider).entryById(entryId);
  if (entry == null || entry.type != DebtEntryType.payment) return null;
  final customer =
      await ref.watch(customerRepositoryProvider).getById(entry.customerId);
  final baseCode = await ref.watch(baseCurrencyCodeProvider.future);
  return ReceiptData(
    payment: entry,
    customerName: customer?.name ?? '',
    customerPhone: customer?.phone,
    baseCurrencyCode: baseCode,
  );
});

/// A payment receipt ("سند قبض"): the paper exactly as it prints, with
/// Print / Share / WhatsApp / Save above it.
///
/// [copy] is false right after the payment was recorded — that output is the
/// original — and true when the receipt is opened again from the ledger:
/// every output then carries the "COPY / نسخة" mark.
class ReceiptScreen extends ConsumerWidget {
  const ReceiptScreen({super.key, required this.entryId, this.copy = false});

  final int entryId;
  final bool copy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(receiptDataProvider(entryId));
    final render = ref.watch(invoiceRenderContextProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.receiptTitle)),
      body: DebtLockGate(
        child: data.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, stack) => LoadErrorView(e, stack),
        data: (receipt) {
          if (receipt == null) {
            return Center(child: Text(l10n.ledgerEmpty));
          }
          final paper = receiptPaper(receipt);
          return ListView(
            key: const ValueKey('receipt-screen'),
            padding: const EdgeInsets.all(16),
            children: [
              PaperActions(paper: paper, copy: copy),
              const SizedBox(height: 16),
              if (render != null)
                LedgerPaperPreview(
                  key: const ValueKey('receipt-preview'),
                  paper: paper,
                  context_: render,
                  copy: copy,
                ),
            ],
          );
        },
        ),
      ),
    );
  }
}

/// The range a statement covers.
enum StatementPeriod { thisMonth, last30, all, custom }

/// What a statement screen is asking for.
class StatementRequest {
  const StatementRequest({required this.customerId, this.from, this.to});

  final int customerId;
  final DateTime? from;
  final DateTime? to;

  @override
  bool operator ==(Object other) =>
      other is StatementRequest &&
      other.customerId == customerId &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(customerId, from, to);
}

final statementDataProvider = FutureProvider.autoDispose
    .family<StatementData?, StatementRequest>((ref, request) async {
  // A payment recorded while the statement is open belongs on it.
  ref.watch(ledgerRevisionProvider);
  final customer =
      await ref.watch(customerRepositoryProvider).getById(request.customerId);
  if (customer == null) return null;
  final statement = await ref.watch(debtRepositoryProvider).statement(
        request.customerId,
        from: request.from,
        to: request.to,
      );
  return StatementData(
    statement: statement,
    customerName: customer.name,
    customerPhone: customer.phone,
    baseCurrencyCode: await ref.watch(baseCurrencyCodeProvider.future),
    printedAt: DateTime.now(),
  );
});

/// An account statement ("كشف حساب"): pick a date range, see the paper —
/// balance brought forward, every entry with its running balance, totals,
/// closing balance — and print it, share it or send it to the customer.
class StatementScreen extends ConsumerStatefulWidget {
  const StatementScreen({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<StatementScreen> createState() => _StatementScreenState();
}

class _StatementScreenState extends ConsumerState<StatementScreen> {
  StatementPeriod _period = StatementPeriod.thisMonth;
  DateRange? _custom;

  StatementRequest get _request {
    final now = DateTime.now();
    final tomorrow = startOfDay(now).add(const Duration(days: 1));
    final (from, to) = switch (_period) {
      StatementPeriod.thisMonth => (startOfMonth(now), tomorrow),
      StatementPeriod.last30 => (
          DateTime(now.year, now.month, now.day - 29),
          tomorrow,
        ),
      StatementPeriod.all => (null, null),
      StatementPeriod.custom => (_custom?.from, _custom?.to),
    };
    return StatementRequest(
      customerId: widget.customerId,
      from: from,
      to: to,
    );
  }

  Future<void> _select(StatementPeriod period) async {
    if (period != StatementPeriod.custom) {
      setState(() => _period = period);
      return;
    }
    final now = DateTime.now();
    final current = _custom;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 1),
      initialDateRange: current == null
          ? null
          : DateTimeRange(
              start: current.from,
              end: current.to.subtract(const Duration(days: 1)),
            ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _custom = customRange(picked.start, picked.end);
      _period = StatementPeriod.custom;
    });
  }

  String _label(AppLocalizations l10n, StatementPeriod period) =>
      switch (period) {
        StatementPeriod.thisMonth => l10n.periodThisMonth,
        StatementPeriod.last30 => l10n.statementLast30,
        StatementPeriod.all => l10n.statementWholeAccount,
        StatementPeriod.custom => l10n.periodCustom,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final data = ref.watch(statementDataProvider(_request));
    final render = ref.watch(invoiceRenderContextProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountStatement)),
      body: DebtLockGate(
        child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final period in StatementPeriod.values) ...[
                  if (period != StatementPeriod.values.first)
                    const SizedBox(width: 8),
                  ChoiceChip(
                    key: ValueKey('statement-period-${period.name}'),
                    label: Text(_label(l10n, period)),
                    selected: _period == period,
                    onSelected: (_) => _select(period),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: data.when(
              skipLoadingOnReload: true,
              loading: () => const SizedBox.shrink(),
              error: (e, stack) => LoadErrorView(e, stack),
              data: (statement) {
                if (statement == null) {
                  return Center(child: Text(l10n.customerNotFound));
                }
                final paper =
                    statementPaper(statement, customerId: widget.customerId);
                return ListView(
                  key: const ValueKey('statement-screen'),
                  padding: const EdgeInsets.all(16),
                  children: [
                    PaperActions(paper: paper),
                    const SizedBox(height: 16),
                    if (render != null)
                      LedgerPaperPreview(
                        key: const ValueKey('statement-preview'),
                        paper: paper,
                        context_: render,
                      ),
                  ],
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }
}
