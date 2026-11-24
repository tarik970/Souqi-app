import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';
import '../../l10n/generated/app_localizations.dart';
import 'sale_providers.dart';

/// Opens the quantity / unit-price sheet for [line] and returns the edited
/// line, or null when the user cancels.
///
/// [startAtPrice] is the "type-to-sell" entry: the price field is empty and
/// selected, so the seller types the price straight away.
Future<CartLine?> showQuantitySheet(
  BuildContext context, {
  required CartLine line,
  bool isEdit = false,
  bool startAtPrice = false,
}) {
  return showModalBottomSheet<CartLine>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuantitySheet(
      line: line,
      isEdit: isEdit,
      startAtPrice: startAtPrice,
    ),
  );
}

/// Which of the two big fields the keypad is typing into.
enum _Field { qty, price }

/// Fast quantity + price entry: a numeric keypad (no OS keyboard), quick
/// quantity buttons, the product's unit, an editable unit price and the line
/// total updating live.
///
/// For an item typed into the sale (a line with no product id) the same sheet
/// also carries a "don't save as a product" checkbox and a "more" link that
/// unfolds unit / type / currency, so a new product is described without
/// leaving the sale.
class QuantitySheet extends ConsumerStatefulWidget {
  const QuantitySheet({
    super.key,
    required this.line,
    required this.isEdit,
    this.startAtPrice = false,
  });

  final CartLine line;
  final bool isEdit;
  final bool startAtPrice;

