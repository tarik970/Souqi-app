import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/utils/date_ranges.dart';
import '../../data/repositories/debt_repository.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import 'debt_actions.dart';
import 'debt_providers.dart';
import 'debt_text.dart';
import 'debt_widgets.dart';
import 'entry_form_screen.dart';
import 'opening_balances_screen.dart' show localizeCount;
import 'payment_form_screen.dart';
import 'receipt_screen.dart';

/// Which entries the ledger list shows. The running balance beside each
/// entry is always the true balance of the account, whatever is hidden.
enum LedgerTypeFilter { all, debts, payments, other }

/// The "Account" tab of a customer's page: the balance in words ("عليه" /
/// "له"), the credit limit, the last payment, what can be done (payment,
/// debt, statement, reminder) and the ledger — date, description, debit or
/// credit, running balance — filtered by date range and type.
///
/// With the "PIN to open debts" setting on, the tab is a locked door until
/// the PIN is entered.
class AccountTab extends ConsumerStatefulWidget {
  const AccountTab({super.key, required this.customer});

  final Customer customer;

  @override
  ConsumerState<AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends ConsumerState<AccountTab> {
  LedgerTypeFilter _type = LedgerTypeFilter.all;
  DateRange? _range;
  int _limit = DebtRepository.ledgerPageSize;

  /// The rows on screen stay while a longer list or another range loads.
  List<LedgerLine>? _lines;

  int get _id => widget.customer.id!;

  void _push(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final current = _range;
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
      _range = customRange(picked.start, picked.end);
      _limit = DebtRepository.ledgerPageSize;
    });
  }

  bool _shows(DebtEntry entry) => switch (_type) {
        LedgerTypeFilter.all => true,
        LedgerTypeFilter.debts => entry.type == DebtEntryType.debt ||
            entry.type == DebtEntryType.manualDebt,
        // A refund kept on the account is money in the customer's favour,
        // like a payment.
        LedgerTypeFilter.payments => entry.type == DebtEntryType.payment ||
            entry.type == DebtEntryType.saleReturn,
        LedgerTypeFilter.other => entry.type == DebtEntryType.openingBalance ||
            entry.type == DebtEntryType.adjustment ||
            entry.type == DebtEntryType.reversal,
      };

  String _typeLabel(AppLocalizations l10n, LedgerTypeFilter type) =>
      switch (type) {
        LedgerTypeFilter.all => l10n.filterAll,
        LedgerTypeFilter.debts => l10n.typeFilterDebts,
        LedgerTypeFilter.payments => l10n.typeFilterPayments,
        LedgerTypeFilter.other => l10n.typeFilterOther,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = ref.watch(baseMoneyProvider);
    final customer = widget.customer;
    final summary = ref.watch(accountSummaryProvider(_id)).value;
    final now = ref.watch(clockProvider)();
    final loaded = ref
        .watch(ledgerProvider(LedgerRequest(
          customerId: _id,
          from: _range?.from,
          to: _range?.to,
          limit: _limit,
        )))
        .value;
    if (loaded != null) _lines = loaded;
    final all = _lines;
    final hasMore = all != null && all.length > _limit;
    final lines = all == null
        ? null
        : [
            for (final line in all.take(_limit))
              if (_shows(line.entry)) line,
          ];
    final limit = customer.creditLimitBaseMinor;
    final overLimit =
        limit != null && summary != null && summary.balanceBaseMinor > limit;
    final oldest = summary?.oldestUnpaidAt;

    return ListView(
      key: const ValueKey('account-tab'),
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary != null)
                BalanceText(
                  summary.balanceBaseMinor,
                  key: const ValueKey('account-balance'),
                  style: theme.textTheme.headlineSmall,
                ),
              if (summary != null && (summary.isOverdue || overLimit))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (summary.isOverdue)
                        DebtBadge(
                          l10n.overdueAmount(money(summary.overdueBaseMinor)),
                          key: const ValueKey('account-overdue'),
                        ),
                      if (overLimit)
                        DebtBadge(
                          l10n.overLimitBadge,
                          key: const ValueKey('account-over-limit'),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              if (limit != null)
                Text(
                  '${l10n.creditLimitLabel}: ${money(limit)}',
                  key: const ValueKey('account-limit'),
                ),
              if (summary != null)
                Text(
                  summary.lastPaymentAt == null
                      ? l10n.neverPaid
                      : l10n.lastPaymentOn(
                          formatDay(summary.lastPaymentAt!, locale),
                        ),
                  key: const ValueKey('account-last-payment'),
                ),
              if (oldest != null)
                Text(
                  ageInDays(oldest, now) <= 0
                      ? l10n.oldestDebtToday
                      : l10n.oldestDebtAge(
                          localizeCount(ageInDays(oldest, now), locale),
                        ),
                  key: const ValueKey('account-oldest'),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('account-pay'),
                    onPressed: () =>
                        _push(RecordPaymentScreen(customerId: _id)),
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(l10n.recordPayment),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('account-add-debt'),
                    onPressed: () => _push(LedgerEntryFormScreen(
                      customerId: _id,
                      kind: LedgerEntryKind.manualDebt,
                    )),
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addDebt),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('account-statement'),
                    onPressed: () => _push(StatementScreen(customerId: _id)),
                    icon: const Icon(Icons.description_outlined),
                    label: Text(l10n.accountStatement),
                  ),
                  if (customer.hasPhone && (summary?.owes ?? false))
                    OutlinedButton.icon(
                      key: const ValueKey('account-remind'),
                      onPressed: () => sendDebtReminder(context, _id),
                      icon: const Icon(Icons.chat_outlined),
                      label: Text(l10n.sendDebtReminder),
                    ),
                  PopupMenuButton<LedgerEntryKind>(
                    key: const ValueKey('account-more'),
                    onSelected: (kind) => _push(
                      LedgerEntryFormScreen(customerId: _id, kind: kind),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        key: const ValueKey('account-opening'),
                        value: LedgerEntryKind.openingBalance,
                        child: Text(l10n.openingBalance),
                      ),
                      PopupMenuItem(
                        key: const ValueKey('account-adjust'),
                        value: LedgerEntryKind.adjustment,
                        child: Text(l10n.adjustment),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 24),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              for (final type in LedgerTypeFilter.values) ...[
                ChoiceChip(
                  key: ValueKey('ledger-type-${type.name}'),
                  label: Text(_typeLabel(l10n, type)),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
                const SizedBox(width: 8),
              ],
              InputChip(
                key: const ValueKey('ledger-range'),
                avatar: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _range == null
                      ? l10n.periodCustom
                      : l10n.periodRangeLabel(
                          formatDay(_range!.from, locale),
                          formatDay(
                            _range!.to.subtract(const Duration(days: 1)),
                            locale,
                          ),
                        ),
                ),
                selected: _range != null,
                onPressed: _pickRange,
                onDeleted: _range == null
                    ? null
                    : () => setState(() {
                          _range = null;
                          _limit = DebtRepository.ledgerPageSize;
                        }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        if (lines != null && lines.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              all!.isEmpty ? l10n.ledgerEmpty : l10n.ledgerNoMatch,
              key: const ValueKey('ledger-empty'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        for (final line in lines ?? const <LedgerLine>[]) ...[
          LedgerTile(
            key: ValueKey('ledger-entry-${line.entry.id}'),
            line: line,
            onTap: () => showEntrySheet(context, line),
          ),
          const Divider(height: 1),
        ],
        if (hasMore)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton(
              key: const ValueKey('ledger-more'),
              onPressed: () => setState(
                () => _limit += DebtRepository.ledgerPageSize,
              ),
              child: Text(l10n.showMore),
            ),
          ),
      ],
    );
  }
}

/// One line of the ledger: the date and what it was at the start; the amount
/// — under "debit" or "credit" — and the balance after it at the end. An
/// entry cancelled by a reversal is struck through.
class LedgerTile extends ConsumerWidget {
  const LedgerTile({super.key, required this.line, this.onTap});

  final LedgerLine line;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = ref.watch(baseMoneyProvider);
    final entry = line.entry;
    final struck = entry.isReversed;
    final amountColor = struck || entry.isReversal
        ? theme.colorScheme.outline
        : entry.isDebit
            ? theme.colorScheme.error
            : theme.colorScheme.primary;
    final note = entry.note?.trim() ?? '';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    describeEntry(l10n, entry, locale: locale),
                    style: theme.textTheme.titleSmall?.copyWith(
                      decoration: struck ? TextDecoration.lineThrough : null,
                      color: struck ? theme.colorScheme.outline : null,
                    ),
                  ),
                  Text(
                    [
                      formatDay(entry.createdAt, locale),
                      if (note.isNotEmpty) note,
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  if (struck)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: DebtBadge(l10n.entryReversed, alert: false),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entry.isDebit ? l10n.ledgerDebit : l10n.ledgerCredit} '
                    '${money.plain(entry.amountBaseMinor)}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                      decoration: struck ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    balanceInWords(
                      l10n,
                      line.balanceAfterBaseMinor,
                      money.plain,
                    ),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
