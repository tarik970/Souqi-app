import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';
import '../../l10n/generated/app_localizations.dart';
import '../products/products_providers.dart';
import 'sale_providers.dart';

/// Opens the quick "unsaved item" sheet and returns the line to add, or null
/// when the user cancels. When "save as product" is ticked the product is
/// created here and the returned line carries its id.
Future<CartLine?> showQuickItemSheet(BuildContext context) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const QuickItemSheet(),
  );
}

/// A line typed directly into the sale: name, unit, unit price and quantity,
/// with an optional "save as product" so the shop can keep it for next time.
class QuickItemSheet extends ConsumerStatefulWidget {
  const QuickItemSheet({super.key});

  @override
  ConsumerState<QuickItemSheet> createState() => _QuickItemSheetState();
}

class _QuickItemSheetState extends ConsumerState<QuickItemSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _qty = TextEditingController(text: '1');

  ProductKind _kind = ProductKind.goods;
  int? _unitId;
  String? _currencyCode;
  bool _saveAsProduct = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _qty.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final ctx = ref.watch(currencyContextProvider).value;
    final units = ref.watch(unitsProvider).value ?? const <Unit>[];
    final sellable = ref.watch(sellableCurrenciesProvider);
    if (ctx == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final currencyCode = _currencyCode ?? ctx.baseCode;
    final decimals = ctx.require(currencyCode).decimalPlaces;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.quickItemTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 2),
            Text(
              l10n.quickItemHint,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.quickItemName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            SegmentedButton<ProductKind>(
              segments: [
                ButtonSegment(
                    value: ProductKind.goods, label: Text(l10n.kindGoods)),
                ButtonSegment(
                    value: ProductKind.service, label: Text(l10n.kindService)),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) => setState(() {
                _kind = selection.first;
                if (_kind == ProductKind.service) _unitId = null;
              }),
            ),
            if (_kind == ProductKind.goods) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _unitId,
                decoration: InputDecoration(
                  labelText: l10n.unitOptional,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem<int?>(
                    value: null,
                    child: Text(l10n.unitNone),
                  ),
                  for (final unit in units)
                    DropdownMenuItem<int?>(
                      value: unit.id,
                      child: Text(unit.nameFor(locale)),
                    ),
                ],
                onChanged: (value) => setState(() => _unitId = value),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    decoration: InputDecoration(
                      labelText: l10n.productPrice,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        parseAmountMinor(value ?? '', decimals: decimals) ==
                                null
                            ? l10n.invalidPrice
                            : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: currencyCode,
                    decoration: InputDecoration(
                      labelText: l10n.productCurrency,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      for (final currency in sellable)
                        DropdownMenuItem(
                          value: currency.code,
                          child: Text(currency.code),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _currencyCode = value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _qty,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.quantityLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final qty = parseQuantityThousandths(value ?? '');
                if (qty == null) return l10n.invalidQuantity;
                if (qty <= 0) return l10n.quantityMustBePositive;
                return null;
              },
            ),
            const SizedBox(height: 4),
            CheckboxListTile(
              value: _saveAsProduct,
              onChanged: (value) =>
                  setState(() => _saveAsProduct = value ?? false),
              title: Text(l10n.saveAsProduct),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _submit(currencyCode, decimals, locale, units),
                    child: Text(l10n.addToCart),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit(
    String currencyCode,
    int decimals,
    String locale,
    List<Unit> units,
  ) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    final priceMinor = parseAmountMinor(_price.text, decimals: decimals)!;
    final qty = parseQuantityThousandths(_qty.text)!;
    final unit = _unitId == null
        ? null
        : units.firstWhere((u) => u.id == _unitId, orElse: () => units.first);

    int? productId;
    if (_saveAsProduct) {
      productId = await ref.read(productRepositoryProvider).insert(Product(
            name: name,
            kind: _kind,
            unitId: _kind == ProductKind.goods ? _unitId : null,
            priceMinor: priceMinor,
            currencyCode: currencyCode,
          ));
      ref.invalidate(productsListProvider);
      ref.invalidate(favoriteProductsProvider);
    }

    navigator.pop(CartLine(
      productId: productId,
      name: name,
      kind: _kind,
      unitName: unit?.nameFor(locale),
      unitPriceMinor: priceMinor,
      priceCurrencyCode: currencyCode,
      qtyThousandths: qty,
    ));
  }
}