  @override
  ConsumerState<QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends ConsumerState<QuantitySheet> {
  late String _qtyText = quantityToPlainText(widget.line.qtyThousandths);
  late String _priceText = '';
  late String _priceCurrencyCode = widget.line.priceCurrencyCode;
  late _Field _active = widget.startAtPrice ? _Field.price : _Field.qty;

  /// With [QuantitySheet.startAtPrice] the price stays empty instead of being
  /// prefilled from the line.
  late bool _priceInitialized = widget.startAtPrice;

  // Only used for an item typed into the sale.
  late ProductKind _kind = widget.line.kind;
  late int? _unitId = widget.line.unitId;
  late String? _unitName = widget.line.unitName;
  late bool _dontSave = !widget.line.saveAsProduct;
  bool _showMore = false;

  /// An item typed into the sale, not a saved product (yet).
  bool get _isTypedItem => widget.line.productId == null;

  /// The unit shown next to the quantity: services have none.
  String? get _shownUnit => !_isTypedItem
      ? widget.line.unitName
      : (_kind == ProductKind.goods ? _unitName : null);

  /// A field still showing its prefilled value: the first digit typed
  /// replaces it instead of appending, the way a cashier expects (opening a
  /// line that says 1 and typing 3 means 3, not 13).
  final _pristine = {_Field.qty: true, _Field.price: true};

  static const _maxQtyDecimals = 3;
  static const _maxDigits = 12;

  int get _priceDecimals =>
      ref.read(currencyContextProvider).value?.lookup(_priceCurrencyCode)
          ?.decimalPlaces ??
      0;

  void _initPrice(int decimals) {
    if (_priceInitialized) return;
    _priceInitialized = true;
    _priceText = minorToPlainText(widget.line.unitPriceMinor, decimals: decimals);
  }

  String get _buffer => _active == _Field.qty ? _qtyText : _priceText;

  void _setBuffer(String value) {
    setState(() {
      _pristine[_active] = false;
      if (_active == _Field.qty) {
        _qtyText = value;
      } else {
        _priceText = value;
      }
    });
  }

  int get _maxDecimals =>
      _active == _Field.qty ? _maxQtyDecimals : _priceDecimals;

  void _tapDigit(String digit) {
    var text = _pristine[_active]! ? '' : _buffer;
    if (text.contains('.')) {
      final decimals = text.length - text.indexOf('.') - 1;
      if (decimals >= _maxDecimals) return;
    } else if (text == '0') {
      text = '';
    }
    if (text.replaceAll('.', '').length >= _maxDigits) return;
    _setBuffer('$text$digit');
  }

  void _tapSeparator() {
    if (_maxDecimals == 0) return;
    final text = _pristine[_active]! ? '' : _buffer;
    if (text.contains('.')) return;
    _setBuffer(text.isEmpty ? '0.' : '$text.');
  }

  void _backspace() {
    final text = _buffer;
    _setBuffer(text.isEmpty ? '' : text.substring(0, text.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final ctxAsync = ref.watch(currencyContextProvider);
    final ctx = ctxAsync.value;
    if (ctx == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final priceCurrency =
        ctx.lookup(_priceCurrencyCode) ?? ctx.base;
    _priceCurrencyCode = priceCurrency.code;
    _initPrice(priceCurrency.decimalPlaces);

    final invoiceCode = ref.watch(cartProvider).effectiveCurrencyCode(ctx);
    final invoiceCurrency = ctx.require(invoiceCode);

    final qty = parseQuantityThousandths(_qtyText);
    final priceMinor =
        parseAmountMinor(_priceText, decimals: priceCurrency.decimalPlaces);
    final valid = qty != null && qty > 0 && priceMinor != null;
    final kind = _isTypedItem ? _kind : widget.line.kind;
    final unitName = _shownUnit;
    final updatesProductPrice =
        ref.watch(saleSettingsProvider).value?.updatePrices ?? true;

    final draft = widget.line.copyWith(
      qtyThousandths: qty != null && qty > 0 ? qty : 1,
      unitPriceMinor: priceMinor ?? 0,
      priceCurrencyCode: priceCurrency.code,
    );
    final preview = computeCartTotals(
      Cart(invoiceCurrencyCode: ref.watch(cartProvider).invoiceCurrencyCode)
          .add(draft),
      ctx,
    );
    final lineTotal = valid ? preview.lines.first.lineTotalMinor : 0;

    final sellable = ref.watch(sellableCurrenciesProvider);
    final units = _isTypedItem
        ? ref.watch(unitsProvider).value ?? const <Unit>[]
        : const <Unit>[];

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            widget.line.name,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          if (unitName != null || widget.line.code != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                [
                  ?unitName,
                  if (widget.line.code != null) '#${widget.line.code}',
                ].join(' · '),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _ValueField(
                  label: l10n.quantityLabel,
                  value: _qtyText.isEmpty
                      ? '0'
                      : localizeDigits(_qtyText, locale),
                  suffix: unitName,
                  selected: _active == _Field.qty,
                  invalid: qty == null || qty <= 0,
                  onTap: () => setState(() => _active = _Field.qty),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ValueField(
                  label: l10n.unitPriceLabel,
                  value: _priceText.isEmpty
                      ? '0'
                      : localizeDigits(_priceText, locale),
                  suffix: priceCurrency.symbol.isEmpty
                      ? priceCurrency.code
                      : priceCurrency.symbol,
                  selected: _active == _Field.price,
                  // An empty price is not wrong, just not typed yet: no red
                  // border, but "Add" stays disabled.
                  muted: _priceText.isEmpty,
                  invalid: priceMinor == null && _priceText.isNotEmpty,
                  onTap: () => setState(() => _active = _Field.price),
                ),
              ),
            ],
          ),
          if (_isTypedItem) ...[
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    key: const ValueKey('new-item-dont-save'),
                    onTap: () => setState(() => _dontSave = !_dontSave),
                    child: Row(
                      children: [
                        Checkbox(
                          value: _dontSave,
                          onChanged: (value) =>
                              setState(() => _dontSave = value ?? false),
                        ),
                        Flexible(
                          child: Text(
                            l10n.newItemDontSave,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                TextButton(
                  key: const ValueKey('new-item-more'),
                  onPressed: () => setState(() => _showMore = !_showMore),
                  child: Text(_showMore ? l10n.newItemLess : l10n.newItemMore),
                ),
              ],
            ),
            if (_showMore) ...[
              SegmentedButton<ProductKind>(
                key: const ValueKey('new-item-kind'),
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                      value: ProductKind.goods, label: Text(l10n.kindGoods)),
                  ButtonSegment(
                      value: ProductKind.service,
                      label: Text(l10n.kindService)),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) =>
                    setState(() => _kind = selection.first),
              ),
              if (_kind == ProductKind.goods) ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  key: const ValueKey('new-item-unit'),
                  // A unit that was deleted meanwhile is not in the list.
                  initialValue:
                      units.any((u) => u.id == _unitId) ? _unitId : null,
                  decoration: InputDecoration(
                    labelText: l10n.productUnit,
                    border: const OutlineInputBorder(),
                    isDense: true,
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
                  onChanged: (id) => setState(() {
                    _unitId = id;
                    _unitName = id == null
                        ? null
                        : units.firstWhere((u) => u.id == id).nameFor(locale);
                  }),
                ),
              ],
            ],
          ],
          if (sellable.length > 1 && (!_isTypedItem || _showMore)) ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _CurrencyPicker(
                currencies: sellable,
                selected: priceCurrency.code,
                locale: locale,
                // The typed number is kept and re-read in the new currency:
                // the user is restating the price, not converting it.
                onChanged: (code) => setState(() {
                  final decimals = ctx.require(code).decimalPlaces;
                  final dot = _priceText.indexOf('.');
                  if (dot >= 0 && _priceText.length - dot - 1 > decimals) {
                    _priceText = decimals == 0
                        ? _priceText.substring(0, dot)
                        : _priceText.substring(0, dot + 1 + decimals);
                  }
                  _priceCurrencyCode = code;
                }),
              ),
            ),
          ],
          if (!_isTypedItem)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                updatesProductPrice
                    ? l10n.unitPriceUpdatesProduct
                    : l10n.unitPriceThisSaleOnly,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.lineTotalLabel,
                          style: theme.textTheme.bodySmall),
                      if (priceCurrency.code != invoiceCurrency.code &&
                          priceMinor != null)
                        Text(
                          formatMinor(
                            priceMinor,
                            decimals: priceCurrency.decimalPlaces,
                            locale: locale,
                            symbol: priceCurrency.code,
                          ),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                    ],
                  ),
                ),
                Text(
                  formatMinor(
                    lineTotal,
                    decimals: invoiceCurrency.decimalPlaces,
                    locale: locale,
                    symbol: invoiceCurrency.symbol.isEmpty
                        ? invoiceCurrency.code
                        : invoiceCurrency.symbol,
                  ),
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in kind == ProductKind.goods
                  ? const [250, 500, 1000, 2000]
                  : const [1000, 2000, 3000, 5000])
                OutlinedButton(
                  key: ValueKey('qty-preset-$preset'),
                  onPressed: () => setState(() {
                    _active = _Field.qty;
                    _pristine[_Field.qty] = false;
                    _qtyText = quantityToPlainText(preset);
                  }),
                  child: Text(formatQuantity(preset, locale: locale)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _Keypad(
            locale: locale,
            separatorEnabled: _maxDecimals > 0,
            onDigit: _tapDigit,
            onSeparator: _tapSeparator,
            onBackspace: _backspace,
            onClear: () => _setBuffer(''),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: valid
                      ? () => Navigator.of(context).pop(widget.line.copyWith(
                            qtyThousandths: qty,
                            unitPriceMinor: priceMinor,
                            priceCurrencyCode: priceCurrency.code,
                            kind: kind,
                            unitId: _isTypedItem
                                ? () =>
                                    kind == ProductKind.goods ? _unitId : null
                                : null,
                            unitName: _isTypedItem ? () => unitName : null,
                            saveAsProduct: _isTypedItem ? !_dontSave : null,
                          ))
                      : null,
                  child: Text(
                      widget.isEdit ? l10n.updateLine : l10n.addToCart),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ValueField extends StatelessWidget {
  const _ValueField({
    required this.label,
    required this.value,
    this.suffix,
    required this.selected,
    this.muted = false,
    required this.invalid,
    required this.onTap,
  });

  final String label;
  final String value;
  final String? suffix;
  final bool selected;

  /// The value is a placeholder (nothing typed yet): shown greyed.
  final bool muted;
  final bool invalid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = invalid
        ? theme.colorScheme.error
        : selected
            ? theme.colorScheme.primary
            : theme.dividerColor;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: muted ? theme.colorScheme.outline : null,
                    ),
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 6),
                  Text(suffix!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.currencies,
    required this.selected,
    required this.locale,
    required this.onChanged,
  });

  final List<Currency> currencies;
  final String selected;
  final String locale;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: currencies.any((c) => c.code == selected) ? selected : null,
      underline: const SizedBox.shrink(),
      items: [
        for (final currency in currencies)
          DropdownMenuItem(
            value: currency.code,
            child: Text('${currency.code} · ${currency.nameFor(locale)}'),
          ),
      ],
      onChanged: (code) {
        if (code != null) onChanged(code);
      },
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.locale,
    required this.separatorEnabled,
    required this.onDigit,
    required this.onSeparator,
    required this.onBackspace,
    required this.onClear,
  });

  final String locale;
  final bool separatorEnabled;
  final ValueChanged<String> onDigit;
  final VoidCallback onSeparator;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Widget key(
      Widget child,
      VoidCallback? onTap, {
      VoidCallback? onLongPress,
      String? id,
    }) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 54,
            child: OutlinedButton(
              key: id == null ? null : ValueKey('keypad-$id'),
              onPressed: onTap,
              onLongPress: onLongPress,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                textStyle: Theme.of(context).textTheme.titleLarge,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    Widget digit(String d) => key(
          Text(localizeDigits(d, locale)),
          () => onDigit(d),
          id: d,
        );

    return Column(
      children: [
        Row(children: [digit('1'), digit('2'), digit('3')]),
        Row(children: [digit('4'), digit('5'), digit('6')]),
        Row(children: [digit('7'), digit('8'), digit('9')]),
        Row(children: [
          key(
            Text(decimalSeparator(locale)),
            separatorEnabled ? onSeparator : null,
            id: 'separator',
          ),
          digit('0'),
          key(
            const Icon(Icons.backspace_outlined),
            onBackspace,
            onLongPress: onClear,
            id: 'backspace',
          ),
        ]),
      ],
    );
  }
}
