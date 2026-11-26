import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/price_change.dart';
import '../../domain/models/product.dart';
import '../../l10n/generated/app_localizations.dart';
import '../sale/sale_providers.dart';
import '../security/audit_providers.dart';
import '../security/pin_dialogs.dart';
import 'products_providers.dart';

/// The change "undo" would take back, if any.
final lastPriceChangeProvider = FutureProvider<PriceChangeRecord?>(
  (ref) => ref.watch(priceChangeRepositoryProvider).lastUndoable(),
);

/// After prices changed: every list that shows them.
void refreshPrices(ProviderContainer container) {
  container
    ..invalidate(productsListProvider)
    ..invalidate(favoriteProductsProvider)
    ..invalidate(saleSearchResultsProvider)
    ..invalidate(lastPriceChangeProvider)
    ..invalidate(auditLogProvider);
}

enum _Direction { raise, lower }

/// Products → "Change prices": one percentage for all products, the ones
/// priced in one currency, or a chosen few; a rounding step; a PREVIEW of
/// every old and new price; then one transaction — and one step of undo.
class BulkPriceScreen extends ConsumerStatefulWidget {
  const BulkPriceScreen({super.key});

  @override
  ConsumerState<BulkPriceScreen> createState() => _BulkPriceScreenState();
}

class _BulkPriceScreenState extends ConsumerState<BulkPriceScreen> {
  final _percent = TextEditingController();
  PriceChangeScope _scope = PriceChangeScope.all;
  String? _currency;
  Set<int> _selected = {};
  _Direction _direction = _Direction.raise;
  PriceRounding _rounding = PriceRounding.none;
  PriceChangePlan? _plan;
  bool _busy = false;
  String? _percentError;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  void _changed(VoidCallback change) => setState(() {
        change();
        _plan = null; // the preview no longer says what would happen
      });

