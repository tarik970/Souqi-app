import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/unit.dart';
import '../../l10n/generated/app_localizations.dart';
import '../vouchers/voucher_providers.dart';
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

/// The order the unit chips are offered in: the unit used for the last new
/// item first (the one this shop keeps reaching for), then the unit this line
/// already has, then the rest in their own order. Each unit appears once.
///
/// Pure, so the order is unit-tested without the sheet.
List<Unit> orderUnitsForPicker(
  List<Unit> units, {
  int? lastUsedId,
  int? lineUnitId,
}) {
  final taken = <int>{};
  final ordered = <Unit>[];
  void first(int? id) {
    if (id == null) return;
    for (final unit in units) {
      if (unit.id == id && taken.add(id)) ordered.add(unit);
    }
  }

  first(lastUsedId);
  first(lineUnitId);
  for (final unit in units) {
    if (unit.id != null && taken.add(unit.id!)) ordered.add(unit);
  }
  return ordered;
}

/// Fast quantity + price entry: a numeric keypad (no OS keyboard), quick
/// quantity buttons, a row of unit chips, an editable unit price and the line
/// total updating live.
///
/// The unit chips are there for every GOODS line, saved product or not: the
/// unit is what a seller re-picks most often (the same sugar sold by the kilo
/// and by the bag), so it must not hide behind "more". Changing it on a saved
/// product's line changes THAT LINE only — the product keeps its own unit; on
/// an item typed into the sale it is the unit the new product gets.
///
/// For an item typed into the sale (a line with no product id) the same sheet
/// also carries a "don't save as a product" checkbox and a "more" link that
/// unfolds type / currency, so a new product is described without leaving the
/// sale.
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

  /// The unit of THIS line, picked from the chips.
  late int? _unitId = widget.line.unitId;
  late String? _unitName = widget.line.unitName;

  // Only used for an item typed into the sale.
  late ProductKind _kind = widget.line.kind;
  late bool _dontSave = !widget.line.saveAsProduct;
  bool _showMore = false;

  /// An item typed into the sale, not a saved product (yet).
  bool get _isTypedItem => widget.line.productId == null;

  /// The kind in force: only a typed item can change it.
  ProductKind get _effectiveKind => _isTypedItem ? _kind : widget.line.kind;

  /// The unit shown next to the quantity: services have none.
  String? get _shownUnit =>
      _effectiveKind == ProductKind.goods ? _unitName : null;

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

  /// A card sold from code stock is sold in whole cards.
  int get _maxDecimals => _active == _Field.qty
      ? (widget.line.codeStock ? 0 : _maxQtyDecimals)
      : _priceDecimals;

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
    // A product sold from code stock: whole cards, and never more than the
    // stock holds. What the other lines of the cart already take counts —
    // the same card at two prices is two lines drawing on one stock.
    final cardId = widget.line.codeStock ? widget.line.productId : null;
    int? cardsLeft;
    if (cardId != null) {
      final stock = ref.watch(voucherAvailabilityProvider).value;
      if (stock != null) {
        var taken = 0;
        for (final other in ref.watch(cartProvider).lines) {
          if (!other.codeStock || other.productId != cardId) continue;
          if (widget.isEdit && other.id == widget.line.id) continue;
          taken += (other.qtyThousandths + 999) ~/ 1000;
        }
        cardsLeft = (stock[cardId] ?? 0) - taken;
        if (cardsLeft < 0) cardsLeft = 0;
      }
    }
    final wholeCards = cardId == null || (qty != null && qty % 1000 == 0);
    final overStock =
        cardsLeft != null && qty != null && qty > cardsLeft * 1000;
    final valid = qty != null &&
        qty > 0 &&
        priceMinor != null &&
        wholeCards &&
        !overStock;
    final kind = _effectiveKind;
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
    // Every GOODS line gets the chips, so the unit table is always needed.
    final units = kind == ProductKind.goods
        ? orderUnitsForPicker(
            ref.watch(unitsProvider).value ?? const <Unit>[],
            lastUsedId: ref.watch(newItemUnitProvider).value?.id,
            lineUnitId: widget.line.unitId,
          )
        : const <Unit>[];

    // Cancel / Add stay pinned at the foot of the sheet while everything
    // above them scrolls: on a small phone at a large system font the keypad
    // alone is taller than what is left of the screen, and the seller must
    // never have to scroll to reach the button that adds the line.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: _form(
              l10n: l10n,
              theme: theme,
              locale: locale,
              ctx: ctx,
              priceCurrency: priceCurrency,
              invoiceCurrency: invoiceCurrency,
              sellable: sellable,
              units: units,
              kind: kind,
              unitName: unitName,
              qty: qty,
              priceMinor: priceMinor,
              lineTotal: lineTotal,
              updatesProductPrice: updatesProductPrice,
              cardsLeft: cardsLeft,
              overStock: overStock,
            ),
          ),
        ),
        Padding(
          // The keyboard's inset sits under the buttons, so the footer stays
          // just above an OS keyboard raised over the sheet.
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            12 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Row(
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
                            // Also for a saved product: the unit travels with
                            // THIS line (and with its invoice item), never
                            // back into the catalog.
                            unitId: () =>
                                kind == ProductKind.goods ? _unitId : null,
                            unitName: () => unitName,
                            saveAsProduct: _isTypedItem ? !_dontSave : null,
                          ))
                      : null,
                  child: Text(
                      widget.isEdit ? l10n.updateLine : l10n.addToCart),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The scrolling part: name, unit chips, the two big fields, the "more"
  /// block, the live line total, the quantity presets and the keypad.
  Widget _form({
    required AppLocalizations l10n,
    required ThemeData theme,
    required String locale,
    required CurrencyContext ctx,
    required Currency priceCurrency,
    required Currency invoiceCurrency,
    required List<Currency> sellable,
    required List<Unit> units,
    required ProductKind kind,
    required String? unitName,
    required int? qty,
    required int? priceMinor,
    required int lineTotal,
    required bool updatesProductPrice,
    required int? cardsLeft,
    required bool overStock,
  }) {
    return Column(
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
        if (widget.line.code != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '#${widget.line.code}',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
              textAlign: TextAlign.center,
            ),
          ),
        // A card sold from code stock: how many there are to sell — and, in
        // the error colour, that the quantity asks for more than that.
        if (cardsLeft != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              cardsLeft == 0
                  ? l10n.stockOut
                  : overStock
                      ? l10n.codeStockOnly(
                          formatMinor(cardsLeft, decimals: 0, locale: locale),
                        )
                      : l10n.stockCount(
                          formatMinor(cardsLeft, decimals: 0, locale: locale),
                        ),
              key: const ValueKey('qty-stock'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cardsLeft == 0 || overStock
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        // The unit, right under the name and one tap away. A service or a
        // top-up card has no unit at all, so the row is not shown for it.
        if (kind == ProductKind.goods && units.isNotEmpty) ...[
          const SizedBox(height: 10),
          _UnitChips(
            units: units,
            selectedId: _unitId,
            locale: locale,
            noneLabel: l10n.unitNone,
            onChanged: (unit) => setState(() {
              _unitId = unit?.id;
              _unitName = unit?.nameFor(locale);
            }),
          ),
        ],
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
          if (_showMore)
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
              Flexible(
                child: Text(
                  formatMinor(
                    lineTotal,
                    decimals: invoiceCurrency.decimalPlaces,
                    locale: locale,
                    symbol: invoiceCurrency.symbol.isEmpty
                        ? invoiceCurrency.code
                        : invoiceCurrency.symbol,
                  ),
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
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
      ],
    );
  }
}

/// The units as one horizontally scrollable row of chips, the selected one
/// highlighted. The last chip clears the unit (a line with nothing to write
/// in the unit column of the invoice).
class _UnitChips extends StatelessWidget {
  const _UnitChips({
    required this.units,
    required this.selectedId,
    required this.locale,
    required this.noneLabel,
    required this.onChanged,
  });

  final List<Unit> units;
  final int? selectedId;
  final String locale;
  final String noneLabel;

  /// Null = no unit.
  final ValueChanged<Unit?> onChanged;

  @override
  Widget build(BuildContext context) {
    // No fixed height: a large system font makes the chips taller and the row
    // grows with them (the sheet itself scrolls).
    return SingleChildScrollView(
      key: const ValueKey('unit-chips'),
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          for (final unit in units) ...[
            ChoiceChip(
              key: ValueKey('unit-chip-${unit.id}'),
              label: Text(unit.nameFor(locale)),
              selected: unit.id == selectedId,
              onSelected: (_) => onChanged(unit),
            ),
            const SizedBox(width: 8),
          ],
          ChoiceChip(
            key: const ValueKey('unit-chip-none'),
            label: Text(noneLabel),
            selected: selectedId == null,
            onSelected: (_) => onChanged(null),
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
                  Flexible(
                    child: Text(
                      suffix!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
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
      // The name of a currency plus the arrow is wider than a narrow phone at
      // a large system font: the menu's rows ellipsize instead of overflowing.
      isExpanded: true,
      items: [
        for (final currency in currencies)
          DropdownMenuItem(
            value: currency.code,
            child: Text(
              '${currency.code} · ${currency.nameFor(locale)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
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
