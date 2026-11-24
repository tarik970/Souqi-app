import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/date_ranges.dart';
import '../../data/repositories/archive_repository.dart';

/// The archive's current filters. Changing any of them rebuilds
/// [archiveListProvider] from the first page.
class ArchiveFilterNotifier extends Notifier<ArchiveFilter> {
  @override
  ArchiveFilter build() => const ArchiveFilter();

  /// Applies a date preset, resolving it to real dates. [ArchivePeriod.all]
  /// clears the bounds; [ArchivePeriod.custom] is set by [setCustomRange].
  void setPeriod(ArchivePeriod period, {DateTime? now}) {
    final range = resolvePeriod(period, now: now);
    state = state.copyWith(
      preset: period,
      from: () => range?.from,
      to: () => range?.to,
    );
  }

  void setCustomRange(DateTime first, DateTime last) {
    final range = customRange(first, last);
    state = state.copyWith(
      preset: ArchivePeriod.custom,
      from: () => range.from,
      to: () => range.to,
    );
  }

  /// The invoice-number box. Non-numeric text is no filter at all.
  void setInvoiceNo(String text) {
    final trimmed = text.trim();
    state = state.copyWith(
      invoiceNo: () => trimmed.isEmpty ? null : int.tryParse(trimmed),
    );
  }

  void setProductQuery(String query) =>
      state = state.copyWith(productQuery: query);

  void setCustomerQuery(String query) =>
      state = state.copyWith(customerQuery: query);

  void clear() => state = const ArchiveFilter();
}

final archiveFilterProvider =
    NotifierProvider<ArchiveFilterNotifier, ArchiveFilter>(
  ArchiveFilterNotifier.new,
);

/// The rows loaded so far, and whether there are more below them.
class ArchiveList {
  const ArchiveList({
    required this.entries,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<ArchiveEntry> entries;

  /// The last page came back full, so there is probably another one.
  final bool hasMore;

  /// A page is being fetched right now (the spinner at the end of the list).
  final bool loadingMore;

  ArchiveList copyWith({
    List<ArchiveEntry>? entries,
    bool? hasMore,
    bool? loadingMore,
  }) =>
      ArchiveList(
        entries: entries ?? this.entries,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// The archive list, loaded a page at a time.
///
/// Only what has been scrolled to is in memory, and each page is fetched by
/// the key of the last row rather than an OFFSET, so an archive of 50,000
/// invoices costs the same per page as one of 50.
class ArchiveListNotifier extends AsyncNotifier<ArchiveList> {
  @override
  Future<ArchiveList> build() async {
    // Watched, not read: editing a filter starts the list again from the top.
    final filter = ref.watch(archiveFilterProvider);
    final entries =
        await ref.read(archiveRepositoryProvider).page(filter: filter);
    return ArchiveList(
      entries: entries,
      hasMore: entries.length == ArchiveRepository.pageSize,
    );
  }

  /// Appends the next page. Safe to call on every scroll event: it does
  /// nothing while a page is already in flight or the end has been reached.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.entries.isEmpty) {
      return;
    }
    final filter = ref.read(archiveFilterProvider);
    state = AsyncData(current.copyWith(loadingMore: true));
    final next = await ref.read(archiveRepositoryProvider).page(
          filter: filter,
          after: current.entries.last.cursor,
        );
    // The filter may have changed while the page was loading, which rebuilt
    // this notifier from page one; appending now would mix two searches.
    if (!ref.mounted || ref.read(archiveFilterProvider) != filter) return;
    state = AsyncData(ArchiveList(
      entries: [...current.entries, ...next],
      hasMore: next.length == ArchiveRepository.pageSize,
    ));
  }
}

final archiveListProvider =
    AsyncNotifierProvider<ArchiveListNotifier, ArchiveList>(
  ArchiveListNotifier.new,
);

/// Count and total of everything the current filter matches — what the
/// "delete these invoices" confirmation has to state before it deletes.
final archiveRangeSummaryProvider =
    FutureProvider<ArchiveRangeSummary>((ref) async {
  final filter = ref.watch(archiveFilterProvider);
  return ref.watch(archiveRepositoryProvider).summary(filter);
});

/// One invoice with its items, for the detail screen.
final archivedInvoiceProvider =
    FutureProvider.family((ref, int id) =>
        ref.watch(archiveRepositoryProvider).getById(id));
