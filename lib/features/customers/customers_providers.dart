import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../data/repositories/customer_repository.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/product.dart';
import '../invoice/invoice_providers.dart';

/// "Now", for everything that buckets due dates. A provider so a test can
/// stand on either side of midnight.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// The "due in the next N days" setting (default 3).
final dueSoonDaysProvider = FutureProvider<int>((ref) async {
  final days = await ref
      .watch(settingsRepositoryProvider)
      .getInt(SettingsKeys.dueSoonDays, fallback: 3);
  return days < 0 ? 0 : days;
});

/// The country code phones are completed with (invoice settings).
final defaultCountryCodeProvider = FutureProvider<String>(
  (ref) => ref.watch(
    invoiceSettingsProvider
        .selectAsync((settings) => settings.defaultCountryCode),
  ),
);

/// The one quick search: customer name, phone, or card / account number.
/// Used by the home screen, the sale screen's customer picker and the
/// renewal flow, so all three always agree on what a query finds.
final quickSearchProvider = FutureProvider.autoDispose
    .family<List<CustomerHit>, String>((ref, query) async {
  final countryCode = await ref.watch(defaultCountryCodeProvider.future);
  return ref.watch(customerRepositoryProvider).quickSearch(
        query,
        includeAccounts: accountsEnabled,
        countryCode: countryCode,
      );
});

/// What the due list shows: the rows loaded so far and the size of each
/// bucket, all as seen at [now].
class DueOverview {
  const DueOverview({
    required this.hits,
    required this.counts,
    required this.now,
    required this.soonDays,
  });

  final List<CustomerHit> hits;
  final DueCounts counts;
  final DateTime now;
  final int soonDays;

  bool get hasMore => hits.length < counts.total;
}

/// The due list, longest overdue first; the argument is how many rows to
/// load. Re-read whenever an account, a customer or an invoice changes (see
/// [refreshCustomerData]).
final dueOverviewProvider =
    FutureProvider.autoDispose.family<DueOverview, int>((ref, limit) async {
  final repository = ref.watch(customerRepositoryProvider);
  final soonDays = await ref.watch(dueSoonDaysProvider.future);
  final now = ref.watch(clockProvider)();
  final counts = await repository.dueCounts(now: now, soonDays: soonDays);
  final hits = await repository.dueList(
    now: now,
    soonDays: soonDays,
    limit: limit,
  );
  return DueOverview(hits: hits, counts: counts, now: now, soonDays: soonDays);
});

/// The home screen badge: accounts overdue, due today or due soon.
final dueCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final soonDays = await ref.watch(dueSoonDaysProvider.future);
  final counts = await ref.watch(customerRepositoryProvider).dueCounts(
        now: ref.watch(clockProvider)(),
        soonDays: soonDays,
      );
  return counts.total;
});

// ---- The Customers screen ------------------------------------------------

class CustomersFilter {
  const CustomersFilter({this.query = '', this.showInactive = false});

  final String query;
  final bool showInactive;

  @override
  bool operator ==(Object other) =>
      other is CustomersFilter &&
      other.query == query &&
      other.showInactive == showInactive;

  @override
  int get hashCode => Object.hash(query, showInactive);
}

class CustomersFilterNotifier extends Notifier<CustomersFilter> {
  @override
  CustomersFilter build() => const CustomersFilter();

  void setQuery(String query) => state =
      CustomersFilter(query: query, showInactive: state.showInactive);

  void setShowInactive(bool show) =>
      state = CustomersFilter(query: state.query, showInactive: show);
}

/// Auto-dispose: the search box starts empty every time the screen opens.
final customersFilterProvider =
    NotifierProvider.autoDispose<CustomersFilterNotifier, CustomersFilter>(
  CustomersFilterNotifier.new,
);

class CustomersList {
  const CustomersList({
    required this.entries,
    required this.hasMore,
    this.loadingMore = false,
  });

  final List<CustomerListEntry> entries;
  final bool hasMore;
  final bool loadingMore;
}

