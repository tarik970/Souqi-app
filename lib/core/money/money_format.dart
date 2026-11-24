/// Locale-aware display formatting and parsing of money amounts.
/// Display only — all arithmetic stays in integer minor units.
library;

import 'package:intl/intl.dart';

import '../utils/normalize.dart';
import 'exchange.dart';

int _pow10(int exp) {
  var v = 1;
  for (var i = 0; i < exp; i++) {
    v *= 10;
  }
  return v;
}

/// Formats [minor] minor units as a localized number with [decimals]
/// fraction digits (grouping, decimal separator and digit shapes follow
/// [locale], e.g. Arabic-Indic digits and '٫' for 'ar').
String formatMinor(
  int minor, {
  required int decimals,
  required String locale,
  String symbol = '',
}) {
  final nf = NumberFormat.decimalPattern(locale);
  final p = _pow10(decimals);
  final abs = minor.abs();
  var text = nf.format(abs ~/ p);
  if (decimals > 0) {
    final frac = (abs % p).toString().padLeft(decimals, '0');
    text = '$text${nf.symbols.DECIMAL_SEP}${_localizeDigits(frac, nf)}';
  }
  if (minor < 0) {
    text = '${nf.symbols.MINUS_SIGN}$text';
  }
  return symbol.isEmpty ? text : '$text $symbol';
}

String _localizeDigits(String asciiDigits, NumberFormat nf) {
  final zero = nf.symbols.ZERO_DIGIT.codeUnitAt(0);
  if (zero == 0x30) return asciiDigits;
  return String.fromCharCodes(
    asciiDigits.codeUnits.map((c) => zero + (c - 0x30)),
  );
}

/// Replaces the ASCII digits in [text] with [locale]'s digit shapes and the
/// '.' with its decimal separator. For on-screen keypads and the text the
/// user is typing into them — display only.
String localizeDigits(String text, String locale) {
  final nf = NumberFormat.decimalPattern(locale);
  final out = StringBuffer();
  for (final char in text.split('')) {
    if (char == '.') {
      out.write(nf.symbols.DECIMAL_SEP);
    } else if (char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39) {
      out.write(_localizeDigits(char, nf));
    } else {
      out.write(char);
    }
  }
  return out.toString();
}

/// The locale's decimal separator, for the keypad's decimal key.
String decimalSeparator(String locale) =>
    NumberFormat.decimalPattern(locale).symbols.DECIMAL_SEP;

/// Formats a quantity held as INTEGER thousandths (500 → "0.5"), dropping
/// trailing zeros, localized for display.
String formatQuantity(int qtyThousandths, {required String locale}) {
  final nf = NumberFormat.decimalPattern(locale);
  final abs = qtyThousandths.abs();
  var frac = (abs % 1000).toString().padLeft(3, '0');
  while (frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  var text = nf.format(abs ~/ 1000);
  if (frac.isNotEmpty) {
    text = '$text${nf.symbols.DECIMAL_SEP}${_localizeDigits(frac, nf)}';
  }
  return qtyThousandths < 0 ? '${nf.symbols.MINUS_SIGN}$text' : text;
}

/// Plain ASCII text of a quantity for prefilling a keypad buffer ("0.5", "2").
String quantityToPlainText(int qtyThousandths) {
  final sign = qtyThousandths < 0 ? '-' : '';
  final abs = qtyThousandths.abs();
  var frac = (abs % 1000).toString().padLeft(3, '0');
  while (frac.endsWith('0')) {
    frac = frac.substring(0, frac.length - 1);
  }
  return frac.isEmpty ? '$sign${abs ~/ 1000}' : '$sign${abs ~/ 1000}.$frac';
}

/// Parses a user-entered quantity into INTEGER thousandths. Returns null for
/// invalid input or more than 3 decimal places.
int? parseQuantityThousandths(String input) =>
    parseAmountMinor(input, decimals: 3);

/// Renders an exact rate fraction as the decimal number the user entered
/// ("13000", "0.0000769"), localized. Expanded with exact integer division —
/// rates never go through double.
String formatRateValue(RateFraction rate, {required String locale}) {
  final nf = NumberFormat.decimalPattern(locale);
  final den = BigInt.from(rate.denominator);
  final whole = BigInt.from(rate.numerator) ~/ den;
  var rem = BigInt.from(rate.numerator) % den;
  final text = nf.format(whole.toInt());
  if (rem == BigInt.zero) return text;
  final frac = StringBuffer();
  final ten = BigInt.from(10);
  for (var i = 0; i < 12 && rem != BigInt.zero; i++) {
    rem *= ten;
    frac.write((rem ~/ den).toString());
    rem %= den;
  }
  var digits = frac.toString();
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }
  if (digits.isEmpty) return text;
  return '$text${nf.symbols.DECIMAL_SEP}${_localizeDigits(digits, nf)}';
}

/// Plain ASCII text of a rate for prefilling an edit field ("13000", "0.5").
String rateToPlainText(RateFraction rate) {
  final den = BigInt.from(rate.denominator);
  final numerator = BigInt.from(rate.numerator);
  final whole = numerator ~/ den;
  var rem = numerator % den;
  if (rem == BigInt.zero) return '$whole';
  final frac = StringBuffer();
  final ten = BigInt.from(10);
  for (var i = 0; i < 12 && rem != BigInt.zero; i++) {
    rem *= ten;
    frac.write((rem ~/ den).toString());
    rem %= den;
  }
  var digits = frac.toString();
  while (digits.endsWith('0')) {
    digits = digits.substring(0, digits.length - 1);
  }
  return digits.isEmpty ? '$whole' : '$whole.$digits';
}

/// Plain ASCII text of [minor] for prefilling edit fields ("2.50", "1500").
/// No grouping, no localization — [formatMinor] is for display.
String minorToPlainText(int minor, {required int decimals}) {
  final sign = minor < 0 ? '-' : '';
  final abs = minor.abs();
  final p = _pow10(decimals);
  if (decimals == 0) return '$sign$abs';
  return '$sign${abs ~/ p}.${(abs % p).toString().padLeft(decimals, '0')}';
}

final _amountPattern = RegExp(r'^[0-9]+(\.[0-9]*)?$|^\.[0-9]+$');

/// Parses a user-entered amount ("1500", "2.50", Arabic-Indic digits,
/// '٫' or ',' separators) into minor units with [decimals] places.
/// Returns null for invalid input or more fraction digits than [decimals].
int? parseAmountMinor(String input, {required int decimals}) {
  var s = normalizeDigits(input.trim())
      .replaceAll('٫', '.')
      .replaceAll(',', '.');
  if (s.isEmpty || !_amountPattern.hasMatch(s)) return null;
  final dot = s.indexOf('.');
  final intPart = dot < 0 ? s : s.substring(0, dot);
  var fracPart = dot < 0 ? '' : s.substring(dot + 1);
  if (fracPart.length > decimals) return null;
  fracPart = fracPart.padRight(decimals, '0');
  final digits = '$intPart$fracPart';
  if (digits.length > 15) return null;
  return int.parse(digits.isEmpty ? '0' : digits);
}
