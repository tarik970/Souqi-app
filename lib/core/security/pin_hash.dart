/// The PIN as it is stored: a salted, deliberately slow hash.
///
/// A 4–6 digit PIN has at most a million values, so no hash can make it
/// strong against someone who holds the database file. What the salt and the
/// iterations do buy: the PIN is not readable from the settings table, two
/// shops with the same PIN do not share a hash, and each guess costs real
/// time. On the phone itself the lock-out in `PinRepository` is what limits
/// guessing.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../utils/normalize.dart';

const int pinMinLength = 4;
const int pinMaxLength = 6;

/// PBKDF2 rounds. About a fifth of a second on a low-end phone.
const int pinIterations = 20000;

const int pinSaltLength = 16;

/// The PIN as typed, with Arabic-Indic digits turned into 0-9 — an Arabic
/// keyboard and a Latin one must give the same PIN.
String normalizePin(String input) => normalizeDigits(input.trim());

/// 4 to 6 digits, nothing else.
bool isValidPin(String input) {
  final pin = normalizePin(input);
  if (pin.length < pinMinLength || pin.length > pinMaxLength) return false;
  return pin.codeUnits.every((c) => c >= 0x30 && c <= 0x39);
}

Uint8List newPinSalt([Random? random]) {
  final source = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(pinSaltLength, (_) => source.nextInt(256)),
  );
}

/// PBKDF2-HMAC-SHA256 (RFC 8018), one 32-byte block.
Uint8List pbkdf2Sha256(List<int> password, List<int> salt, int iterations) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be >= 1');
  }
  final hmac = Hmac(sha256, password);
  // U1 = HMAC(password, salt ‖ INT(1)); Un = HMAC(password, Un-1).
  var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes;
  final out = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < out.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

/// The stored form: `pbkdf2-sha256$<iterations>$<base64 hash>`. The
/// iteration count travels with the hash so it can be raised later without
/// locking anybody out.
String hashPin(String pin, List<int> salt, {int iterations = pinIterations}) =>
    _hashSecret(normalizePin(pin), salt, iterations);

/// Whether [pin] is the one behind [stored]. Compares in constant time.
bool verifyPin(String pin, List<int> salt, String stored) =>
    _verifySecret(normalizePin(pin), salt, stored);

// ---- The recovery code ---------------------------------------------------
//
// A shop that forgets its PIN must not be locked out of its own card stock
// for good. So every time a PIN is set, a RECOVERY CODE is made: shown once,
// to be printed or saved away from the phone, and stored here only as a
// salted hash — exactly like the PIN, and for the same reason.

/// Characters in a recovery code. 12 × 5 bits = 60 bits: far beyond guessing
/// by hand, and the lock-out stops guessing on the phone anyway.
const int recoveryCodeLength = 12;

/// Crockford's base32 alphabet: no I, L, O or U, so a code read off paper or
/// over the phone cannot be mistyped into a different valid code.
const String crockfordAlphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// A new random recovery code, without separators ("7K3M9QXA2B4D").
String generateRecoveryCode([Random? random]) {
  final source = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < recoveryCodeLength; i++)
      crockfordAlphabet.codeUnitAt(source.nextInt(crockfordAlphabet.length)),
  ]);
}

/// The code as it is shown and printed: "7K3M-9QXA-2B4D".
String formatRecoveryCode(String code) {
  final plain = normalizeRecoveryCode(code);
  return [
    for (var i = 0; i < plain.length; i += 4)
      plain.substring(i, i + 4 > plain.length ? plain.length : i + 4),
  ].join('-');
}

/// The code as typed, made comparable: no spaces or dashes, upper case,
/// Arabic-Indic digits as 0-9, and the letters Crockford's alphabet leaves
/// out read as the digits they are mistaken for (O → 0, I and L → 1).
String normalizeRecoveryCode(String input) => stripCodeSeparators(input)
    .toUpperCase()
    .replaceAll('O', '0')
    .replaceAll('I', '1')
    .replaceAll('L', '1');

/// Whether [input] can be a recovery code at all: twelve characters of the
/// alphabet once normalized. (Whether it is THE code is [verifyRecoveryCode].)
bool isRecoveryCodeShaped(String input) {
  final code = normalizeRecoveryCode(input);
  return code.length == recoveryCodeLength &&
      code.split('').every(crockfordAlphabet.contains);
}

/// The stored form of a recovery code — same construction as [hashPin].
String hashRecoveryCode(
  String code,
  List<int> salt, {
  int iterations = pinIterations,
}) =>
    _hashSecret(normalizeRecoveryCode(code), salt, iterations);

/// Whether [code] is the one behind [stored]. Compares in constant time.
bool verifyRecoveryCode(String code, List<int> salt, String stored) =>
    _verifySecret(normalizeRecoveryCode(code), salt, stored);

String _hashSecret(String secret, List<int> salt, int iterations) {
  final digest = pbkdf2Sha256(utf8.encode(secret), salt, iterations);
  return 'pbkdf2-sha256\$$iterations\$${base64Encode(digest)}';
}

bool _verifySecret(String secret, List<int> salt, String stored) {
  final parts = stored.split(r'$');
  if (parts.length != 3 || parts[0] != 'pbkdf2-sha256') return false;
  final iterations = int.tryParse(parts[1]);
  if (iterations == null || iterations < 1) return false;
  final Uint8List expected;
  try {
    expected = base64Decode(parts[2]);
  } on FormatException {
    return false;
  }
  final actual = pbkdf2Sha256(utf8.encode(secret), salt, iterations);
  if (expected.length != actual.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}
