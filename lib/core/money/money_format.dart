/// Locale-aware display formatting and parsing of money amounts.
/// Display only — all arithmetic stays in integer minor units.
library;

import 'package:intl/intl.dart';

import '../utils/normalize.dart';

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
