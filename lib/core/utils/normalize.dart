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

/// A voucher code the way it is PRINTED and compared by eye: trimmed, no
/// spaces or dashes, Arabic-Indic digits as 0-9. Unlike [normalizeCode] the
/// letters keep their case — that form is only for hashing and lookup, while
/// this one is what the customer types into the provider's page.
String stripCodeSeparators(String input) =>
    normalizeDigits(input.trim()).replaceAll(_spacesAndDashes, '');

/// Inclusive code-unit ranges dropped from names: tatweel, Arabic diacritics
/// (tashkeel, Quranic marks, superscript alef) and the invisible direction /
/// joiner marks keyboards sometimes insert. Written as numbers on purpose:
/// literal invisible characters in source code are a trap.
const _nameNoiseRanges = <(int, int)>[
  (0x0640, 0x0640), // tatweel
  (0x0610, 0x061A),
  (0x064B, 0x065F), // the common tashkeel
  (0x0670, 0x0670), // superscript alef
  (0x06D6, 0x06DC),
  (0x06DF, 0x06E8),
  (0x06EA, 0x06ED),
  (0x200B, 0x200F), // zero-width space and joiners, LRM, RLM
  (0x202A, 0x202E), // direction embeddings
  (0x2066, 0x2069), // direction isolates
  (0xFEFF, 0xFEFF),
];

bool _isNameNoise(int codeUnit) {
  for (final (from, to) in _nameNoiseRanges) {
    if (codeUnit >= from && codeUnit <= to) return true;
  }
  return false;
}

String _stripNameNoise(String input) {
  if (!input.codeUnits.any(_isNameNoise)) return input;
  return String.fromCharCodes(input.codeUnits.where((c) => !_isNameNoise(c)));
}

/// Letters the same word is commonly typed with, folded to one spelling.
const _arabicFold = <String, String>{
  'أ': 'ا',
  'إ': 'ا',
  'آ': 'ا',
  'ٱ': 'ا',
  'ة': 'ه',
  'ى': 'ي',
  // Persian / Urdu keyboard variants of the same letters.
  'ی': 'ي',
  'ک': 'ك',
};

final _arabicFoldPattern = RegExp('[${_arabicFold.keys.join()}]');

/// Name normalization for search columns and the duplicate-product guard
/// (products, customers). Two names that normalize to the same text are the
/// same name as far as the app is concerned:
///
/// - trim and collapse internal whitespace;
/// - Arabic-Indic digits → 0-9, Latin letters lowercased;
/// - tatweel and diacritics removed ("سُكَّر" = "سكر", "ســكر" = "سكر");
/// - أ / إ / آ → ا, ة → ه, ى → ي;
/// - a leading "ال" dropped from every word ("السكر الناعم" = "سكر ناعم"),
///   as long as at least two letters remain, so short words that merely
///   start with those letters ("الف" from "ألف") are left alone.
///
/// Stored in `name_norm`; the search query goes through the same function,
/// which is what makes "السكر" find "سكر".
String normalizeName(String input) {
  final folded = _stripNameNoise(normalizeDigits(input))
      .replaceAllMapped(_arabicFoldPattern, (m) => _arabicFold[m[0]]!)
      .toLowerCase()
      .trim();
  if (folded.isEmpty) return '';
  return folded.split(RegExp(r'\s+')).map((word) {
    return word.length >= 4 && word.startsWith('ال') ? word.substring(2) : word;
  }).join(' ');
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

final _phoneShaped = RegExp(r'^[0-9\s\-‐‑‒–—+()./]+$');

/// Whether [input] can be a phone number, or the beginning of one, at all:
/// digits with nothing but the punctuation phones are written with. Text
/// with a letter in it ("MTN-123") is a name or an account number, never a
/// phone.
bool looksLikePhone(String input) {
  final text = normalizeDigits(input.trim());
  return _phoneShaped.hasMatch(text) && text.contains(RegExp('[0-9]'));
}

/// The digits to look for inside a stored `phone_norm` so that a number is
/// found however it — and the stored one — was typed: with the trunk zero
/// ("0944 123 456"), with the country code ("+963 944 123 456",
/// "00963944123456") or bare.
///
/// The stored column keeps the digits exactly as entered, so the one thing
/// every spelling of a number shares is its subscriber part. This strips the
/// international prefix and the trunk zero from the typed text and returns
/// what is left; a "contains" match on that finds all the spellings.
///
/// Returns '' when [input] is not phone-shaped (see [looksLikePhone]).
///
/// Deliberately cautious, because the same box also searches card numbers
/// and those often start with zeros: "00" is only an international prefix
/// when the country code follows it, and the trunk zero is only dropped
/// once seven digits are typed. Until then the digits are searched exactly
/// as typed, so "0011" still means 0011.
String phoneSearchKey(String input, {String countryCode = '963'}) {
  if (!looksLikePhone(input)) return '';
  final raw = normalizeDigits(input.trim());
  var digits = normalizePhone(raw);
  final cc = normalizePhone(countryCode).replaceFirst(RegExp('^0+'), '');
  if (cc.isNotEmpty) {
    if (digits.startsWith('00$cc')) {
      digits = digits.substring(2 + cc.length);
    } else if (digits.startsWith(cc) &&
        (raw.startsWith('+') || digits.length >= cc.length + 7)) {
      digits = digits.substring(cc.length);
    }
  }
  if (digits.length >= 7 && digits.startsWith('0')) {
    digits = digits.substring(1);
  }
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
