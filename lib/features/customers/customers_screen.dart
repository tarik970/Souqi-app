import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/utils/bidi.dart';
import '../../data/repositories/customer_repository.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';
import 'customers_providers.dart';

/// The customer list: search by name or phone, add, open one.
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  // This screen owns the controller for its whole life, so nothing can
  // rebuild on a disposed one.
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(int customerId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CustomerDetailScreen(customerId: customerId),
    ));
  }

  Future<void> _add() async {
    final created = await Navigator.of(context).push(
      MaterialPageRoute<SaleCustomer>(
        builder: (_) => const CustomerFormScreen(),
      ),
    );
    // Straight to the new customer's page: that is where the rest of the
    // account (package, renewal period) is filled in.
    if (!mounted || created == null) return;
    _open(created.customerId);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final filter = ref.watch(customersFilterProvider);
    final list = ref.watch(customersListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navCustomers),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              CheckedPopupMenuItem<void>(
                checked: filter.showInactive,
                child: Text(l10n.showInactive),
                onTap: () => ref
                    .read(customersFilterProvider.notifier)
                    .setShowInactive(!filter.showInactive),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              key: const ValueKey('customers-search-field'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.searchCustomersHint,
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              onChanged: ref.read(customersFilterProvider.notifier).setQuery,
            ),
          ),
          Expanded(
            child: list.when(
              // Keep the list on screen between keystrokes.
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Center(child: Text('$e')),
              data: (data) => data.entries.isEmpty
                  ? Center(
                      // Scrollable: with the keyboard up there is hardly
                      // any room left here.
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          filter.query.trim().isEmpty
                              ? l10n.noCustomers
                              : l10n.quickSearchEmpty(filter.query.trim()),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification.metrics.extentAfter < 400) {
                          ref.read(customersListProvider.notifier).loadMore();
                        }
                        return false;
                      },
                      child: ListView.builder(
                        // Room for the button floating over the last rows.
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: data.entries.length,
                        itemBuilder: (context, index) => _CustomerTile(
                          entry: data.entries[index],
                          onTap: () =>
                              _open(data.entries[index].customer.id!),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _add,
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.addCustomer),
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.entry, required this.onTap});

  final CustomerListEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customer = entry.customer;
    final details = [
      if (customer.hasPhone) ltrIsolate(customer.phone!),
      if (featureOn(Feature.accounts) && entry.accountCount > 0)
        l10n.accountsCount(entry.accountCount),
    ].join(' · ');

    return ListTile(
      key: ValueKey('customer-${customer.id}'),
      leading: const Icon(Icons.person_outline),
      title: Row(
        children: [
          Flexible(
            child: Text(
              customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!customer.isActive) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(l10n.inactiveBadge),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
      subtitle: details.isEmpty
          ? null
          : Text(details, maxLines: 1, overflow: TextOverflow.ellipsis),
      // A deactivated customer can still be opened (to reactivate).
      onTap: onTap,
    );
  }
}
