import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/archive_screen.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/customer_widgets.dart';
import '../customers/customers_providers.dart';
import '../customers/customers_screen.dart';
import '../customers/due_screen.dart';
import '../customers/quick_search.dart';
import '../customers/renewal.dart';
import '../products/products_screen.dart';
import '../sale/sale_screen.dart';
import '../settings/settings_screen.dart';
import '../setup/setup_screen.dart';
import '../stats/stats_screen.dart';
import '../vouchers/card_stock_screen.dart';
import '../vouchers/voucher_providers.dart';

/// The home screen.
///
/// The quick customer search is the first thing on it (when customers are
/// enabled): one box for a name, a phone or a card number. What is under the
/// box depends on the SHOP TYPE setting, which only changes what is shown
/// first — never what the shop can do:
///
/// - Grocery: the grid of the main destinations.
/// - Cards & subscriptions, or Both: the due-for-renewal list, with the
///   destinations as a compact row of buttons above it.
///
/// Typing in the box replaces either with the search results.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  /// Due rows shown on the home screen itself; "See all" opens the rest.
  static const int dueRowsOnHome = 20;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  // Owned by this screen for its whole life.
  final _search = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _search.dispose();
    super.dispose();
  }

  /// Back from the background — possibly on another day: "due today" and
  /// the badge are re-read rather than left as they were yesterday.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    ref
      ..invalidate(dueOverviewProvider)
      ..invalidate(dueCountProvider)
      // Cards may have expired overnight.
      ..invalidate(voucherAvailabilityProvider)
      ..invalidate(lowStockCountProvider);
  }

  void _push(WidgetBuilder builder) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));

  void _openCustomer(CustomerHit hit) => _push(
        (_) => CustomerDetailScreen(customerId: hit.customer.id!),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final shopType = ref.watch(shopTypeProvider).value ?? shopTypeGrocery;
    final cardsFirst =
        customersEnabled && accountsEnabled && shopType != shopTypeGrocery;
    final dueCount =
        accountsEnabled ? ref.watch(dueCountProvider).value ?? 0 : 0;
    final lowStock =
        voucherStockEnabled ? ref.watch(lowStockCountProvider).value ?? 0 : 0;
    final query = _query.trim();

    final items = <_NavItem>[
      _NavItem(
        id: 'sale',
        label: l10n.navSale,
        icon: Icons.point_of_sale,
        builder: (_) => const SaleScreen(),
      ),
      if (customersEnabled)
        _NavItem(
          id: 'customers',
          label: l10n.navCustomers,
          icon: Icons.people_outline,
          builder: (_) => const CustomersScreen(),
        ),
      if (accountsEnabled)
        _NavItem(
          id: 'due',
          label: l10n.navDue,
          icon: Icons.event_repeat,
          badge: dueCount,
          builder: (_) => const DueScreen(),
        ),
      _NavItem(
        id: 'products',
        label: l10n.navProducts,
        icon: Icons.inventory_2,
        builder: (_) => const ProductsScreen(),
      ),
      if (voucherStockEnabled)
        _NavItem(
          id: 'cards',
          label: l10n.navCardStock,
          icon: Icons.confirmation_number_outlined,
          // Card products that are out of stock or at their threshold.
          badge: lowStock,
          builder: (_) => const CardStockScreen(),
        ),
      _NavItem(
        id: 'archive',
        label: l10n.navArchive,
        icon: Icons.receipt_long,
        builder: (_) => const ArchiveScreen(),
      ),
      _NavItem(
        id: 'stats',
        label: l10n.navStats,
        icon: Icons.bar_chart,
        builder: (_) => const StatsScreen(),
      ),
      _NavItem(
        id: 'settings',
        label: l10n.navSettings,
        icon: Icons.settings,
        builder: (_) => const SettingsScreen(),
      ),
    ];

    final Widget idle = cardsFirst
        ? _CardsHome(items: items, onOpen: _push, onOpenCustomer: _openCustomer)
        : GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            children: [
              for (final item in items)
                _NavCard(item: item, onTap: () => _push(item.builder)),
            ],
          );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      // TWO FIXED SLOTS in this order whatever is shown: the search box and
      // the area under it. The box never moves to another index while the
      // keyboard comes and goes (see the note in the sale screen: a Column
      // matches children by position, and a text field that changes index
      // loses its state and drops the keyboard).
      body: Column(
        children: [
          if (customersEnabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: QuickSearchField(
                controller: _search,
                onChanged: (text) => setState(() => _query = text),
              ),
            ),
          Expanded(
            child: query.isEmpty
                ? idle
                : QuickSearchResults(
                    query: query,
                    onTap: _openCustomer,
                    actionsFor: (hit) => [
                      if (accountsEnabled && hit.account != null)
                        RenewButton(
                          key: ValueKey('renew-${hit.account!.id}'),
                          onPressed: () => startRenewal(context, hit),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
    this.badge = 0,
  });

  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  /// A count shown on the icon; nothing when 0.
  final int badge;
}

/// An icon with a count on its corner.
class _BadgedIcon extends ConsumerWidget {
  const _BadgedIcon({required this.item, required this.size, this.color});

  final _NavItem item;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider).languageCode;
    final icon = Icon(item.icon, size: size, color: color);
    if (item.badge <= 0) return icon;
    return Badge(
      key: ValueKey('home-badge-${item.id}'),
      label: Text(formatMinor(item.badge, decimals: 0, locale: locale)),
      child: icon,
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.item, required this.onTap});

  final _NavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: ValueKey('home-nav-${item.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _BadgedIcon(item: item, size: 48, color: scheme.primary),
              const SizedBox(height: 12),
              // Scaled down rather than wrapped onto a third line: the card
              // is square and a large system font must still fit in it.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    item.label,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The home of a cards / subscriptions shop: the destinations as a compact
/// row of buttons, then the due-for-renewal list.
class _CardsHome extends ConsumerWidget {
  const _CardsHome({
    required this.items,
    required this.onOpen,
    required this.onOpenCustomer,
  });

  final List<_NavItem> items;
  final ValueChanged<WidgetBuilder> onOpen;
  final ValueChanged<CustomerHit> onOpenCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final overview =
        ref.watch(dueOverviewProvider(HomeScreen.dueRowsOnHome)).value;

    return ListView(
      key: const ValueKey('home-cards'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final item in items)
                ActionChip(
                  key: ValueKey('home-nav-${item.id}'),
                  avatar: _BadgedIcon(
                    item: item,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  label: Text(item.label),
                  onPressed: () => onOpen(item.builder),
                ),
            ],
          ),
        ),
        if (overview != null && overview.hits.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.event_available,
                    size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 8),
                Text(
                  l10n.dueEmpty,
                  key: const ValueKey('home-due-empty'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
              ],
            ),
          ),
        if (overview != null && overview.hits.isNotEmpty) ...[
          ...buildDueRows(
            context,
            overview: overview,
            locale: locale,
            onTap: onOpenCustomer,
          ),
          if (overview.hasMore)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton(
                key: const ValueKey('home-due-see-all'),
                onPressed: () => onOpen((_) => const DueScreen()),
                child: Text(l10n.dueSeeAll(formatMinor(
                  overview.counts.total,
                  decimals: 0,
                  locale: locale,
                ))),
              ),
            ),
        ],
      ],
    );
  }
}
