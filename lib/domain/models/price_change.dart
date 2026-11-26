/// Bulk price change: raise or lower many saved prices by one percentage,
/// with an optional rounding step — and the record that undoes it.
///
/// Pure: the math is unit-tested directly. Prices are INTEGER minor units of
/// each product's own currency (see the data rules); the percentage is kept
/// in BASIS POINTS (1/100 of a percent: +7.5 % = 750) so it is exact too.
library;

import '../../core/money/rounding.dart';
import '../../core/utils/normalize.dart';

/// The rounding step, in MINOR units of the product's own currency: for a
/// 0-decimal currency (SYP) "nearest 500" is 500 pounds; for a 2-decimal one
/// (USD) it is 500 cents, i.e. 5.00 — so one choice makes sense for both.
enum PriceRounding {
  none(1),
  nearest50(50),
  nearest100(100),
  nearest500(500),
  nearest1000(1000);

  const PriceRounding(this.step);

  final int step;

  static PriceRounding fromStep(int step) =>
      values.firstWhere((r) => r.step == step, orElse: () => none);
}

/// Which products a bulk change is about.
enum PriceChangeScope {
  all('ALL'),
  currency('CURRENCY'),
  selected('SELECTED');

  const PriceChangeScope(this.db);

  final String db;

  static PriceChangeScope fromDb(String? value) =>
      values.firstWhere((s) => s.db == value, orElse: () => all);
}

/// The smallest and largest percentage accepted. −100 % would make every
/// price zero; more than +1000 % is a typo, not a price change.
const int minPercentBasisPoints = -9999;
const int maxPercentBasisPoints = 100000;

/// "+10", "-7.5", "٥", "12,5" → basis points (1000, -750, 500, 1250). Null
/// when it is not a percentage, is zero, or is out of range.
int? parsePercentBasisPoints(String input) {
  var text = normalizeDigits(input.trim())
      .replaceAll('%', '')
      .replaceAll('٪', '')
      .replaceAll('٫', '.')
      .replaceAll(',', '.')
      .replaceAll(' ', '');
  // The Arabic minus and the en dash some keyboards give for "-".
  text = text.replaceAll('−', '-').replaceAll('–', '-');
  final match = RegExp(r'^([+-]?)(\d{1,5})(?:\.(\d{1,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = int.parse(match[2]!);
  final fraction = (match[3] ?? '').padRight(2, '0');
  var bp = whole * 100 + (fraction.isEmpty ? 0 : int.parse(fraction));
  if (match[1] == '-') bp = -bp;
  if (bp == 0 || bp < minPercentBasisPoints || bp > maxPercentBasisPoints) {
    return null;
  }
  return bp;
}

/// The new price: `old × (1 + percent)` rounded ONCE, half-up, to the
/// [rounding] step. A price that was not zero never becomes zero (it stops at
/// one step); a zero price stays zero — "free" is not a price to scale.
int bulkNewPrice(int oldMinor, int basisPoints, PriceRounding rounding) {
  if (oldMinor <= 0) return oldMinor;
  final step = rounding.step;
  final scaled = divRoundHalfUp(
    BigInt.from(oldMinor) * BigInt.from(10000 + basisPoints),
    BigInt.from(10000) * BigInt.from(step),
  );
  final result = scaled * step;
  return result < step ? step : result;
}

/// One product in the preview (and in the undo record).
class PriceChangeLine {
  const PriceChangeLine({
    required this.productId,
    required this.name,
    required this.currencyCode,
    required this.oldPriceMinor,
    required this.newPriceMinor,
  });

  final int productId;
  final String name;
  final String currencyCode;
  final int oldPriceMinor;
  final int newPriceMinor;

  bool get changes => oldPriceMinor != newPriceMinor;
}

/// What the preview shows before anything is written.
class PriceChangePlan {
  const PriceChangePlan({
    required this.basisPoints,
    required this.rounding,
    required this.scope,
    this.scopeCurrency,
    required this.lines,
  });

  final int basisPoints;
  final PriceRounding rounding;
  final PriceChangeScope scope;
  final String? scopeCurrency;

  /// Every product in scope, changing or not, by name.
  final List<PriceChangeLine> lines;

  List<PriceChangeLine> get changing => [
        for (final line in lines)
          if (line.changes) line,
      ];
}

/// Builds the plan from the products in scope (id, name, currency, price).
PriceChangePlan planBulkPriceChange({
  required Iterable<({int id, String name, String currencyCode, int priceMinor})>
      products,
  required int basisPoints,
  required PriceRounding rounding,
  required PriceChangeScope scope,
  String? scopeCurrency,
}) =>
    PriceChangePlan(
      basisPoints: basisPoints,
      rounding: rounding,
      scope: scope,
      scopeCurrency: scopeCurrency,
      lines: [
        for (final p in products)
          PriceChangeLine(
            productId: p.id,
            name: p.name,
            currencyCode: p.currencyCode,
            oldPriceMinor: p.priceMinor,
            newPriceMinor: bulkNewPrice(p.priceMinor, basisPoints, rounding),
          ),
      ],
    );

/// The last bulk change, as kept for "undo".
class PriceChangeRecord {
  const PriceChangeRecord({
    required this.id,
    required this.createdAt,
    required this.basisPoints,
    required this.rounding,
    required this.scope,
    this.scopeCurrency,
    required this.productCount,
  });

  final int id;
  final DateTime createdAt;
  final int basisPoints;
  final PriceRounding rounding;
  final PriceChangeScope scope;
  final String? scopeCurrency;
  final int productCount;
}

/// What an undo did: prices put back, and products left alone because their
/// price was changed again since (by hand or by a sale) or they are gone.
class PriceUndoResult {
  const PriceUndoResult({required this.restored, required this.skipped});

  final int restored;
  final int skipped;
}

/// "+10 %", "−7.5 %".
String formatBasisPoints(int bp) {
  final sign = bp < 0 ? '−' : '+';
  final abs = bp.abs();
  final whole = abs ~/ 100;
  final fraction = abs % 100;
  final text = fraction == 0
      ? '$whole'
      : '$whole.${fraction.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '')}';
  return '$sign$text %';
}
