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
import '../debts/debt_providers.dart';
import '../debts/debtors_screen.dart';
import '../products/products_screen.dart';
import '../sale/sale_screen.dart';
import '../settings/settings_screen.dart';
import '../setup/setup_screen.dart';
import '../stats/stats_screen.dart';
import '../vouchers/card_stock_screen.dart';
import '../vouchers/voucher_providers.dart';

/// The home screen.
///
/// ONE layout for every shop type: the quick customer search on top, then
/// the cards that need an answer today (debts, renewals due), then the grid
/// of large destination tiles — two columns, every tile the same size.
///
/// The SHOP TYPE setting only changes the ORDER of the tiles, never what the
/// shop can do:
///
/// - Cards & subscriptions: Sale, Due for renewal, Customers, Card stock,
///   Products, Archive, Statistics, Settings.
/// - Both: Sale, Products, Customers, Due for renewal, Card stock, Archive,
///   Statistics, Settings.
/// - Grocery: the same order as Both, with Due for renewal and Card stock
///   left out while those two have nothing to show (no account is due, no
///   card product exists) — a grocer who never sells cards is not offered a
///   tile into an empty screen, and the tile appears by itself the day there
///   is data behind it.
///
/// Typing in the search box replaces everything under it with the results.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  /// Names of the next renewals shown on the "Due for renewal" card.
  static const int dueNamesOnHome = 3;

  /// The destinations, in the order a cards / subscriptions shop wants them.
  static const List<String> _cardsOrder = [
    'sale',
    'due',
    'customers',
    'cards',
    'products',
    'archive',
    'stats',
    'settings',
  ];

  /// The order a grocery ("Both") shop wants them in.
  static const List<String> _goodsOrder = [
    'sale',
    'products',
    'customers',
    'due',
    'cards',
    'archive',
    'stats',
    'settings',
  ];

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
      ..invalidate(lowStockCountProvider)
      // A debt may have become overdue overnight.
      ..invalidate(debtorsProvider);
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
    final grocery = shopType == shopTypeGrocery;
    // The renewals card belongs to a shop that sells subscriptions.
    final renewalsCard = customersEnabled && accountsEnabled && !grocery;
    final dueCount =
        accountsEnabled ? ref.watch(dueCountProvider).value ?? 0 : 0;
    final lowStock =
        voucherStockEnabled ? ref.watch(lowStockCountProvider).value ?? 0 : 0;
    // "There is at least one card product": one is either low on stock or
    // has codes left, so the two counts together answer it (and both are
    // already read for the badges).
    final hasCardProducts = voucherStockEnabled &&
        (lowStock > 0 ||
            (ref.watch(voucherAvailabilityProvider).value?.isNotEmpty ??
                false));
    final query = _query.trim();
    final debtOn = ref.watch(debtFeatureProvider);

    // Every destination this build has, by id; the order comes after.
    final byId = <String, _NavItem>{
      'sale': _NavItem(
        id: 'sale',
        label: l10n.navSale,
        icon: Icons.point_of_sale,
        builder: (_) => const SaleScreen(),
      ),
      if (customersEnabled)
        'customers': _NavItem(
          id: 'customers',
          label: l10n.navCustomers,
          icon: Icons.people_outline,
          builder: (_) => const CustomersScreen(),
        ),
      // Grocery: only once something is actually due.
      if (accountsEnabled && (!grocery || dueCount > 0))
        'due': _NavItem(
          id: 'due',
          label: l10n.navDue,
          icon: Icons.event_repeat,
          badge: dueCount,
          builder: (_) => const DueScreen(),
        ),
      'products': _NavItem(
        id: 'products',
        label: l10n.navProducts,
        icon: Icons.inventory_2,
        builder: (_) => const ProductsScreen(),
      ),
      // Grocery: only once the shop has card products.
      if (voucherStockEnabled && (!grocery || hasCardProducts))
        'cards': _NavItem(
          id: 'cards',
          label: l10n.navCardStock,
          icon: Icons.confirmation_number_outlined,
          // Card products that are out of stock or at their threshold.
          badge: lowStock,
          builder: (_) => const CardStockScreen(),
        ),
      'archive': _NavItem(
        id: 'archive',
        label: l10n.navArchive,
        icon: Icons.receipt_long,
        builder: (_) => const ArchiveScreen(),
      ),
      'stats': _NavItem(
        id: 'stats',
        label: l10n.navStats,
        icon: Icons.bar_chart,
        builder: (_) => const StatsScreen(),
      ),
      'settings': _NavItem(
        id: 'settings',
        label: l10n.navSettings,
        icon: Icons.settings,
        builder: (_) => const SettingsScreen(),
      ),
    };
    final order = shopType == shopTypeCards
        ? HomeScreen._cardsOrder
        : HomeScreen._goodsOrder;
    final items = [
      for (final id in order) ?byId[id],
    ];

    final Widget idle = ListView(
      key: const ValueKey('home-idle'),
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (debtOn)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: HomeDebtsCard(),
          ),
        if (renewalsCard)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: HomeDueCard(onOpen: _push, onOpenCustomer: _openCustomer),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: GridView.count(
            key: const ValueKey('home-tiles'),
            crossAxisCount: 2,
            // A little wider than tall: 6–8 tiles on a phone screen.
            childAspectRatio: 1.25,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            // The whole home is one scroll; the grid is as tall as its rows.
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final item in items)
                _NavCard(item: item, onTap: () => _push(item.builder)),
            ],
          ),
        ),
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

