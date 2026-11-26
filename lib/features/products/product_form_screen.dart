import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../data/repositories/product_repository.dart';
import '../vouchers/code_scan_screen.dart';
import '../vouchers/product_stock_screen.dart';
import '../vouchers/voucher_providers.dart';
import 'products_providers.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  const ProductFormScreen({super.key, this.product});

  /// Null when adding a new product.
  final Product? product;

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _barcode;
  late final TextEditingController _price;
  late final TextEditingController _threshold;

  late ProductKind _kind;
  int? _unitId;
  String? _currencyCode; // null until currencies load (then base)
  late bool _favorite;
  late bool _requiresAccount;
  late bool _codeStock;
  late bool _active;
  String? _codeError;
  String? _barcodeError;
  bool _saving = false;

  Product? get _initial => widget.product;

  @override
  void initState() {
    super.initState();
    final p = _initial;
    _name = TextEditingController(text: p?.name ?? '');
    _code = TextEditingController(text: p?.code ?? '');
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _price = TextEditingController();
    _threshold = TextEditingController(
      text: p?.lowStockThreshold == null ? '' : '${p!.lowStockThreshold}',
    );
    _kind = p?.kind ?? ProductKind.goods;
    _unitId = p?.unitId;
    _currencyCode = p?.currencyCode;
    _favorite = p?.isFavorite ?? false;
    _requiresAccount = p?.requiresAccount ?? false;
    _codeStock = p?.soldFromCodeStock ?? false;
    _active = p?.isActive ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _barcode.dispose();
    _price.dispose();
    _threshold.dispose();
    super.dispose();
  }

  /// "Sold from code stock" is offered for SERVICE/CARD products only, and
  /// only while the feature is on.
  bool get _offersCodeStock =>
      featureOn(Feature.vouchers) && _kind == ProductKind.service;

  /// The threshold field: empty = no warning. Null when it is not a whole
  /// number of cards.
  static (bool ok, int? value) _parseThreshold(String text) {
    final trimmed = normalizeDigits(text.trim());
    if (trimmed.isEmpty) return (true, null);
    final value = int.tryParse(trimmed);
    if (value == null || value < 0) return (false, null);
    return (true, value);
  }

  Future<void> _scanBarcode() async {
    final scanned = await scanOneBarcode(context);
    if (scanned == null || !mounted) return;
    setState(() {
      _barcode.text = scanned;
      _barcodeError = null;
    });
  }

  Currency? _selectedCurrency(Map<String, Currency> currencies, String base) {
    return currencies[_currencyCode ?? _initial?.currencyCode ?? base];
  }

  Future<void> _save(Currency currency) async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _codeError = null;
      _barcodeError = null;
    });
    if (!_formKey.currentState!.validate()) return;

    final priceMinor = parseAmountMinor(
      _price.text,
      decimals: currency.decimalPlaces,
    );
    if (priceMinor == null) return; // validator already showed the error

    final code = _code.text.trim().isEmpty ? null : _code.text.trim();
    final repo = ref.read(productRepositoryProvider);
    // The list is refreshed through the container: the save must show up
    // even if this screen was closed while it ran.
    final container = ProviderScope.containerOf(context, listen: false);
    if (code != null &&
        await repo.isCodeTaken(code, excludeId: _initial?.id)) {
      if (!mounted) return;
      setState(() => _codeError = l10n.productCodeTaken);
      return;
    }
    final barcode = ProductRepository.normalizeBarcode(_barcode.text);
    if (barcode != null &&
        await repo.isBarcodeTaken(barcode, excludeId: _initial?.id)) {
      if (!mounted) return;
      setState(() => _barcodeError = l10n.productBarcodeTaken);
      return;
    }
    if (!mounted) return;

    setState(() => _saving = true);
    final product = Product(
      id: _initial?.id,
      name: _name.text,
      code: code,
      barcode: barcode,
      kind: _kind,
      unitId: _kind == ProductKind.goods ? _unitId : null,
      priceMinor: priceMinor,
      currencyCode: currency.code,
      isFavorite: _favorite,
      isActive: _active,
      requiresAccount: _requiresAccount,
      // With the feature off the form shows neither field and leaves both
      // as they were.
      soldFromCodeStock: featureOn(Feature.vouchers)
          ? _offersCodeStock && _codeStock
          : _initial?.soldFromCodeStock ?? false,
      lowStockThreshold: featureOn(Feature.vouchers)
          ? (_offersCodeStock && _codeStock
              ? _parseThreshold(_threshold.text).$2
              : null)
          : _initial?.lowStockThreshold,
    );
    if (_initial == null) {
      await repo.insert(product);
    } else {
      await repo.update(product);
    }
    container.invalidate(productsListProvider);
    // The switch decides whether the product is on the stock screen at all.
    refreshVoucherData(container);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final unitsAsync = ref.watch(unitsProvider);
    final currenciesAsync = ref.watch(currencyMapProvider);
    final baseAsync = ref.watch(baseCurrencyCodeProvider);

    final body = switch ((currenciesAsync, baseAsync, unitsAsync)) {
      (AsyncData(value: final currencies), AsyncData(value: final base),
            AsyncData(value: final units)) =>
        _buildForm(context, l10n, locale, currencies, base, units),
      _ => const Center(child: CircularProgressIndicator()),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? l10n.addProduct : l10n.editProduct),
      ),
      body: body,
    );
  }

  Widget _buildForm(
    BuildContext context,
    AppLocalizations l10n,
    String locale,
    Map<String, Currency> currencies,
    String baseCode,
    List<Unit> units,
  ) {
    final currency = _selectedCurrency(currencies, baseCode)!;
    if (_price.text.isEmpty && _initial != null) {
      // Prefill once, using the product currency's decimal places.
      _price.text = minorToPlainText(
        _initial!.priceMinor,
        decimals: currency.decimalPlaces,
      );
    }
    // Without the multi-currency feature a product is priced in the base
    // currency. One that already has another currency keeps it until it
    // is moved to the base here (the only other choice then offered).
    final activeCurrencies = [
      for (final c in currencies.values)
        if (featureOn(Feature.multiCurrency)
            ? c.isActive || c.code == currency.code
            : c.code == baseCode || c.code == currency.code)
          c,
    ];

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _name,
            decoration: InputDecoration(labelText: l10n.productName),
            textInputAction: TextInputAction.next,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _code,
            decoration: InputDecoration(
              labelText: l10n.productCode,
              errorText: _codeError,
            ),
            textInputAction: TextInputAction.next,
          ),
          if (featureOn(Feature.barcode)) ...[
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('product-barcode'),
              controller: _barcode,
              decoration: InputDecoration(
                labelText: l10n.productBarcode,
                helperText: l10n.productBarcodeHint,
                errorText: _barcodeError,
                suffixIcon: IconButton(
                  key: const ValueKey('product-barcode-scan'),
                  tooltip: l10n.scanBarcodeTitle,
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanBarcode,
                ),
              ),
              textInputAction: TextInputAction.next,
            ),
          ],
          const SizedBox(height: 16),
          Text(l10n.productKind,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<ProductKind>(
            segments: [
              ButtonSegment(
                value: ProductKind.goods,
                label: Text(l10n.kindGoods),
                icon: const Icon(Icons.shopping_basket),
              ),
              ButtonSegment(
                value: ProductKind.service,
                label: Text(l10n.kindService),
                icon: const Icon(Icons.sim_card),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          if (_kind == ProductKind.goods) ...[
            DropdownButtonFormField<int>(
              initialValue: _unitId,
              decoration: InputDecoration(labelText: l10n.productUnit),
              items: [
                for (final unit in units)
                  DropdownMenuItem(
                    value: unit.id,
                    child: Text(unit.nameFor(locale)),
                  ),
              ],
              onChanged: (v) => setState(() => _unitId = v),
              validator: (v) => v == null ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: SelectAllOnFocus(
                  controller: _price,
                  child: TextFormField(
                    controller: _price,
                    decoration: InputDecoration(labelText: l10n.productPrice),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) => parseAmountMinor(v ?? '',
                                decimals: currency.decimalPlaces) ==
                            null
                        ? l10n.invalidPrice
                        : null,
                  ),
                ),
              ),
              if (activeCurrencies.length > 1) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    initialValue: currency.code,
                    decoration:
                        InputDecoration(labelText: l10n.productCurrency),
                    items: [
                      for (final c in activeCurrencies)
                        DropdownMenuItem(value: c.code, child: Text(c.code)),
                    ],
                    onChanged: (v) => setState(() => _currencyCode = v),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.favoriteLabel),
            value: _favorite,
            onChanged: (v) => setState(() => _favorite = v),
          ),
          // Without the accounts feature there would be no way to attach an
          // account, so the switch that demands one is not offered.
          if (featureOn(Feature.accounts) && _kind == ProductKind.service)
            SwitchListTile(
              key: const ValueKey('product-requires-account'),
              title: Text(l10n.requiresAccount),
              subtitle: Text(l10n.requiresAccountHint),
              value: _requiresAccount,
              onChanged: (v) => setState(() => _requiresAccount = v),
            ),
          if (_offersCodeStock) ...[
            SwitchListTile(
              key: const ValueKey('product-code-stock'),
              title: Text(l10n.soldFromCodeStock),
              subtitle: Text(l10n.soldFromCodeStockHint),
              value: _codeStock,
              onChanged: (v) => setState(() => _codeStock = v),
            ),
            if (_codeStock) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SelectAllOnFocus(
                  controller: _threshold,
                  child: TextFormField(
                    key: const ValueKey('product-low-stock'),
                    controller: _threshold,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.lowStockThresholdLabel,
                      helperText: l10n.lowStockThresholdHint,
                    ),
                    validator: (v) => _parseThreshold(v ?? '').$1
                        ? null
                        : l10n.invalidNumber,
                  ),
                ),
              ),
              // Loading codes needs a saved product to load them for.
              if (_initial != null && _initial!.soldFromCodeStock)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('product-open-stock'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ProductStockScreen(productId: _initial!.id!),
                      ),
                    ),
                    icon: const Icon(Icons.confirmation_number_outlined),
                    label: Text(l10n.manageStock),
                  ),
                ),
            ],
          ],
          if (_initial != null && !_initial!.isActive)
            SwitchListTile(
              title: Text(l10n.activeLabel),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(currency),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.save),
            ),
          ),
        ],
      ),
    );
  }
}
