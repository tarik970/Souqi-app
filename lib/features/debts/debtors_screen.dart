import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/customers_providers.dart';
import 'debt_actions.dart';
import 'debt_providers.dart';
import 'debt_widgets.dart';
import 'opening_balances_screen.dart';
import 'payment_form_screen.dart';

enum DebtorSort { amount, oldestDebt, lastPayment }

enum DebtorFilter { owing, overdue, overLimit, credit }

/// The debtors of [snapshot] that pass [filter] and [query], in [sort]
/// order. Pure, so the rules are unit-tested without a screen:
///
/// - `owing` is everyone who owes; `overdue` and `overLimit` narrow that;
///   `credit` is the other side — customers the shop owes.
/// - The search matches the name or the phone, through the shared
///   normalizers ("أحمد" finds "احمد", "٠٩٤٤" finds "0944").
/// - "Oldest debt" puts the longest-unpaid first; "last payment" puts the
///   customer who has gone longest without paying first, and one who never
///   paid before all of them. Ties fall back to the larger balance, then
///   the name, so the order never jumps between two loads.
List<Debtor> arrangeDebtors(
  DebtorsSnapshot snapshot, {
  DebtorSort sort = DebtorSort.amount,
  DebtorFilter filter = DebtorFilter.owing,
  String query = '',
  String countryCode = '963',
}) {
  final name = normalizeName(query);
  final phone = phoneSearchKey(query, countryCode: countryCode);
  bool matches(Debtor d) {
    if (query.trim().isEmpty) return true;
    if (name.isNotEmpty && d.nameNorm.contains(name)) return true;
    if (phone.isNotEmpty && (d.phoneNorm ?? '').contains(phone)) return true;
    return false;
  }

  bool passes(Debtor d) => switch (filter) {
        DebtorFilter.owing => d.balanceBaseMinor > 0,
        DebtorFilter.overdue => d.account.isOverdue,
        DebtorFilter.overLimit => d.isOverLimit,
        DebtorFilter.credit => d.balanceBaseMinor < 0,
      };

  int byAmount(Debtor a, Debtor b) {
    final amount =
        b.balanceBaseMinor.abs().compareTo(a.balanceBaseMinor.abs());
    return amount != 0 ? amount : a.nameNorm.compareTo(b.nameNorm);
  }

  int byDate(DateTime? a, DateTime? b, {required bool nullFirst}) {
    if (a == null && b == null) return 0;
    if (a == null) return nullFirst ? -1 : 1;
    if (b == null) return nullFirst ? 1 : -1;
    return a.compareTo(b);
  }

  final list = [
    for (final debtor in snapshot.debtors)
      if (passes(debtor) && matches(debtor)) debtor,
  ];
  list.sort((a, b) {
    final first = switch (sort) {
      DebtorSort.amount => 0,
      DebtorSort.oldestDebt => byDate(
          a.account.oldestUnpaidAt,
          b.account.oldestUnpaidAt,
          nullFirst: false,
        ),
      DebtorSort.lastPayment => byDate(
          a.account.lastPaymentAt,
          b.account.lastPaymentAt,
          nullFirst: true,
        ),
    };
    return first != 0 ? first : byAmount(a, b);
  });
  return list;
}

/// Opens the debtors list — through the PIN when the "PIN to open debts"
/// setting is on.
Future<void> openDebtors(BuildContext context) async {
  final navigator = Navigator.of(context);
  if (!await requireDebtAccess(context)) return;
  if (!navigator.mounted) return;
  await navigator.push(
    MaterialPageRoute<void>(builder: (_) => const DebtorsScreen()),
  );
}

/// The debtors list ("المدينون"): the total outstanding and the aging
/// summary on top; under them every customer with a balance — what they
/// owe, how old their oldest unpaid debt is, when they last paid, whether
/// they are overdue — sortable, filterable, searchable, with "record
/// payment" and "remind on WhatsApp" on every row.
///
/// One snapshot of the ledger ([debtorsProvider]) is arranged in memory, so
/// typing in the search or changing the sort never goes back to the
/// database.
class DebtorsScreen extends ConsumerStatefulWidget {
  const DebtorsScreen({super.key});

  @override
  ConsumerState<DebtorsScreen> createState() => _DebtorsScreenState();
}

class _DebtorsScreenState extends ConsumerState<DebtorsScreen> {
  // Owned by this page for its whole life.
  final _search = TextEditingController();
  DebtorSort _sort = DebtorSort.amount;
  DebtorFilter _filter = DebtorFilter.owing;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _sortLabel(AppLocalizations l10n, DebtorSort sort) => switch (sort) {
        DebtorSort.amount => l10n.sortByAmount,
        DebtorSort.oldestDebt => l10n.sortByOldest,
        DebtorSort.lastPayment => l10n.sortByLastPayment,
      };

