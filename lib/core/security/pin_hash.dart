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
String hashPin(String pin, List<int> salt, {int iterations = pinIterations}) {
  final digest = pbkdf2Sha256(utf8.encode(normalizePin(pin)), salt, iterations);
  return 'pbkdf2-sha256\$$iterations\$${base64Encode(digest)}';
}

/// Whether [pin] is the one behind [stored]. Compares in constant time.
bool verifyPin(String pin, List<int> salt, String stored) {
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
  final actual = pbkdf2Sha256(utf8.encode(normalizePin(pin)), salt, iterations);
  if (expected.length != actual.length) return false;
  var diff = 0;
  for (var i = 0; i < actual.length; i++) {
    diff |= actual[i] ^ expected[i];
  }
  return diff == 0;
}