/// The Customers screen's list, a page at a time by name — 5,000 customers
/// cost the same per page as 50.
class CustomersListNotifier extends AsyncNotifier<CustomersList> {
  @override
  Future<CustomersList> build() async {
    final filter = ref.watch(customersFilterProvider);
    final countryCode = await ref.watch(defaultCountryCodeProvider.future);
    final entries = await ref.read(customerRepositoryProvider).list(
          query: filter.query,
          includeInactive: filter.showInactive,
          countryCode: countryCode,
        );
    return CustomersList(
      entries: entries,
      hasMore: entries.length == CustomerRepository.pageSize,
    );
  }

  /// Appends the next page. Safe to call on every scroll event.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null ||
        !current.hasMore ||
        current.loadingMore ||
        current.entries.isEmpty) {
      return;
    }
    final filter = ref.read(customersFilterProvider);
    final repository = ref.read(customerRepositoryProvider);
    state = AsyncData(CustomersList(
      entries: current.entries,
      hasMore: true,
      loadingMore: true,
    ));
    final countryCode = await ref.read(defaultCountryCodeProvider.future);
    final next = await repository.list(
      query: filter.query,
      includeInactive: filter.showInactive,
      after: current.entries.last,
      countryCode: countryCode,
    );
    // The filter may have changed meanwhile, which rebuilt this notifier
    // from page one; appending now would mix two searches.
    if (!ref.mounted || ref.read(customersFilterProvider) != filter) return;
    state = AsyncData(CustomersList(
      entries: [...current.entries, ...next],
      hasMore: next.length == CustomerRepository.pageSize,
    ));
  }
}

final customersListProvider =
    AsyncNotifierProvider.autoDispose<CustomersListNotifier, CustomersList>(
  CustomersListNotifier.new,
);

// ---- One customer --------------------------------------------------------

final customerProvider = FutureProvider.autoDispose.family<Customer?, int>(
  (ref, id) => ref.watch(customerRepositoryProvider).getById(id),
);

/// The customer's accounts, each with its default package.
final customerAccountsProvider =
    FutureProvider.autoDispose.family<List<CustomerHit>, int>(
  (ref, id) => ref.watch(customerRepositoryProvider).accountsOf(id),
);

final customerTotalsProvider =
    FutureProvider.autoDispose.family<CustomerTotals, int>(
  (ref, id) => ref.watch(customerRepositoryProvider).totals(id),
);

/// The customer's invoices, newest first; `limit` grows with "Show more".
final customerHistoryProvider = FutureProvider.autoDispose
    .family<List<CustomerInvoice>, ({int customerId, int limit})>(
  (ref, args) => ref
      .watch(customerRepositoryProvider)
      .history(args.customerId, limit: args.limit),
);

/// Providers typed before, for the autocomplete under the provider field.
final providerSuggestionsProvider = FutureProvider.autoDispose<List<String>>(
  (ref) => ref.watch(customerRepositoryProvider).providerSuggestions(),
);

/// Active SERVICE/CARD products: what an account's default package can be.
final servicePackagesProvider = FutureProvider.autoDispose<List<Product>>(
  (ref) =>
      ref.watch(productRepositoryProvider).list(kind: ProductKind.service),
);

/// The stored renewal reminder text; '' means "the built-in default in the
/// invoice language".
final reminderTemplateProvider = FutureProvider<String>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getString(SettingsKeys.renewalReminderText),
);

/// Everything that shows customers, accounts or due dates is now stale: a
/// customer or an account was edited, or a sale was saved (a renewal moves
/// a due date, any sale adds to a customer's history).
///
/// Takes the container so it still runs when the screen that caused it has
/// already been closed.
void refreshCustomerData(ProviderContainer container) {
  container
    ..invalidate(quickSearchProvider)
    ..invalidate(dueOverviewProvider)
    ..invalidate(dueCountProvider)
    ..invalidate(customersListProvider)
    ..invalidate(customerProvider)
    ..invalidate(customerAccountsProvider)
    ..invalidate(customerTotalsProvider)
    ..invalidate(customerHistoryProvider)
    ..invalidate(providerSuggestionsProvider);
}
