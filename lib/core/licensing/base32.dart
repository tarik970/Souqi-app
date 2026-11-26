/// Crockford base32 — the text form of every licensing code (the request
/// code, the activation code, the PIN reset code).
///
/// SHARED FILE: an identical copy lives in the developer's key generator
/// (../souqi_keygen/lib/src/base32.dart). Change both or neither; the test
/// vectors (license_vectors.json, also in both projects) catch a drift.
///
/// Pure Dart on purpose: no Flutter, no package of the app.
library;

import 'dart:typed_data';

/// No I, L, O or U: a code read aloud or off a screen cannot turn into
/// another valid code.
const String licenseAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Bytes as text: five bits a character, the first bit of the first byte
/// first, the last character padded with zero bits. No '=' padding.
String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | (byte & 0xFF);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(licenseAlphabet[(buffer >> bits) & 31]);
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(licenseAlphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// The bytes behind [text], which must already be normalized (see
/// [normalizeCodeText]). Null for anything that [base32Encode] could not
/// have written: a character outside the alphabet, a length no whole number
/// of bytes gives, or padding bits that are not zero.
Uint8List? base32Decode(String text) {
  final spare = (text.length * 5) % 8;
  if (spare >= 5) return null;
  final out = Uint8List((text.length * 5) ~/ 8);
  var buffer = 0;
  var bits = 0;
  var at = 0;
  for (var i = 0; i < text.length; i++) {
    final value = licenseAlphabet.indexOf(text[i]);
    if (value < 0) return null;
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out[at++] = (buffer >> bits) & 0xFF;
      buffer &= (1 << bits) - 1;
    }
  }
  if (buffer != 0) return null;
  return out;
}

/// A code as typed, pasted or scanned, made decodable: everything that is
/// not a letter or a digit is dropped (spaces, dashes, line breaks, the
/// invisible direction marks a chat app adds), letters become upper case,
/// Arabic-Indic digits become 0-9, and the letters the alphabet leaves out
/// are read as the digits they are mistaken for (O as 0, I and L as 1).
String normalizeCodeText(String input) {
  final out = StringBuffer();
  for (final rune in input.runes) {
    var c = rune;
    // Arabic-Indic and Eastern Arabic-Indic digits.
    if (c >= 0x0660 && c <= 0x0669) c = 0x30 + (c - 0x0660);
    if (c >= 0x06F0 && c <= 0x06F9) c = 0x30 + (c - 0x06F0);
    // a-z.
    if (c >= 0x61 && c <= 0x7A) c -= 0x20;
    final isDigit = c >= 0x30 && c <= 0x39;
    final isLetter = c >= 0x41 && c <= 0x5A;
    if (!isDigit && !isLetter) continue;
    if (c == 0x4F) c = 0x30; // O
    if (c == 0x49 || c == 0x4C) c = 0x31; // I, L
    out.writeCharCode(c);
  }
  return out.toString();
}

/// "K7QM29XDHF4P8WZN" as "K7QM-29XD-HF4P-8WZN".
String groupCodeText(String text, {int size = 4, String separator = '-'}) {
  final groups = <String>[];
  for (var i = 0; i < text.length; i += size) {
    groups.add(
      text.substring(i, i + size > text.length ? text.length : i + size),
    );
  }
  return groups.join(separator);
}
