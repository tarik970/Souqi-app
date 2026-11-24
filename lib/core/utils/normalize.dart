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

/// Converts a phone number the way a shop owner types it into the
/// international form a WhatsApp chat link needs: digits only, country code
/// first, no '+' and no '00'.
///
///   0944 123 456        → 963944123456   (trunk zero replaced by the code)
///   +963 944 123 456    → 963944123456
///   00963944123456      → 963944123456
///   ٠٩٤٤١٢٣٤٥٦          → 963944123456   (Arabic-Indic digits)
///   +963 (0) 944 123456 → 963944123456   (trunk zero typed after the code)
///
/// Returns null when the result cannot be a phone number (E.164 allows at
/// most 15 digits; fewer than 8 is not a subscriber number anywhere).
String? toInternationalPhone(
  String input, {
  String defaultCountryCode = '963',
}) {
  final raw = normalizeDigits(input.trim());
  final hasPlus = raw.startsWith('+');
  var digits = normalizePhone(raw);
  if (digits.isEmpty) return null;
  final cc = normalizePhone(defaultCountryCode).replaceFirst(RegExp('^0+'), '');

  if (hasPlus) {
    // Already international.
  } else if (digits.startsWith('00')) {
    digits = digits.substring(2);
  } else if (digits.startsWith('0')) {
    digits = '$cc${digits.substring(1)}';
  } else if (cc.isNotEmpty &&
      digits.startsWith(cc) &&
      digits.length >= cc.length + 7) {
    // International, typed without '+' or '00'.
  } else {
    digits = '$cc$digits';
  }

  if (cc.isNotEmpty && digits.startsWith('${cc}0')) {
    digits = '$cc${digits.substring(cc.length + 1)}';
  }
  if (digits.length < 8 || digits.length > 15) return null;
  return digits;
}

/// Hides everything but the last four characters of an account / card number
/// for printing ("0011-2233-4455" → "****-****-4455"). Spaces and dashes are
/// kept so the grouping stays readable. Four characters or fewer are returned
/// unchanged — there would be nothing left to recognise the account by.
String maskAllButLast4(String input, {String maskChar = '*'}) {
  final chars = input.split('');
  final maskable = <int>[
    for (var i = 0; i < chars.length; i++)
      if (!_spacesAndDashes.hasMatch(chars[i])) i,
  ];
  if (maskable.length <= 4) return input;
  for (final index in maskable.take(maskable.length - 4)) {
    chars[index] = maskChar;
  }
  return chars.join();
}
