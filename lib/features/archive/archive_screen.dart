import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/on_open_and_resume.dart';
import '../../core/logging/error_log.dart';
import '../../core/widgets/load_error_view.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../data/repositories/archive_repository.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice_return.dart';
import '../../l10n/generated/app_localizations.dart';
import '../debts/debt_providers.dart';
import '../debts/debt_widgets.dart';
import '../returns/returns_providers.dart';
import '../security/admin_lock.dart';
import '../settings/storage_providers.dart';
import 'archive_providers.dart';
import 'invoice_detail_screen.dart';

/// Which of the three text filters the one search box is driving.
enum _SearchTarget { product, customer, invoiceNo }

/// The invoice archive: newest first, filtered, loaded a page at a time.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  // This screen owns the controller for its whole life, so nothing can
  // rebuild on a disposed one.
  final _search = TextEditingController();
  _SearchTarget _target = _SearchTarget.product;

  @override
  void initState() {
    super.initState();
    // The filter outlives this screen: the box comes back with what the
    // list is still narrowed by, not empty.
    final filter = ref.read(archiveFilterProvider);
    if (filter.customerQuery.isNotEmpty) {
      _target = _SearchTarget.customer;
      _search.text = filter.customerQuery;
    } else if (filter.invoiceNo != null) {
      _target = _SearchTarget.invoiceNo;
      _search.text = '${filter.invoiceNo}';
    } else {
      _search.text = filter.productQuery;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// One box, one filter: switching the target clears the other two, so what
  /// is on screen is always exactly what is being searched.
  void _applySearch(String text) {
    final filter = ref.read(archiveFilterProvider.notifier);
    filter.setProductQuery(_target == _SearchTarget.product ? text : '');
    filter.setCustomerQuery(_target == _SearchTarget.customer ? text : '');
    filter.setInvoiceNo(_target == _SearchTarget.invoiceNo ? text : '');
  }

  void _setTarget(_SearchTarget target) {
    setState(() => _target = target);
    _applySearch(_search.text);
  }

  String _searchHint(AppLocalizations l10n) => switch (_target) {
        _SearchTarget.product => l10n.archiveSearchProductHint,
        _SearchTarget.customer => l10n.archiveSearchCustomerHint,
        _SearchTarget.invoiceNo => l10n.archiveInvoiceNoHint,
      };

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null || !mounted) return;
    ref
        .read(archiveFilterProvider.notifier)
        .setCustomRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(archiveFilterProvider);
    final returns = filter.status == ArchiveStatus.returns;
    // Not read while the return documents are what is listed.
    final list = returns
        ? const AsyncLoading<ArchiveList>()
        : ref.watch(archiveListProvider);

    // Behind the PIN when "PIN to open settings, archive and statistics" is
    // on (see AdminLockGate); with it off the gate is not there at all.
    return AdminLockGate(
      title: l10n.navArchive,
      child: Scaffold(
      appBar: AppBar(
        // "Today" follows the day: see refreshRelativePeriod.
        title: OnOpenAndResume(
          action: () => ref
              .read(archiveFilterProvider.notifier)
              .refreshRelativePeriod(),
          child: Text(l10n.navArchive),
        ),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                child: Text(l10n.archiveClearFilters),
                onTap: () {
                  _search.clear();
                  ref.read(archiveFilterProvider.notifier).clear();
                },
              ),
              PopupMenuItem<void>(
                key: const ValueKey('archive-delete-range'),
                // Deleting is by period. While a search — or the "Voided" /
                // "Returns" filter — is narrowing the list, the action would
                // delete something other than what is on screen, so it is
                // simply not offered.
                enabled: !filter.isNarrowed,
                child: filter.isNarrowed
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.archiveDeleteRange),
                          Text(
                            l10n.archiveDeleteNeedsNoSearch,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      )
                    : Text(l10n.archiveDeleteRange),
                // The dialog must not open inside onTap (the menu is still
                // closing); a post-frame callback is the documented way.
                onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _confirmDeleteRange(),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _PeriodBar(
            selected: filter.preset,
            onSelected: (period) {
              if (period == ArchivePeriod.custom) {
                _pickCustomRange();
                return;
              }
              ref.read(archiveFilterProvider.notifier).setPeriod(period);
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('archive-search'),
                    controller: _search,
                    keyboardType: _target == _SearchTarget.invoiceNo
                        ? TextInputType.number
                        : TextInputType.text,
                    decoration: InputDecoration(
                      hintText: _searchHint(l10n),
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                    onChanged: _applySearch,
                  ),
                ),
                PopupMenuButton<_SearchTarget>(
                  key: const ValueKey('archive-search-target'),
                  icon: const Icon(Icons.filter_list),
                  tooltip: l10n.archiveFilters,
                  initialValue: _target,
                  onSelected: _setTarget,
                  itemBuilder: (context) => [
                    CheckedPopupMenuItem(
                      value: _SearchTarget.product,
                      checked: _target == _SearchTarget.product,
                      child: Text(l10n.archiveSearchProductHint),
                    ),
                    CheckedPopupMenuItem(
                      value: _SearchTarget.customer,
                      checked: _target == _SearchTarget.customer,
                      child: Text(l10n.archiveSearchCustomerHint),
                    ),
                    CheckedPopupMenuItem(
                      value: _SearchTarget.invoiceNo,
                      checked: _target == _SearchTarget.invoiceNo,
                      child: Text(l10n.archiveInvoiceNoHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _StatusBar(
            selected: filter.status,
            onSelected: (status) =>
                ref.read(archiveFilterProvider.notifier).setStatus(status),
          ),
          // "Returns" lists the return documents of the period, not its
          // invoices; everything else lists invoices.
          if (returns) ...[
            const _ReturnsSummary(),
            const Expanded(child: _ReturnsList()),
          ] else ...[
            const _MatchSummary(),
            Expanded(
              child: list.when(
                data: (data) => data.entries.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(
                            filter.isEmpty
                                ? l10n.archiveNoInvoices
                                : l10n.archiveNoMatches,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : _InvoiceList(data: data),
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, stack) => LoadErrorView(e, stack),
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// Deletes every invoice the current filter matches.
  ///
  /// The confirmation opens on THIS frame and counts inside itself: on a
  /// 50,000-invoice archive the count took seconds, the app looked frozen,
  /// and an impatient second tap started a second delete. Nothing is
  /// awaited before the dialog is on screen any more, and the lock in
  /// [HousekeepingController] turns the second tap away.
  Future<void> _confirmDeleteRange() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final locale = ref.read(appLocaleProvider).languageCode;
    // The PERIOD, and nothing else: not the search box, and not the ids the
    // list happens to hold. The same object is counted and then deleted.
    final criteria = ref.read(archiveFilterProvider).datesOnly;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteConfirmDialog(filter: criteria),
    );
    if (confirmed != true || !mounted) return;

    // Blocking and un-dismissable: it closes itself when the job leaves the
    // deleting phase.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DeletingDialog(),
    );
    final outcome = await container
        .read(housekeepingProvider.notifier)
        .deleteMatching(criteria);
    // The debts of the deleted invoices stay; only their link to the
    // invoice is gone, and the ledger on screen should say so.
    refreshDebtData(container);
    container.invalidate(deleteDebtCountProvider);

    // ONE message at the end, whatever happened.
    String message() {
      if (outcome.refused) return l10n.housekeepingBusy;
      final error = outcome.error;
      if (error != null) {
        // The technical text goes to the error log, not into the sentence.
        reportError(error, null, context: 'archive delete');
        return l10n.archiveDeleteFailed(l10n.errorSeeLog);
      }
      if (outcome.remaining > 0) {
        return l10n.archiveDeletePartial(
          formatMinor(outcome.deleted, decimals: 0, locale: locale),
          formatMinor(outcome.remaining, decimals: 0, locale: locale),
        );
      }
      return l10n.archiveDeletedMessage(
        formatMinor(outcome.deleted, decimals: 0, locale: locale),
      );
    }

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message())));
  }
}

/// "Delete these invoices?" — open at once, with the count and total filling
/// in when the aggregate comes back.
///
/// Delete stays disabled until the figures are there, so nobody can confirm
/// a deletion whose size they have not been told.
class _DeleteConfirmDialog extends ConsumerWidget {
  const _DeleteConfirmDialog({required this.filter});

  final ArchiveFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    // One SQL aggregate over the created_at index, asked for THESE criteria
    // — the very ones the delete is about to be given.
    final summary = ref.watch(deleteSummaryProvider(filter)).value;
    final withDebt = ref.watch(deleteDebtCountProvider(filter)).value;
    final base = ref.watch(baseCurrencyProvider).value;
    // Delete waits for both figures: nobody confirms a deletion without
    // having been told how many of its invoices carry debts.
    final counting = summary == null || base == null || withDebt == null;
    final empty = summary != null && summary.count == 0;

    return AlertDialog(
      key: const ValueKey('archive-delete-range-dialog'),
      // Scrolls: on a small phone at a large font the three paragraphs are
      // taller than the dialog.
      scrollable: true,
      title: Text(l10n.archiveDeleteRangeTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (counting)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(l10n.archiveCounting),
              ],
            )
          else if (empty)
            Text(l10n.archiveDeleteRangeEmpty)
          else ...[
            Text(l10n.archiveDeleteRangeMessage(
              formatMinor(summary.count, decimals: 0, locale: locale),
              formatMinor(
                summary.totalBaseMinor,
                decimals: base.decimalPlaces,
                locale: locale,
                symbol: base.symbol.isEmpty ? base.code : base.symbol,
              ),
            )),
            // Debts are never deleted with their invoices: say how many of
            // these carry one, and that it stays.
            if (withDebt > 0) ...[
              const SizedBox(height: 12),
              Text(
                l10n.deleteCarriesDebt(
                  formatMinor(withDebt, decimals: 0, locale: locale),
                ),
                key: const ValueKey('archive-delete-debt-note'),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
            // Deleting "everything" must never happen by accident.
            if (filter.from == null && filter.to == null) ...[
              const SizedBox(height: 12),
              Text(
                l10n.archiveDeleteWholeArchive,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: counting || empty
              ? null
              : () => Navigator.of(context).pop(true),
          child: Text(l10n.delete),
        ),
      ],
    );
  }
}

/// "Deleting invoices — 12,000 of 50,000", with a progress bar.
///
/// Blocks the back button and the barrier while it is up, so nothing can be
/// navigated away from or started twice mid-delete, and pops itself as soon
/// as the job leaves the deleting phase (a VACUUM carries on behind the
/// "optimizing…" pill, which the seller may walk away from).
class DeletingDialog extends ConsumerStatefulWidget {
  const DeletingDialog({super.key});

  @override
  ConsumerState<DeletingDialog> createState() => _DeletingDialogState();
}

class _DeletingDialogState extends ConsumerState<DeletingDialog> {
  bool _popped = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final state = ref.watch(housekeepingProvider);

    if (!state.deleting && !_popped) {
      // Done (or it never started, on an archive small enough to finish
      // inside one frame). Pop after this build, never during it.
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }

    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('archive-deleting-dialog'),
        title: Text(l10n.archiveDeletingTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              state.total <= 0
                  ? l10n.archiveCounting
                  : l10n.progressCount(
                      formatMinor(state.done, decimals: 0, locale: locale),
                      formatMinor(state.total, decimals: 0, locale: locale),
                    ),
              key: const ValueKey('archive-deleting-progress'),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: state.progress),
            const SizedBox(height: 12),
            Text(
              l10n.archiveDeletingHint,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// The date presets. Horizontally scrollable: six chips do not fit the width
/// of a small phone, in either direction.
class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.selected, required this.onSelected});

  final ArchivePeriod selected;
  final ValueChanged<ArchivePeriod> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(ArchivePeriod period) => switch (period) {
          ArchivePeriod.all => l10n.periodAll,
          ArchivePeriod.today => l10n.periodToday,
          ArchivePeriod.yesterday => l10n.periodYesterday,
          ArchivePeriod.thisWeek => l10n.periodThisWeek,
          ArchivePeriod.thisMonth => l10n.periodThisMonth,
          ArchivePeriod.custom => l10n.periodCustom,
        };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          for (final period in ArchivePeriod.values) ...[
            if (period != ArchivePeriod.values.first) const SizedBox(width: 8),
            ChoiceChip(
              key: ValueKey('archive-period-${period.name}'),
              label: Text(label(period)),
              selected: selected == period,
              onSelected: (_) => onSelected(period),
            ),
          ],
        ],
      ),
    );
  }
}

