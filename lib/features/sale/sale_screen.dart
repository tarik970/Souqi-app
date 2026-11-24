import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/product.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';
import '../products/products_providers.dart';
import 'discount_sheet.dart';
import 'quantity_sheet.dart';
import 'quick_item_sheet.dart';
import 'rates_sheet.dart';
import 'sale_invoice_screen.dart';
import 'sale_providers.dart';

/// The sale screen: favorites bar, search, cart, live total, save.
class SaleScreen extends ConsumerStatefulWidget {
  const SaleScreen({super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  String get _locale => ref.read(appLocaleProvider).languageCode;

  CurrencyContext? get _ctx => ref.read(currencyContextProvider).value;

  /// Builds a cart line from a saved product, snapshotting its unit name.
  /// Awaits the unit table so the snapshot is never silently empty on the
  /// first sale after launch.
  Future<CartLine> _lineFor(Product product,
      {int qtyThousandths = 1000}) async {
    // Read before the await: `ref` must not be used once the screen may be
    // gone.
    final locale = _locale;
    final units = await ref.read(saleUnitsProvider.future);
    return CartLine(
      productId: product.id,
      name: product.name,
      code: product.code,
      kind: product.kind,
      unitId: product.unitId,
      unitName: product.unitId == null
          ? null
          : units[product.unitId]?.nameFor(locale),
      unitPriceMinor: product.priceMinor,
      priceCurrencyCode: product.currencyCode,
      qtyThousandths: qtyThousandths,
      // What the product costs right now, so the cart can tell when the
      // seller changes the price ("remember last price").
      listPriceMinor: product.priceMinor,
      listCurrencyCode: product.currencyCode,
    );
  }

  /// "Type-to-sell": sells [name] as a new item. Opens the quantity sheet
  /// with the price empty and selected, quantity 1, the unit of the previous
  /// new item, kind GOODS, the base currency. The line goes straight into the
  /// cart; the product itself is only created when the invoice is saved.
  Future<void> _startNewItem(String name) async {
    final settingsRepository = ref.read(settingsRepositoryProvider);
    final locale = _locale;
    // All three are requested before the first await (see _lineFor).
    final (ctx, saleSettings, unit) = await (
      ref.read(currencyContextProvider.future),
      ref.read(saleSettingsProvider.future),
      ref.read(newItemUnitProvider.future),
    ).wait;
    if (!mounted) return;
    final line = await showQuantitySheet(
      context,
      line: CartLine(
        name: name,
        kind: ProductKind.goods,
        unitId: unit?.id,
        unitName: unit?.nameFor(locale),
        unitPriceMinor: 0,
        priceCurrencyCode: ctx.baseCode,
        qtyThousandths: 1000,
        saveAsProduct: saleSettings.saveNewItems,
      ),
      startAtPrice: true,
    );
    if (line == null || !mounted) return;
    ref.read(cartProvider.notifier).add(line);
    _clearSearch();
    // Back to the search box: type the next item.
    _searchFocus.requestFocus();
    if (line.kind == ProductKind.goods && line.unitId != unit?.id) {
      await settingsRepository.setString(
        SettingsKeys.lastNewItemUnitId,
        '${line.unitId ?? 0}',
      );
      if (mounted) ref.invalidate(newItemUnitProvider);
    }
  }

  Future<void> _tapProduct(Product product) async {
    final draft = await _lineFor(product);
    if (!mounted) return;
    final line = await showQuantitySheet(context, line: draft);
    if (line == null || !mounted) return;
    ref.read(cartProvider.notifier).add(line);
    _clearSearch();
  }

  Future<void> _editLine(CartLine line) async {
    final edited =
        await showQuantitySheet(context, line: line, isEdit: true);
    if (edited == null || !mounted) return;
    ref.read(cartProvider.notifier).replace(edited);
  }

  void _clearSearch() {
    _search.clear();
    ref.read(saleSearchProvider.notifier).clear();
  }

  /// Only digits (spaces and dashes aside): the text was meant as a code or
  /// came from a barcode scanner, not as the name of a new item.
  static final _digitsOnly = RegExp(r'^[0-9]+$');

  /// Enter on the search field picks the top row:
  /// - an exact code (or barcode) goes straight into the cart with quantity
  ///   1 — no sheet, no extra tap;
  /// - a product with exactly that name opens its quantity sheet;
  /// - anything else is a new item: the same as tapping "+ Add «text»".
  ///
  /// One exception: a number that matches no code is reported as an unknown
  /// code instead of becoming an item called "6221234567890" — a mistyped
  /// code or an unknown barcode must not start a new product. The "+ Add" row
  /// is still there to tap for a product that really is named with digits.
  Future<void> _submitSearch(String raw) async {
    if (raw.trim().isEmpty) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repository = ref.read(productRepositoryProvider);

    final byCode = await repository.getByExactCode(raw);
    if (!mounted) return;
    if (byCode != null) {
      final line = await _lineFor(byCode);
      if (!mounted) return;
      ref.read(cartProvider.notifier).add(line);
      _clearSearch();
      _searchFocus.requestFocus();
      return;
    }

    final results = await searchForSale(repository, raw);
    if (!mounted) return;
    final exact = results.exactMatch;
    if (exact != null) {
      await _tapProduct(exact);
      return;
    }
    if (_digitsOnly.hasMatch(normalizeCode(results.query))) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.codeNotFound(results.query))),
      );
      return;
    }
    await _startNewItem(results.query);
  }

  Future<void> _addQuickItem() async {
    final line = await showQuickItemSheet(context);
    if (line == null || !mounted) return;
    ref.read(cartProvider.notifier).add(line);
  }

  Future<void> _editDiscount() async {
    final result = await showDiscountSheet(context);
    if (result == null || !mounted) return;
    ref.read(cartProvider.notifier).setDiscount(result.discount);
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearCartTitle),
        content: Text(l10n.clearCartMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.clearCart),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      ref.read(cartProvider.notifier).clear();
    }
  }

  /// The extra currencies shown under the total: the very list the invoice
  /// settings screen edits (max 2). This shortcut ticks currencies in and out
  /// of that list one at a time — it never replaces the list, so a
  /// two-currency choice made in the settings survives a visit here.
  Future<void> _pickSecondaryTotals() {
    return showDialog<void>(
      context: context,
      builder: (_) => const _SecondaryTotalsDialog(),
    );
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // The catalog must be refreshed after the save even if this screen is
    // gone by then, so hold on to the container rather than to `ref`.
    final container = ProviderScope.containerOf(context, listen: false);
    final cart = ref.read(cartProvider);
    if (cart.isEmpty || _saving) return;
    final (ctx, saleSettings) = await (
      ref.read(currencyContextProvider.future),
      ref.read(saleSettingsProvider.future),
    ).wait;
    if (!mounted) return;

    final totals = computeCartTotals(cart, ctx);
    if (totals.currenciesNeedingRate.isNotEmpty) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.rateNeeded(
          totals.currenciesNeedingRate.map((c) => c.code).join(', '),
        )),
      ));
      return;
    }

    setState(() => _saving = true);
    try {
      // One transaction: the invoice, the products created from typed items
      // and the prices the seller changed.
      final saved = await container.read(invoiceRepositoryProvider).save(
            Invoice.fromCart(
              cart: cart,
              ctx: ctx,
              createdAt: DateTime.now().toUtc(),
              updateProductPrices: saleSettings.updatePrices,
            ),
          );
      container.read(cartProvider.notifier).reset();
      // New products, new prices and new "most sold" numbers.
      container.invalidate(productsListProvider);
      container.invalidate(favoriteProductsProvider);
      if (!mounted) return;
      navigator.pushReplacement(MaterialPageRoute(
        builder: (_) => SaleInvoiceScreen(invoice: saved),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final cart = ref.watch(cartProvider);
    final totals = ref.watch(cartTotalsProvider);
    final query = ref.watch(saleSearchProvider).trim();
    final sellable = ref.watch(sellableCurrenciesProvider);
    final allCurrencies = ref.watch(currenciesProvider).value ?? const [];

    // The keyboard is up — on this screen that means the seller is typing in
    // the search box. On a small phone the favorites bar, the search box and
    // the full totals panel together are then taller than what is left of the
    // screen, and the Column overflowed ("BOTTOM OVERFLOWED BY 41 PIXELS").
    // None of that is what the seller is looking at while typing, so the
    // favorites bar goes away and the panel shrinks to a one-line total,
    // leaving the results (or the cart) as the only flexible part.
    //
    // The inset is read HERE, above the Scaffold: the Scaffold hides it from
    // its own body (that is how it makes room for the keyboard). Focus is
    // deliberately not part of the test — the space is gone whenever the
    // keyboard is up, including while a sheet with a field is open over this
    // screen.
    final typing = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSale),
        actions: [
          PopupMenuButton<void>(
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                onTap: _addQuickItem,
                child: Text(l10n.quickItemTitle),
              ),
              PopupMenuItem<void>(
                onTap: _pickSecondaryTotals,
                child: Text(l10n.secondaryTotalTitle),
              ),
              if (cart.isNotEmpty)
                PopupMenuItem<void>(
                  onTap: _confirmClear,
                  child: Text(l10n.clearCart),
                ),
            ],
          ),
        ],
      ),
      // FOUR FIXED SLOTS, in this order, in BOTH layouts.
      //
      // The slots never appear, disappear or change widget type as the
      // keyboard comes and goes: a Column matches its old elements to its new
      // children BY POSITION, so dropping the favorites bar out of the list
      // used to shift the search field up one index, onto an element of a
      // different type. Flutter then threw that element away and built a new
      // TextField: its state went with it, its input connection closed, the
      // keyboard dropped, `typing` went back to false and the whole thing
      // flipped back — a loop that made the field impossible to type in on a
      // phone. Each slot now collapses or swaps its own contents instead.
      body: Column(
        children: [
          _FavoritesSlot(collapsed: typing, onTap: _tapProduct),
          Padding(
            key: const ValueKey('sale-search'),
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: TextField(
              key: const ValueKey('sale-search-field'),
              controller: _search,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.done,
              onChanged: ref.read(saleSearchProvider.notifier).set,
              onSubmitted: _submitSearch,
              decoration: InputDecoration(
                hintText: l10n.saleSearchHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSearch,
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? _CartList(
                    totals: totals,
                    onEdit: _editLine,
                  )
                : _SearchResults(
                    onTap: _tapProduct,
                    onAddNew: _startNewItem,
                  ),
          ),
          _TotalsSlot(
            compact: typing,
            compactBuilder: (_) =>
                _CompactTotalBar(totals: totals, locale: locale),
            fullBuilder: (_) => _TotalsPanel(
              totals: totals,
              cart: cart,
              locale: locale,
              sellable: sellable,
              saving: _saving,
              onCurrencyChanged: (code) =>
                  ref.read(cartProvider.notifier).setInvoiceCurrency(code),
              onUpdateRate: () async {
                final base = _ctx?.baseCode;
                if (base == null) return;
                await openRatesQuickAction(
                  context,
                  baseCode: base,
                  currencies: allCurrencies,
                );
              },
              onDiscount: _editDiscount,
              onSave: _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// The favorites bar's slot: always the Column's first child, empty while the
/// keyboard is up. Collapsing it here instead of leaving it out of the
/// children list is what keeps the search field below it on the same index —
/// see the note on the Column.
class _FavoritesSlot extends StatelessWidget {
  const _FavoritesSlot({required this.collapsed, required this.onTap});

  final bool collapsed;
  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context) =>
      collapsed ? const SizedBox.shrink() : _FavoritesBar(onTap: onTap);
}

/// The totals slot: the full panel, or the one-line total that leaves the
/// keyboard room. One stable child of the Column either way; the builders
/// keep the panel that is not shown from being built at all.
class _TotalsSlot extends StatelessWidget {
  const _TotalsSlot({
    required this.compact,
    required this.compactBuilder,
    required this.fullBuilder,
  });

  final bool compact;
  final WidgetBuilder compactBuilder;
  final WidgetBuilder fullBuilder;

  @override
  Widget build(BuildContext context) =>
      compact ? compactBuilder(context) : fullBuilder(context);
}

/// Large one-tap buttons for favorite products.
class _FavoritesBar extends ConsumerWidget {
  const _FavoritesBar({required this.onTap});

  final ValueChanged<Product> onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final favorites = ref.watch(favoriteProductsProvider).value;
    final currencies = ref.watch(currencyContextProvider).value;
    // The bar is one fixed-height row, so a large system font has to grow it
    // — otherwise the name and the price inside a button overflow it.
    final height = MediaQuery.textScalerOf(context).scale(96).clamp(96.0, 160.0);

    if (favorites == null) {
      return SizedBox(height: height);
    }
    if (favorites.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(
          children: [
            Icon(Icons.star_border, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.saleFavoritesHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        itemCount: favorites.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final product = favorites[index];
          final currency = currencies?.lookup(product.currencyCode);
          return SizedBox(
            width: 132,
            child: FilledButton.tonal(
              onPressed: () => onTap(product),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (currency != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatMinor(
                        product.priceMinor,
                        decimals: currency.decimalPlaces,
                        locale: locale,
                        symbol: currency.symbol.isEmpty
                            ? currency.code
                            : currency.symbol,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The secondary-total shortcut: one checkbox per currency, bound to the
/// invoice settings' "also show the total in" list.
class _SecondaryTotalsDialog extends ConsumerWidget {
  const _SecondaryTotalsDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final selected =
        ref.watch(extraTotalCurrenciesProvider).value ?? const <String>[];
    final sellable = ref.watch(sellableCurrenciesProvider);
    final all = ref.watch(currenciesProvider).value ?? const <Currency>[];

    String label(String code) {
      for (final currency in all) {
        if (currency.code == code) {
          return '${currency.code} · ${currency.nameFor(locale)}';
        }
      }
      return code;
    }

    // Every currency that can be converted, plus anything already chosen
    // that no longer can (disabled since) — so it can still be unticked.
    final codes = <String>[
      for (final currency in sellable) currency.code,
      for (final code in selected)
        if (!sellable.any((c) => c.code == code)) code,
    ];

    void toggle(String code, bool on) {
      ref.read(invoiceSettingsProvider.notifier).change(
            (settings) => settings.copyWith(
              extraCurrencies: on
                  ? [
                      ...settings.extraCurrencies,
                      if (!settings.extraCurrencies.contains(code)) code,
                    ]
                  : [
                      for (final other in settings.extraCurrencies)
                        if (other != code) other,
                    ],
            ),
          );
    }

    return AlertDialog(
      title: Text(l10n.secondaryTotalTitle),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                l10n.extraCurrenciesHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
            for (final code in codes)
              CheckboxListTile(
                key: ValueKey('secondary-total-$code'),
                value: selected.contains(code),
                title: Text(label(code)),
                // A third currency cannot be added: two at most.
                onChanged: !selected.contains(code) && selected.length >= 2
                    ? null
                    : (on) => toggle(code, on ?? false),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.onTap, required this.onAddNew});

  final ValueChanged<Product> onTap;

  /// "+ Add «text»" was tapped: sell the typed text as a new item.
  final ValueChanged<String> onAddNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final results = ref.watch(saleSearchResultsProvider);
    final ctx = ref.watch(currencyContextProvider).value;
    final typed =
        ref.watch(saleSearchProvider).trim().replaceAll(RegExp(r'\s+'), ' ');

    return results.when(
      // Keep the previous results on screen while the next keystroke is being
      // searched, instead of flashing a spinner between letters.
      skipLoadingOnReload: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('$error')),
      data: (found) {
        final products = found.products;
        // Offered whenever the typed text is not already a product. While the
        // results still belong to the previous keystroke the row is offered
        // too: the duplicate guard on save makes that harmless.
        final offerNew =
            typed.isNotEmpty && (found.query != typed || found.offersNewItem);
        final offset = offerNew ? 1 : 0;
        return ListView.builder(
          itemCount: products.length + offset,
          itemBuilder: (context, index) {
            if (index < offset) {
              return ListTile(
                key: const ValueKey('add-new-item'),
                leading: Icon(Icons.add_circle,
                    color: theme.colorScheme.primary),
                title: Text(
                  l10n.addNewItem(typed),
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () => onAddNew(typed),
              );
            }
            final product = products[index - offset];
            final currency = ctx?.lookup(product.currencyCode);
            return ListTile(
              leading: Icon(product.kind == ProductKind.goods
                  ? Icons.shopping_basket
                  : Icons.sim_card),
              title: Text(product.name),
              subtitle: currency == null
                  ? null
                  : Text([
                      formatMinor(
                        product.priceMinor,
                        decimals: currency.decimalPlaces,
                        locale: locale,
                        symbol: currency.symbol.isEmpty
                            ? currency.code
                            : currency.symbol,
                      ),
                      if (product.code != null) '#${product.code}',
                    ].join(' · ')),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => onTap(product),
            );
          },
        );
      },
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.totals, required this.onEdit});

  final CartTotals? totals;
  final ValueChanged<CartLine> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final totals = this.totals;
    if (totals == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (totals.isEmpty) {
      // Scrollable and min-size: with the keyboard up at a large system font
      // there is barely any room left here, and the empty-cart art overflowed
      // it by a pixel.
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shopping_cart_outlined,
                  size: 56, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              Text(l10n.cartEmpty, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                l10n.cartEmptyHint,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      );
    }

    final currency = totals.currency;
    final symbol = currency.symbol.isEmpty ? currency.code : currency.symbol;
    final ctx = ref.watch(currencyContextProvider).value;
    final updatePrices =
        ref.watch(saleSettingsProvider).value?.updatePrices ?? true;

    /// What saving the invoice will do to the catalog for this line, if
    /// anything: create the product, or remember the changed price.
    String? catalogHint(CartLine line) {
      if (line.createsProduct) return l10n.cartNewProduct;
      if (updatePrices && line.hasPriceOverride) {
        return l10n.cartPriceWillUpdate;
      }
      return null;
    }

    /// "qty × unit price", the same wording as the printed invoice. A line
    /// priced in another currency shows its ORIGINAL price and currency
    /// ("10 × 5,000 SYP" next to a 3.85 USD total): the converted unit price
    /// is rounded on its own and would not multiply out to the line total.
    String detail(LineTotals entry) {
      final line = entry.line;
      final cross = line.priceCurrencyCode != currency.code;
      final origin = ctx?.lookup(line.priceCurrencyCode);
      final price = formatMinor(
        line.unitPriceMinor,
        decimals: origin?.decimalPlaces ?? entry.origDecimals,
        locale: locale,
        symbol: !cross
            ? symbol
            : (origin == null || origin.symbol.isEmpty
                ? line.priceCurrencyCode
                : origin.symbol),
      );
      return '${formatQuantity(line.qtyThousandths, locale: locale)} × $price';
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: totals.lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = totals.lines[index];
        final line = entry.line;
        final hint = catalogHint(line);
        return ListTile(
          onTap: () => onEdit(line),
          leading: Container(
            width: 52,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              // Scaled down rather than wrapped: a long quantity ("12.345")
              // or unit name ("piece", a custom unit) must not push the box
              // past the height of the row.
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatQuantity(line.qtyThousandths, locale: locale),
                    maxLines: 1,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (line.unitName != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        line.unitName!,
                        maxLines: 1,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          title: Text(line.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                detail(entry),
                key: ValueKey('cart-line-detail-${line.id}'),
              ),
              if (hint != null)
                Text(
                  hint,
                  key: ValueKey('cart-line-hint-${line.id}'),
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                formatMinor(
                  entry.lineTotalMinor,
                  decimals: currency.decimalPlaces,
                  locale: locale,
                  symbol: symbol,
                ),
                style: theme.textTheme.titleMedium,
              ),
              IconButton(
                tooltip: l10n.removeLine,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    ref.read(cartProvider.notifier).remove(line.id),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The totals panel while the keyboard is up: item count and total on one
/// line, nothing else. Save and the rest come back as soon as the keyboard
/// closes (the panel below is the same data, unshrunk).
class _CompactTotalBar extends StatelessWidget {
  const _CompactTotalBar({required this.totals, required this.locale});

  final CartTotals? totals;
  final String locale;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final totals = this.totals;
    if (totals == null) return const SizedBox.shrink();
    final currency = totals.currency;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                totals.isEmpty
                    ? l10n.totalLabel
                    : l10n.itemsCount(totals.lines.length),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatMinor(
                    totals.totalMinor,
                    decimals: currency.decimalPlaces,
                    locale: locale,
                    symbol: currency.symbol.isEmpty
                        ? currency.code
                        : currency.symbol,
                  ),
                  key: const ValueKey('cart-total'),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
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

/// Invoice currency, rate shortcut, discount, the big total and Save.
class _TotalsPanel extends ConsumerWidget {
  const _TotalsPanel({
    required this.totals,
    required this.cart,
    required this.locale,
    required this.sellable,
    required this.saving,
    required this.onCurrencyChanged,
    required this.onUpdateRate,
    required this.onDiscount,
    required this.onSave,
  });

  final CartTotals? totals;
  final Cart cart;
  final String locale;
  final List<Currency> sellable;
  final bool saving;
  final ValueChanged<String?> onCurrencyChanged;
  final VoidCallback onUpdateRate;
  final VoidCallback onDiscount;
  final VoidCallback onSave;

  /// The currency whose rate the quick button talks about: the invoice
  /// currency when it is not the base one, otherwise the first non-base
  /// currency used in the cart, otherwise the first non-base currency.
  Currency? _rateFocus(CurrencyContext ctx, CartTotals totals) {
    if (totals.currency.code != ctx.baseCode) return totals.currency;
    for (final entry in totals.lines) {
      if (entry.line.priceCurrencyCode != ctx.baseCode) {
        return ctx.lookup(entry.line.priceCurrencyCode);
      }
    }
    for (final currency in sellable) {
      if (currency.code != ctx.baseCode) return currency;
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final ctx = ref.watch(currencyContextProvider).value;
    final totals = this.totals;
    if (totals == null || ctx == null) return const SizedBox.shrink();

    final currency = totals.currency;
    final symbol = currency.symbol.isEmpty ? currency.code : currency.symbol;
    String money(int minor) => formatMinor(
          minor,
          decimals: currency.decimalPlaces,
          locale: locale,
          symbol: symbol,
        );

    final focus = _rateFocus(ctx, totals);
    final needRate = totals.currenciesNeedingRate;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A Wrap, not a Row: at a large system font the rate shortcut
              // is wider than what is left beside the currency picker, and it
              // then takes a line of its own instead of overflowing.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  if (sellable.length > 1)
                    DropdownButton<String>(
                      value: sellable.any((c) => c.code == currency.code)
                          ? currency.code
                          : null,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final option in sellable)
                          DropdownMenuItem(
                            value: option.code,
                            child: Text(option.code == ctx.baseCode
                                ? '${option.code} · ${l10n.baseBadge}'
                                : option.code),
                          ),
                      ],
                      onChanged: onCurrencyChanged,
                    )
                  else
                    Text('${l10n.invoiceCurrency}: ${currency.code}',
                        style: theme.textTheme.bodySmall),
                  if (focus != null)
                    TextButton.icon(
                      onPressed: onUpdateRate,
                      icon: const Icon(Icons.currency_exchange, size: 18),
                      label: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            l10n.rateDisplay(
                              focus.code,
                              formatRateValue(focus.rate, locale: locale),
                              ctx.baseCode,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                          Text(
                            focus.rateUpdatedAt == null
                                ? l10n.rateNeverUpdated
                                : DateFormat.yMd(locale).add_jm().format(
                                    focus.rateUpdatedAt!.toLocal()),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: focus.rateUpdatedAt == null
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (totals.isNotEmpty) ...[
                const Divider(height: 12),
                Row(
                  children: [
                    Text(
                      l10n.itemsCount(totals.lines.length),
                      style: theme.textTheme.bodySmall,
                    ),
                    const Spacer(),
                    if (totals.discountMinor != 0)
                      Text(
                        '${l10n.subtotalLabel}: ${money(totals.subtotalMinor)}',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ],
              if (discountEnabled && totals.isNotEmpty)
                Row(
                  children: [
                    // Flexible: at a large system font the discount button's
                    // own label is wider than the row.
                    Flexible(
                      child: TextButton.icon(
                        onPressed: onDiscount,
                        icon: const Icon(Icons.percent, size: 18),
                        label: Text(
                          totals.discountMinor == 0
                              ? l10n.discountTitle
                              : '${l10n.discountLabel} − '
                                  '${money(totals.discountMinor)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (totals.discountMinor != 0)
                      IconButton(
                        tooltip: l10n.discountNone,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () =>
                            ref.read(cartProvider.notifier).setDiscount(null),
                      ),
                  ],
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(l10n.totalLabel, style: theme.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  // One flexible child, not a Spacer plus a Flexible: two
                  // flex children split the free space and the rounding of
                  // that division overflowed the row by a fraction of a pixel.
                  Expanded(
                    child: Text(
                      money(totals.totalMinor),
                      key: const ValueKey('cart-total'),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
              for (final extra in totals.extraTotals)
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    '≈ ${formatMinor(
                      extra.totalMinor,
                      decimals: extra.currency.decimalPlaces,
                      locale: locale,
                      symbol: extra.currency.symbol.isEmpty
                          ? extra.currency.code
                          : extra.currency.symbol,
                    )}',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ),
              if (needRate.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    l10n.rateNeeded(needRate.map((c) => c.code).join(', ')),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed:
                    cart.isEmpty || saving || needRate.isNotEmpty ? null : onSave,
                icon: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check),
                label: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(l10n.save,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