/// One destination tile: a big icon over its label, the same size on every
/// shop type.
class _NavCard extends StatelessWidget {
  const _NavCard({required this.item, required this.onTap});

  final _NavItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              _BadgedIcon(item: item, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              // Two lines at the tile's width, then scaled down rather than
              // clipped: a long label and a large system font must both fit.
              Flexible(
                child: LayoutBuilder(
                  builder: (context, constraints) => FittedBox(
                    fit: BoxFit.scaleDown,
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: constraints.maxWidth),
                      child: Text(
                        item.label,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
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

/// The "Due for renewal" card of a cards / subscriptions shop, in the same
/// style as the Debts card: how many are overdue, due today and due soon,
/// the next three names, and a way into the full list. A quiet line when
/// nothing is due.
class HomeDueCard extends ConsumerWidget {
  const HomeDueCard({
    super.key,
    required this.onOpen,
    required this.onOpenCustomer,
  });

  final ValueChanged<WidgetBuilder> onOpen;
  final ValueChanged<CustomerHit> onOpenCustomer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final overview =
        ref.watch(dueOverviewProvider(HomeScreen.dueNamesOnHome)).value;
    final counts = overview?.counts;
    final total = counts?.total ?? 0;
    String count(int value) => formatMinor(value, decimals: 0, locale: locale);

    // Only the buckets that hold something, so the line stays short.
    final buckets = <String>[
      if ((counts?.overdue ?? 0) > 0)
        l10n.dueSectionOverdue(count(counts!.overdue)),
      if ((counts?.today ?? 0) > 0) l10n.dueSectionToday(count(counts!.today)),
      if ((counts?.soon ?? 0) > 0)
        l10n.dueSectionSoon(overview!.soonDays, count(counts!.soon)),
    ];
    final names = [
      for (final hit in overview?.hits ?? const <CustomerHit>[])
        hit.customer.name,
    ];

    return Card(
      key: const ValueKey('home-due'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen((_) => const DueScreen()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                total > 0 ? Icons.event_repeat : Icons.event_available,
                size: 36,
                color: total > 0
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.navDue,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (overview == null)
                      const Text('…')
                    else if (total == 0)
                      Text(
                        l10n.dueEmpty,
                        key: const ValueKey('home-due-empty'),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      )
                    else ...[
                      Text(
                        buckets.join(' · '),
                        key: const ValueKey('home-due-counts'),
                        maxLines: 2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: (counts?.overdue ?? 0) > 0
                              ? theme.colorScheme.error
                              : null,
                        ),
                      ),
                      if (names.isNotEmpty)
                        Text(
                          names.join(' · '),
                          key: const ValueKey('home-due-names'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                    ],
                  ],
                ),
              ),
              if (total > 0)
                TextButton(
                  key: const ValueKey('home-due-see-all'),
                  onPressed: () => onOpen((_) => const DueScreen()),
                  child: Text(l10n.dueSeeAll(count(total))),
                )
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Debts" card of the home screen: the total outstanding and how many
/// customers are overdue; a tap opens the debtors list.
///
/// With the "PIN to open debts" setting on and the PIN not yet entered, the
/// card shows a lock instead of the figures — and does not read them.
class HomeDebtsCard extends ConsumerWidget {
  const HomeDebtsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final pinRequired = ref.watch(debtRequirePinProvider).value;
    final locked =
        pinRequired == null || (pinRequired && !ref.watch(debtUnlockedProvider));
    // Not watched while locked: nothing is read from the ledger behind the
    // door.
    final snapshot = locked ? null : ref.watch(debtorsProvider).value;
    final money = ref.watch(baseMoneyProvider);
    final overdue = snapshot?.overdueCount ?? 0;

    return Card(
      key: const ValueKey('home-debts'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openDebtors(context),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                pinRequired == true && locked
                    ? Icons.lock_outline
                    : Icons.menu_book_outlined,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      l10n.debtsTitle,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (pinRequired == true && locked)
                      Text(
                        l10n.debtLockedMessage,
                        key: const ValueKey('home-debts-locked'),
                      )
                    else ...[
                      // One line, scaled down: totals run into the millions
                      // and the system font may be large.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          snapshot == null
                              ? '…'
                              : money(snapshot.totalOutstandingBaseMinor),
                          key: const ValueKey('home-debts-total'),
                          maxLines: 1,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (snapshot != null)
                        Text(
                          overdue == 0
                              ? l10n.homeDebtsNoOverdue
                              : l10n.homeDebtsOverdue(
                                  formatMinor(
                                    overdue,
                                    decimals: 0,
                                    locale: locale,
                                  ),
                                ),
                          key: const ValueKey('home-debts-overdue'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: overdue == 0
                                ? theme.colorScheme.outline
                                : theme.colorScheme.error,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