  String _filterLabel(AppLocalizations l10n, DebtorFilter filter) =>
      switch (filter) {
        DebtorFilter.owing => l10n.filterAll,
        DebtorFilter.overdue => l10n.filterOverdue,
        DebtorFilter.overLimit => l10n.filterOverLimit,
        DebtorFilter.credit => l10n.filterCreditBalances,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final snapshot = ref.watch(debtorsProvider);
    final countryCode = ref.watch(defaultCountryCodeProvider).value ?? '963';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.debtorsTitle),
        actions: [
          IconButton(
            key: const ValueKey('debtors-opening-balances'),
            tooltip: l10n.openingBalancesTitle,
            icon: const Icon(Icons.playlist_add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const OpeningBalancesScreen(),
              ),
            ),
          ),
        ],
      ),
      body: DebtLockGate(
        child: snapshot.when(
          // A payment recorded from a row reloads the snapshot: keep the
          // list on screen, not a spinner.
          skipLoadingOnReload: true,
          skipLoadingOnRefresh: true,
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Center(child: Text('$e')),
          data: (data) {
            final debtors = arrangeDebtors(
              data,
              sort: _sort,
              filter: _filter,
              query: _search.text,
              countryCode: countryCode,
            );
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: TextField(
                    key: const ValueKey('debtors-search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: l10n.searchCustomersHint,
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _search.clear()),
                            ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    key: const ValueKey('debtors-list'),
                    padding: const EdgeInsets.only(bottom: 32),
                    // The summary scrolls away with the list: on a small
                    // phone with the keyboard up, the rows need the room.
                    itemCount: debtors.length + 2,
                    itemBuilder: (context, index) {
                      if (index == 0) return _summary(l10n, theme, data);
                      if (index == debtors.length + 1) {
                        return debtors.isNotEmpty
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.all(32),
                                child: Text(
                                  data.debtors.isEmpty
                                      ? l10n.debtorsEmpty
                                      : l10n.debtorsNoMatch,
                                  key: const ValueKey('debtors-empty'),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              );
                      }
                      final debtor = debtors[index - 1];
                      return DebtorTile(
                        key: ValueKey('debtor-${debtor.customerId}'),
                        debtor: debtor,
                        at: data.at,
                        locale: locale,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(
    AppLocalizations l10n,
    ThemeData theme,
    DebtorsSnapshot data,
  ) {
    final money = ref.watch(baseMoneyProvider);
    final locale = ref.watch(appLocaleProvider).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.debtorsTotalOutstanding,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  money(data.totalOutstandingBaseMinor),
                  key: const ValueKey('debtors-total'),
                  maxLines: 1,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
              Text(
                l10n.debtorsOwingCount(
                  localizeCount(data.owingCount, locale),
                ),
                key: const ValueKey('debtors-count'),
              ),
              if (data.totalCreditBaseMinor > 0)
                Text(
                  l10n.debtorsCreditTotal(money(data.totalCreditBaseMinor)),
                  key: const ValueKey('debtors-credit-total'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.agingTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                  AgingGrid(aging: data.aging),
                ],
              ),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              for (final filter in DebtorFilter.values) ...[
                ChoiceChip(
                  key: ValueKey('debtors-filter-${filter.name}'),
                  label: Text(_filterLabel(l10n, filter)),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Text('${l10n.sortLabel}: ', style: theme.textTheme.bodySmall),
              Expanded(
                child: DropdownButton<DebtorSort>(
                  key: const ValueKey('debtors-sort'),
                  value: _sort,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final sort in DebtorSort.values)
                      DropdownMenuItem(
                        value: sort,
                        child: Text(
                          _sortLabel(l10n, sort),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (sort) {
                    if (sort != null) setState(() => _sort = sort);
                  },
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}

/// One customer of the debtors list.
class DebtorTile extends ConsumerWidget {
  const DebtorTile({
    super.key,
    required this.debtor,
    required this.at,
    required this.locale,
  });

  final Debtor debtor;

  /// The moment the snapshot measured ages at.
  final DateTime at;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final account = debtor.account;
    final oldest = account.oldestUnpaidAt;
    final age = oldest == null ? null : ageInDays(oldest, at);
    final small =
        theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline);

    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => CustomerDetailScreen(
          customerId: debtor.customerId,
          initialTab: CustomerTab.account,
        ),
      )),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 10, 8, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    debtor.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: BalanceText(
                      debtor.balanceBaseMinor,
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 2, end: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (account.isOverdue) DebtBadge(l10n.overdueBadge),
                  if (debtor.isOverLimit) DebtBadge(l10n.overLimitBadge),
                  if (!debtor.isActive)
                    DebtBadge(l10n.inactiveBadge, alert: false),
                  if (age != null)
                    Text(
                      age <= 0
                          ? l10n.oldestDebtToday
                          : l10n.oldestDebtAge(localizeCount(age, locale)),
                      style: small,
                    ),
                  Text(
                    account.lastPaymentAt == null
                        ? l10n.neverPaid
                        : l10n.lastPaymentOn(
                            formatDay(account.lastPaymentAt!, locale),
                          ),
                    style: small,
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: ValueKey('debtor-pay-${debtor.customerId}'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RecordPaymentScreen(customerId: debtor.customerId),
                    ),
                  ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: Text(l10n.recordPayment),
                ),
                if (debtor.phone != null && debtor.balanceBaseMinor > 0)
                  TextButton.icon(
                    key: ValueKey('debtor-remind-${debtor.customerId}'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () =>
                        sendDebtReminder(context, debtor.customerId),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: Text(l10n.sendDebtReminder),
                  ),
              ],
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}