  void _say(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  int? _basisPoints() {
    final bp = parsePercentBasisPoints(_percent.text);
    if (bp == null || bp < 0) return null;
    return _direction == _Direction.lower ? -bp : bp;
  }

  Future<void> _preview() async {
    final l10n = AppLocalizations.of(context);
    final bp = _basisPoints();
    if (bp == null || (bp < 0 && bp < minPercentBasisPoints)) {
      setState(() => _percentError = l10n.bulkPercentInvalid);
      return;
    }
    if (_scope == PriceChangeScope.selected && _selected.isEmpty) {
      _say(l10n.bulkChooseFirst);
      return;
    }
    setState(() {
      _percentError = null;
      _busy = true;
    });
    final repository = _container.read(priceChangeRepositoryProvider);
    try {
      final plan = await repository.preview(
        basisPoints: bp,
        rounding: _rounding,
        scope: _scope,
        currencyCode: _currency,
        productIds: _selected,
      );
      if (mounted) setState(() => _plan = plan);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final l10n = AppLocalizations.of(context);
    final plan = _plan;
    if (plan == null || plan.changing.isEmpty) return;
    final container = _container;
    final repository = container.read(priceChangeRepositoryProvider);
    final locale = ref.read(appLocaleProvider).languageCode;
    if (!await requirePinIfSet(context, reason: l10n.pinReasonBulkPrice)) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final changed = await repository.apply(plan);
      refreshPrices(container);
      if (!mounted) return;
      setState(() => _plan = null);
      _say(
        l10n.bulkApplied(formatMinor(changed, decimals: 0, locale: locale)),
        action: SnackBarAction(
          label: l10n.bulkUndo,
          onPressed: _undo,
        ),
      );
    } on Object {
      _say(l10n.bulkFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    final repository = container.read(priceChangeRepositoryProvider);
    final locale = ref.read(appLocaleProvider).languageCode;
    if (!await requirePinIfSet(context, reason: l10n.pinReasonBulkPrice)) {
      return;
    }
    final result = await repository.undoLast();
    refreshPrices(container);
    if (result == null) return;
    String n(int v) => formatMinor(v, decimals: 0, locale: locale);
    _say(result.skipped == 0
        ? l10n.bulkUndone(n(result.restored))
        : l10n.bulkUndoneSkipped(n(result.restored), n(result.skipped)));
  }

  Future<void> _choose() async {
    final picked = await Navigator.of(context).push(
      MaterialPageRoute<Set<int>>(
        fullscreenDialog: true,
        builder: (_) => ProductChooserScreen(initial: _selected),
      ),
    );
    if (picked == null || !mounted) return;
    _changed(() => _selected = picked);
  }

  String _price(int minor, String code, Map<String, Currency> currencies,
      String locale) {
    final currency = currencies[code];
    if (currency == null) return '$minor $code';
    return formatMinor(
      minor,
      decimals: currency.decimalPlaces,
      locale: locale,
      symbol: currency.symbol.isEmpty ? currency.code : currency.symbol,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final currencies =
        ref.watch(currencyMapProvider).value ?? const <String, Currency>{};
    final last = ref.watch(lastPriceChangeProvider).value;
    final plan = _plan;
    final changing = plan?.changing ?? const <PriceChangeLine>[];
    final currencyChoices = [
      for (final c in currencies.values)
        if (c.isActive || c.code == _currency) c.code,
    ];
    _currency ??= ref.watch(baseCurrencyCodeProvider).value;

    String roundingLabel(PriceRounding r) => switch (r) {
          PriceRounding.none => l10n.bulkRoundNone,
          _ => l10n.bulkRoundNearest(
              formatMinor(r.step, decimals: 0, locale: locale),
            ),
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.bulkTitle)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          key: const ValueKey('bulk-price'),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (last != null)
              Card(
                key: const ValueKey('bulk-last'),
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text(l10n.bulkLast(
                    ltrIsolate(formatBasisPoints(last.basisPoints)),
                    formatMinor(last.productCount, decimals: 0, locale: locale),
                  )),
                  subtitle: Text(DateFormat.yMd(locale)
                      .add_jm()
                      .format(last.createdAt.toLocal())),
                  trailing: TextButton(
                    key: const ValueKey('bulk-undo'),
                    onPressed: _undo,
                    child: Text(l10n.bulkUndo),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l10n.bulkWhich, style: theme.textTheme.titleSmall),
            ),
            RadioGroup<PriceChangeScope>(
              groupValue: _scope,
              onChanged: (v) {
                if (v != null) _changed(() => _scope = v);
              },
              child: Column(
                children: [
                  RadioListTile<PriceChangeScope>(
                    key: const ValueKey('bulk-scope-all'),
                    value: PriceChangeScope.all,
                    title: Text(l10n.bulkScopeAll),
                  ),
                  // "Products priced in one currency" is a choice only
                  // where there can be more than one.
                  if (featureOn(Feature.multiCurrency))
                    RadioListTile<PriceChangeScope>(
                      key: const ValueKey('bulk-scope-currency'),
                      value: PriceChangeScope.currency,
                      title: Text(l10n.bulkScopeCurrency),
                      subtitle: _scope == PriceChangeScope.currency &&
                              currencyChoices.isNotEmpty
                          ? DropdownButton<String>(
                              key: const ValueKey('bulk-currency'),
                              value: currencyChoices.contains(_currency)
                                  ? _currency
                                  : currencyChoices.first,
                              items: [
                                for (final code in currencyChoices)
                                  DropdownMenuItem(value: code, child: Text(code)),
                              ],
                              onChanged: (v) => _changed(() => _currency = v),
                            )
                          : null,
                    ),
                  RadioListTile<PriceChangeScope>(
                    key: const ValueKey('bulk-scope-selected'),
                    value: PriceChangeScope.selected,
                    title: Text(l10n.bulkScopeSelected),
                    subtitle: _scope == PriceChangeScope.selected
                        ? Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              key: const ValueKey('bulk-choose'),
                              onPressed: _choose,
                              icon: const Icon(Icons.checklist),
                              label: Text(l10n.bulkChosen(formatMinor(
                                _selected.length,
                                decimals: 0,
                                locale: locale,
                              ))),
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SegmentedButton<_Direction>(
                segments: [
                  ButtonSegment(
                    value: _Direction.raise,
                    icon: const Icon(Icons.trending_up),
                    label: Text(l10n.bulkRaise),
                  ),
                  ButtonSegment(
                    value: _Direction.lower,
                    icon: const Icon(Icons.trending_down),
                    label: Text(l10n.bulkLower),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => _changed(() => _direction = s.first),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                key: const ValueKey('bulk-percent'),
                controller: _percent,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _changed(() => _percentError = null),
                decoration: InputDecoration(
                  labelText: l10n.bulkPercentLabel,
                  suffixText: '%',
                  errorText: _percentError,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(l10n.bulkRounding, style: theme.textTheme.titleSmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final r in PriceRounding.values)
                    ChoiceChip(
                      key: ValueKey('bulk-round-${r.step}'),
                      label: Text(roundingLabel(r)),
                      selected: _rounding == r,
                      onSelected: (_) => _changed(() => _rounding = r),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                l10n.bulkRoundingHint,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton.icon(
                key: const ValueKey('bulk-preview'),
                onPressed: _busy ? null : _preview,
                icon: const Icon(Icons.preview_outlined),
                label: Text(l10n.bulkPreview),
              ),
            ),
            if (plan != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.bulkPreviewCount(
                    formatMinor(changing.length, decimals: 0, locale: locale),
                    formatMinor(plan.lines.length, decimals: 0, locale: locale),
                  ),
                  key: const ValueKey('bulk-preview-count'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              for (final line in changing)
                ListTile(
                  key: ValueKey('bulk-line-${line.productId}'),
                  dense: true,
                  title: Text(line.name),
                  subtitle: Row(
                    children: [
                      Flexible(
                        child: Text(
                          _price(line.oldPriceMinor, line.currencyCode,
                              currencies, locale),
                          style: const TextStyle(
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, size: 14),
                      ),
                      Flexible(
                        child: Text(
                          _price(line.newPriceMinor, line.currencyCode,
                              currencies, locale),
                          key: ValueKey('bulk-new-${line.productId}'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: FilledButton.icon(
                  key: const ValueKey('bulk-apply'),
                  onPressed: _busy || changing.isEmpty ? null : _apply,
                  icon: const Icon(Icons.check),
                  label: Text(l10n.bulkApply(
                    formatMinor(changing.length, decimals: 0, locale: locale),
                  )),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The products to change, ticked from a searchable list. Pops the ids.
class ProductChooserScreen extends ConsumerStatefulWidget {
  const ProductChooserScreen({super.key, this.initial = const {}});

  final Set<int> initial;

  @override
  ConsumerState<ProductChooserScreen> createState() =>
      _ProductChooserScreenState();
}

class _ProductChooserScreenState extends ConsumerState<ProductChooserScreen> {
  late final Set<int> _picked = {...widget.initial};
  final _search = TextEditingController();
  List<Product>? _products;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repository = ref.read(productRepositoryProvider);
    final products = await repository.list(includeInactive: true);
    if (mounted) setState(() => _products = products);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final all = _products;
    final q = _query.trim().toLowerCase();
    final shown = all == null
        ? const <Product>[]
        : [
            for (final p in all)
              if (q.isEmpty ||
                  p.name.toLowerCase().contains(q) ||
                  (p.code ?? '').toLowerCase().contains(q))
                p,
          ];
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.bulkChosen(
          formatMinor(_picked.length, decimals: 0, locale: locale),
        )),
        actions: [
          TextButton(
            key: const ValueKey('bulk-chooser-done'),
            onPressed: () => Navigator.of(context).pop(_picked),
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            child: Text(l10n.done),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: l10n.searchProductsHint,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(
                  () => _picked.addAll([for (final p in shown) p.id!]),
                ),
                child: Text(l10n.bulkSelectAllShown),
              ),
              TextButton(
                onPressed: () => setState(_picked.clear),
                child: Text(l10n.bulkSelectNone),
              ),
            ],
          ),
          Expanded(
            child: all == null
                ? const SizedBox.shrink()
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, index) {
                      final p = shown[index];
                      return CheckboxListTile(
                        key: ValueKey('bulk-pick-${p.id}'),
                        value: _picked.contains(p.id),
                        title: Text(p.name),
                        subtitle: p.code == null ? null : Text('#${p.code}'),
                        onChanged: (on) => setState(() {
                          on == true ? _picked.add(p.id!) : _picked.remove(p.id);
                        }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
