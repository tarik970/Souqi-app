import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../placeholder/placeholder_screen.dart';
import '../products/products_screen.dart';
import '../settings/settings_screen.dart';

// Currencies and units are reachable from Settings; home shows the five
// main destinations from the brief.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = <_NavItem>[
      _NavItem(
        label: l10n.navSale,
        icon: Icons.point_of_sale,
        builder: (_) => PlaceholderScreen(title: l10n.navSale),
      ),
      _NavItem(
        label: l10n.navProducts,
        icon: Icons.inventory_2,
        builder: (_) => const ProductsScreen(),
      ),
      _NavItem(
        label: l10n.navArchive,
        icon: Icons.receipt_long,
        builder: (_) => PlaceholderScreen(title: l10n.navArchive),
      ),
      _NavItem(
        label: l10n.navStats,
        icon: Icons.bar_chart,
        builder: (_) => PlaceholderScreen(title: l10n.navStats),
      ),
      _NavItem(
        label: l10n.navSettings,
        icon: Icons.settings,
        builder: (_) => const SettingsScreen(),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        children: [for (final item in items) _NavCard(item: item)],
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final WidgetBuilder builder;
}

class _NavCard extends StatelessWidget {
  const _NavCard({required this.item});

  final _NavItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: item.builder)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 48, color: scheme.primary),
            const SizedBox(height: 12),
            Text(
              item.label,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
