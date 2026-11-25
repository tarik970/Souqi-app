import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/money/quantity.dart';
import '../../core/providers.dart';
import '../../domain/models/cart.dart';
import '../../l10n/generated/app_localizations.dart';
import 'sale_providers.dart';

/// The sheet's outcome: null result means "cancelled", a result holding a null
/// discount means "remove the discount".
class DiscountResult {
  const DiscountResult(this.discount);

  final Discount? discount;
}

Future<DiscountResult?> showDiscountSheet(BuildContext context) {
  return showModalBottomSheet<DiscountResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const DiscountSheet(),
  );
}

/// Per-invoice discount: a fixed amount in the invoice currency or a
/// percentage, with the resulting total shown live.
class DiscountSheet extends ConsumerStatefulWidget {
  const DiscountSheet({super.key});

  @override
  ConsumerState<DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends ConsumerState<DiscountSheet> {
  final _controller = TextEditingController();
  DiscountType _type = DiscountType.amount;
  bool _initialized = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Percentages are entered with 2 decimals (12.5% → 1250 basis points).
  int? _parse(int currencyDecimals) {
    return switch (_type) {
      DiscountType.amount =>
        parseAmountMinor(_controller.text, decimals: currencyDecimals),
      DiscountType.percent => switch (
            parseAmountMinor(_controller.text, decimals: 2)) {
          null => null,
          final basisPoints when basisPoints > 10000 => null,
          final basisPoints => basisPoints,
        },
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final totals = ref.watch(cartTotalsProvider);
    if (totals == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final currency = totals.currency;
    final symbol =
        currency.symbol.isEmpty ? currency.code : currency.symbol;

    if (!_initialized) {
      _initialized = true;
      final existing = ref.read(cartProvider).discount;
      if (existing != null) {
        _type = existing.type;
        _controller.text = switch (existing.type) {
          DiscountType.amount => minorToPlainText(
              existing.value,
              decimals: currency.decimalPlaces,
            ),
          DiscountType.percent => minorToPlainText(existing.value, decimals: 2),
        };
      }
    }

    final value = _parse(currency.decimalPlaces);
    final rawDiscount = value == null
        ? 0
        : switch (_type) {
            DiscountType.amount => value,
            DiscountType.percent => percentDiscountMinor(
                subtotalMinor: totals.subtotalMinor,
                basisPoints: value,
              ),
          };
    final capped = rawDiscount > totals.subtotalMinor;
    final discountMinor = capped ? totals.subtotalMinor : rawDiscount;

    String money(int minor) => formatMinor(
          minor,
          decimals: currency.decimalPlaces,
          locale: locale,
          symbol: symbol,
        );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.discountTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: 16),
          SegmentedButton<DiscountType>(
            segments: [
              ButtonSegment(
                value: DiscountType.amount,
                label: Text(l10n.discountTypeAmount),
              ),
              ButtonSegment(
                value: DiscountType.percent,
                label: Text(l10n.discountTypePercent),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (selection) =>
                setState(() => _type = selection.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.discountLabel,
              border: const OutlineInputBorder(),
              suffixText: _type == DiscountType.amount ? symbol : '%',
              errorText: _controller.text.trim().isEmpty || value != null
                  ? null
                  : l10n.invalidDiscount,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          _Row(label: l10n.subtotalLabel, value: money(totals.subtotalMinor)),
          _Row(label: l10n.discountLabel, value: '− ${money(discountMinor)}'),
          const Divider(),
          _Row(
            label: l10n.totalLabel,
            value: money(totals.subtotalMinor - discountMinor),
            emphasize: true,
          ),
          if (capped)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.discountCappedNote,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context)
                      .pop(const DiscountResult(null)),
                  child: Text(l10n.discountNone),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: value == null
                      ? null
                      : () => Navigator.of(context).pop(DiscountResult(
                            _type == DiscountType.amount
                                ? Discount.amount(value)
                                : Discount.percent(value),
                          )),
                  child: Text(l10n.save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasize
        ? theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            // The label gives way first: at a large system font "Subtotal"
            // plus the amount is wider than a narrow phone.
            Expanded(
              child: Text(
                label,
                style: style,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            // And an amount in the millions is scaled down to what is left
            // rather than overflowing — it is never cut short.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerEnd,
                child: Text(value, style: style, maxLines: 1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
