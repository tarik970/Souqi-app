import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../data/repositories/archive_repository.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';
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
    final list = ref.watch(archiveListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navArchive),
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
                // Deleting is by period. While a search is narrowing the
                // list, the action would delete something other than what
                // is on screen, so it is simply not offered.
                enabled: !filter.hasSearch,
                child: filter.hasSearch
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
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),
        ],
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

    // ONE message at the end, whatever happened.
    String message() {
      if (outcome.refused) return l10n.housekeepingBusy;
      final error = outcome.error;
      if (error != null) return l10n.archiveDeleteFailed('$error');
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
    final base = ref.watch(baseCurrencyProvider).value;
    final counting = summary == null || base == null;
    final empty = summary != null && summary.count == 0;

    return AlertDialog(
      key: const ValueKey('archive-delete-range-dialog'),
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
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
      subtitle: Text(details, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => InvoiceDetailScreen(invoiceId: entry.id),
        ),
      ),
    );
  }
}