/// All / Voided / Returns. Horizontally scrollable, like the periods.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.selected, required this.onSelected});

  final ArchiveStatus selected;
  final ValueChanged<ArchiveStatus> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(ArchiveStatus status) => switch (status) {
          ArchiveStatus.all => l10n.archiveStatusAll,
          ArchiveStatus.voided => l10n.archiveStatusVoided,
          ArchiveStatus.returns => l10n.returnsTitle,
        };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Row(
        children: [
          for (final status in ArchiveStatus.values) ...[
            if (status != ArchiveStatus.values.first) const SizedBox(width: 8),
            ChoiceChip(
              key: ValueKey('archive-status-${status.name}'),
              label: Text(label(status)),
              selected: selected == status,
              onSelected: (_) => onSelected(status),
            ),
          ],
        ],
      ),
    );
  }
}

/// "3 returns · 12,000 SYP given back" for the period and the search.
class _ReturnsSummary extends ConsumerWidget {
  const _ReturnsSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final summary = ref.watch(archiveReturnsSummaryProvider).value;
    final base = ref.watch(baseCurrencyProvider).value;
    if (summary == null || base == null || summary.count == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          key: const ValueKey('archive-returns-summary'),
          l10n.archiveReturnsCount(
            formatMinor(summary.count, decimals: 0, locale: locale),
            formatMinor(
              summary.totalBaseMinor,
              decimals: base.decimalPlaces,
              locale: locale,
              symbol: base.symbol.isEmpty ? base.code : base.symbol,
            ),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

/// The return documents of the period, newest first; "Show more" loads the
/// next ones.
class _ReturnsList extends ConsumerStatefulWidget {
  const _ReturnsList();

  @override
  ConsumerState<_ReturnsList> createState() => _ReturnsListState();
}

class _ReturnsListState extends ConsumerState<_ReturnsList> {
  /// The rows on screen stay while a longer list loads.
  List<InvoiceReturn>? _rows;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final loaded = ref.watch(archiveReturnsProvider);
    final limit = ref.watch(archiveReturnsLimitProvider);
    if (loaded.hasError && loaded.value == null) {
      return LoadErrorView(loaded.error!, loaded.stackTrace);
    }
    if (loaded.value != null) _rows = loaded.value;
    final rows = _rows;
    if (rows == null) return const SizedBox.shrink();
    if (rows.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.archiveNoReturns,
            key: const ValueKey('archive-no-returns'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final more = rows.length >= limit;
    return ListView.separated(
      key: const ValueKey('archive-returns-list'),
      itemCount: rows.length + (more ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= rows.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton(
              key: const ValueKey('archive-returns-more'),
              onPressed: () =>
                  ref.read(archiveReturnsLimitProvider.notifier).more(),
              child: Text(l10n.showMore),
            ),
          );
        }
        return ReturnTile(document: rows[index], showInvoice: true);
      },
    );
  }
}

/// "12 invoices · 148,000 SYP" for whatever the filters currently match.
class _MatchSummary extends ConsumerWidget {
  const _MatchSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final summary = ref.watch(archiveRangeSummaryProvider).value;
    final base = ref.watch(baseCurrencyProvider).value;
    if (summary == null || base == null || summary.count == 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          key: const ValueKey('archive-match-summary'),
          l10n.archiveMatchCount(
            formatMinor(summary.count, decimals: 0, locale: locale),
            formatMinor(
              summary.totalBaseMinor,
              decimals: base.decimalPlaces,
              locale: locale,
              symbol: base.symbol.isEmpty ? base.code : base.symbol,
            ),
          ),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class _InvoiceList extends ConsumerWidget {
  const _InvoiceList({required this.data});

  final ArchiveList data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = data.entries;
    return ListView.separated(
      key: const ValueKey('archive-list'),
      itemCount: entries.length + (data.hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (index >= entries.length) {
          // The sentinel row at the end: asking for the next page while it
          // is still a few rows away keeps the scroll from ever stopping.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            ref.read(archiveListProvider.notifier).loadMore();
          });
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return _InvoiceTile(entry: entries[index]);
      },
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  const _InvoiceTile({required this.entry});

  final ArchiveEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final currencies = ref.watch(currenciesProvider).value ?? const <Currency>[];
    final currency =
        currencies.where((c) => c.code == entry.currencyCode).firstOrNull;

    final total = formatMinor(
      entry.totalMinor,
      decimals: currency?.decimalPlaces ?? 0,
      locale: locale,
      symbol: currency == null || currency.symbol.isEmpty
          ? entry.currencyCode
          : currency.symbol,
    );
    final customer = entry.customerName?.trim() ?? '';
    final details = [
      DateFormat.yMd(locale).add_jm().format(entry.createdAt.toLocal()),
      l10n.archiveItemsLabel(
        formatMinor(entry.itemCount, decimals: 0, locale: locale),
      ),
      if (customer.isNotEmpty) customer,
    ].join(' · ');

    return ListTile(
      key: ValueKey('archive-invoice-${entry.invoiceNo}'),
      title: Row(
        children: [
          Expanded(
            child: Text(
              l10n.invoiceNoLabel(
                formatMinor(entry.invoiceNo, decimals: 0, locale: locale),
              ),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Text(
            total,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              // A voided total is money that was not made.
              color: entry.isVoided
                  ? theme.colorScheme.outline
                  : theme.colorScheme.primary,
              decoration: entry.isVoided ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (entry.isVoided || entry.returnCount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  if (entry.isVoided)
                    DebtBadge(
                      l10n.invoiceVoidMark,
                      key: ValueKey('archive-void-${entry.invoiceNo}'),
                    ),
                  if (entry.returnCount > 0)
                    DebtBadge(
                      l10n.archiveHasReturns,
                      key: ValueKey('archive-returned-${entry.invoiceNo}'),
                      alert: false,
                    ),
                ],
              ),
            ),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: entry.id),
        ),
      ),
    );
  }
}
