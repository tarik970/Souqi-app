/// Text normalizers used for search columns and voucher-code hashing.
///
/// Normalized values are stored in dedicated `*_norm` columns; the original
/// text is always stored exactly as entered.
library;

const _arabicIndicZero = 0x0660; // ٠..٩
const _extendedArabicIndicZero = 0x06F0; // ۰..۹ (Persian/Urdu keyboards)
const _asciiZero = 0x30;

/// Converts Arabic-Indic (٠-٩) and Extended Arabic-Indic (۰-۹) digits to 0-9.
/// All other characters pass through unchanged.
String normalizeDigits(String input) {
  final codes = input.codeUnits;
  StringBuffer? out;
  for (var i = 0; i < codes.length; i++) {
    final c = codes[i];
    int mapped = c;
    if (c >= _arabicIndicZero && c <= _arabicIndicZero + 9) {
      mapped = _asciiZero + (c - _arabicIndicZero);
    } else if (c >= _extendedArabicIndicZero &&
        c <= _extendedArabicIndicZero + 9) {
      mapped = _asciiZero + (c - _extendedArabicIndicZero);
    }
    if (mapped != c && out == null) {
      out = StringBuffer(input.substring(0, i));
    }
    out?.writeCharCode(mapped);
  }
  return out?.toString() ?? input;
}

/// Phone normalization: digits only (after Arabic-Indic conversion).
/// Everything that is not 0-9 is removed.
String normalizePhone(String input) {
  return normalizeDigits(input).replaceAll(RegExp(r'[^0-9]'), '');
}

final _spacesAndDashes = RegExp(r'[\s \-‐‑‒–—]');

/// Account-number / voucher-code normalization (ALPHANUMERIC):
/// trim, remove spaces and dashes, convert Arabic-Indic digits to 0-9,
/// uppercase letters. Letters are never stripped.
String normalizeCode(String input) {
  return normalizeDigits(input.trim())
      .replaceAll(_spacesAndDashes, '')
      .toUpperCase();
}

/// Name normalization for search columns (products, customers):
/// trim, collapse internal whitespace, convert Arabic-Indic digits, lowercase.
String normalizeName(String input) {
  return normalizeDigits(input.trim())
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();
}
