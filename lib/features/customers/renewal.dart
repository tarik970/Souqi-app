import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/product.dart';
import '../../l10n/generated/app_localizations.dart';
import '../sale/sale_providers.dart';
import '../sale/sale_screen.dart';

/// "Renew": opens a NEW sale with the customer and the account attached and
/// the account's default package already in the cart, at the product's
/// current price (editable as in any sale). From there it is Save and
/// print / share as usual; saving is what moves the account's dates.
///
/// A sale left unfinished in the cart is not thrown away silently: the
/// seller is asked first.
///
/// An account with no default package (or whose package was deactivated)
/// still opens the sale with the customer attached — the cart is simply
/// empty and a line says why.
Future<void> startRenewal(BuildContext context, CustomerHit hit) async {
  final l10n = AppLocalizations.of(context);
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Everything below runs through the container: the row that was tapped
  // may be rebuilt away while the package is being read.
  final container = ProviderScope.containerOf(context, listen: false);
  final locale = container.read(appLocaleProvider).languageCode;

  if (container.read(cartProvider).isNotEmpty) {
    final replace = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('renew-replace-cart-dialog'),
        scrollable: true,
        title: Text(l10n.renewNewSaleTitle),
        content: Text(l10n.renewNewSaleMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.newSale),
          ),
        ],
      ),
    );
    if (replace != true) return;
  }

  Product? package;
  final packageId = hit.account?.defaultProductId;
  if (packageId != null) {
    final product =
        await container.read(productRepositoryProvider).getById(packageId);
    if (product != null && product.isActive) package = product;
  }
  String? unitName;
  if (package?.unitId != null) {
    final units = await container.read(saleUnitsProvider.future);
    unitName = units[package!.unitId]?.nameFor(locale);
  }

  container.read(cartProvider.notifier).reset();
  container.read(saleSearchProvider.notifier).clear();
  container.read(saleCustomerProvider.notifier).attach(hit.forSale);
  if (package != null) {
    container
        .read(cartProvider.notifier)
        .add(cartLineForProduct(package, unitName: unitName));
  }

  if (!navigator.mounted) return;
  navigator.push(MaterialPageRoute(builder: (_) => const SaleScreen()));
  if (package == null && messenger.mounted) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.renewNoPackage)));
  }
}
