/// Currency conversion with exact-fraction exchange rates.
///
/// A rate is stored as two positive integers (rate_num, rate_den) meaning
/// "rate_num/rate_den BASE units per 1 unit of this currency", exactly as the
/// user entered it. All conversions run through BigInt with ONE half-up
/// rounding step at the end, to the target currency's decimal places.
library;

import 'quantity.dart';
import 'rounding.dart';

import '../utils/normalize.dart';

/// An exact exchange rate to the base currency.
class RateFraction {
  final int numerator;
  final int denominator;

  const RateFraction(this.numerator, this.denominator)
      : assert(numerator > 0, 'rate numerator must be > 0'),
        assert(denominator > 0, 'rate denominator must be > 0');

  /// The base currency's own rate.
  static const RateFraction one = RateFraction(1, 1);

  @override
  bool operator ==(Object other) =>
      other is RateFraction &&
      other.numerator == numerator &&
      other.denominator == denominator;

  @override
  int get hashCode => Object.hash(numerator, denominator);

  @override
  String toString() => '$numerator/$denominator';
}

BigInt _pow10(int exp) => BigInt.from(10).pow(exp);

/// Converts [amountMinor] (minor units of the source currency) into minor
/// units of the target currency. Decimals are each currency's
/// `decimal_places`; rates are each currency's rate to the base currency.
///
///   value = amountMinor
///         * fromRate.num * toRate.den * 10^toDecimals
///         / (fromRate.den * toRate.num * 10^fromDecimals)
int convertMinor({
  required int amountMinor,
  required int fromDecimals,
  required RateFraction fromRate,
  required int toDecimals,
  required RateFraction toRate,
}) {
  final numerator = BigInt.from(amountMinor) *
      BigInt.from(fromRate.numerator) *
      BigInt.from(toRate.denominator) *
      _pow10(toDecimals);
  final denominator = BigInt.from(fromRate.denominator) *
      BigInt.from(toRate.numerator) *
      _pow10(fromDecimals);
  return divRoundHalfUp(numerator, denominator);
}

/// A line total converted into another currency with a SINGLE rounding step.
///
/// Price × quantity × the rate all happen inside one BigInt fraction, so the
/// result is rounded once at the end:
///
///   value = unitPriceMinor * qtyThousandths
///         * fromRate.num * toRate.den * 10^toDecimals
///         / (1000 * fromRate.den * toRate.num * 10^fromDecimals)
///
/// Rounding the converted unit price first and then multiplying by the
/// quantity would multiply that rounding error by the quantity: 5000 SYP × 10
/// at 13000 SYP/USD is 3.85 USD, not 10 × 0.38 = 3.80 USD.
///
/// With the same currency on both sides this reduces exactly to
/// [lineTotalMinor] — `round(price * qty / 1000)`.
int convertLineTotalMinor({
  required int unitPriceMinor,
  required int qtyThousandths,
  required int fromDecimals,
  required RateFraction fromRate,
  required int toDecimals,
  required RateFraction toRate,
}) {
  if (qtyThousandths < 0) {
    throw ArgumentError.value(qtyThousandths, 'qtyThousandths', 'must be >= 0');
  }
  final numerator = BigInt.from(unitPriceMinor) *
      BigInt.from(qtyThousandths) *
      BigInt.from(fromRate.numerator) *
      BigInt.from(toRate.denominator) *
      _pow10(toDecimals);
  final denominator = BigInt.from(quantityScale) *
      BigInt.from(fromRate.denominator) *
      BigInt.from(toRate.numerator) *
      _pow10(fromDecimals);
  return divRoundHalfUp(numerator, denominator);
}

/// Converts minor units of a currency into minor units of the BASE currency.
int toBaseMinor({
  required int amountMinor,
  required int fromDecimals,
  required RateFraction fromRate,
  required int baseDecimals,
}) {
  return convertMinor(
    amountMinor: amountMinor,
    fromDecimals: fromDecimals,
    fromRate: fromRate,
    toDecimals: baseDecimals,
    toRate: RateFraction.one,
  );
}

final _ratePattern = RegExp(r'^[0-9]+(\.[0-9]+)?$');

/// Parses a user-entered decimal rate ("13000", "0.0000769", "1.5", with
/// Western or Arabic-Indic digits, '.', ',' or '٫' as decimal separator)
/// into an exact reduced fraction. Throws [FormatException] for anything
/// else, for zero, or for inputs too long to stay exact in 64-bit math.
RateFraction parseRateFraction(String input) {
  var s = normalizeDigits(input.trim())
      .replaceAll('٫', '.') // Arabic decimal separator
      .replaceAll(',', '.');
  if (!_ratePattern.hasMatch(s)) {
    throw FormatException('invalid rate', input);
  }
  final dot = s.indexOf('.');
  final digits = dot < 0 ? s : s.substring(0, dot) + s.substring(dot + 1);
  final fracLen = dot < 0 ? 0 : s.length - dot - 1;
  if (digits.length > 15 || fracLen > 12) {
    throw FormatException('rate has too many digits', input);
  }
  var num = BigInt.parse(digits);
  var den = _pow10(fracLen);
  if (num == BigInt.zero) {
    throw FormatException('rate must be greater than zero', input);
  }
  final g = num.gcd(den);
  num = num ~/ g;
  den = den ~/ g;
  return RateFraction(num.toInt(), den.toInt());
}
