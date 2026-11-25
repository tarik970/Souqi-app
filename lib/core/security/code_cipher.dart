/// Encryption at rest for prepaid card codes.
///
/// A card code is cash: whoever reads it can spend it. So the database never
/// holds one in the clear. Each code is stored as
///
///  - `code_cipher`: AES-256-GCM of the code, a fresh random nonce per code;
///  - `code_hash`: HMAC-SHA-256 of the NORMALIZED code, for the duplicate
///    guard and for "was this card sold?" — a lookup that needs no decryption.
///
/// Both keys are random, generated on first use and kept outside the
/// database, in the Android Keystore (see `secure_key_store.dart`). A copy of
/// the database file alone therefore gives away neither the codes nor a way
/// to test guesses against the hashes: a plain SHA-256 of a 14-digit PIN can
/// be brute-forced in hours, a keyed one cannot.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../utils/normalize.dart';

/// Where the key material lives. The app uses the Android Keystore; tests use
/// [InMemoryKeyStore].
abstract class SecretKeyStore {
  Future<String?> read(String name);

  Future<void> write(String name, String value);
}

class InMemoryKeyStore implements SecretKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String name) async => values[name];

  @override
  Future<void> write(String name, String value) async => values[name] = value;
}

/// A stored code could not be decrypted: the bytes were damaged, or — the
/// usual reason — the database was copied to a phone that does not hold the
/// key. Never carries the bytes or any part of the code.
class CodeUnreadableException implements Exception {
  const CodeUnreadableException();

  @override
  String toString() => 'CodeUnreadableException';
}

class _Keys {
  _Keys(Uint8List bytes)
      : aes = SecretKey(Uint8List.sublistView(bytes, 0, 32)),
        hmac = crypto.Hmac(crypto.sha256, Uint8List.sublistView(bytes, 32, 64));

  final SecretKey aes;
  final crypto.Hmac hmac;
}

class CodeCipher {
  CodeCipher(this._store, {Random? random}) : _random = random ?? Random.secure();

  /// The Keystore entry: 64 random bytes, base64 — 32 for AES, 32 for HMAC.
  ///
  /// PHASE 5 (backup / restore): a backup must carry this entry AS A WHOLE,
  /// re-encrypted with the backup password, and a restore must write it back
  /// before the database is used. With only the AES half the codes decrypt
  /// but every lookup hash stops matching; with neither, the codes of the
  /// restored database are unreadable. See PHASE 5 NOTES in the rule file.
  static const String keyName = 'souqi.voucher_keys.v1';

  /// First byte of every stored blob, so the format can change later without
  /// guessing what an old row is.
  static const int formatVersion = 1;

  static const int _nonceLength = 12;
  static const int _macLength = 16;

  final SecretKeyStore _store;
  final Random _random;
  final AesGcm _aes = AesGcm.with256bits(nonceLength: _nonceLength);

  Future<_Keys>? _loading;

  /// One load for the life of the app. Memoized as a FUTURE, so two callers
  /// arriving together cannot each generate a key and overwrite one another.
  Future<_Keys> _keys() => _loading ??= _load().onError((error, stack) {
        _loading = null; // let the next call try again
        Error.throwWithStackTrace(error!, stack);
      });

  Future<_Keys> _load() async {
    final stored = await _store.read(keyName);
    if (stored != null) {
      final bytes = base64Decode(stored);
      if (bytes.length != 64) {
        // Never "repair" this by writing a new key over it: every code
        // already stored would become unreadable for good.
        throw StateError('the stored card-code key is damaged');
      }
      return _Keys(bytes);
    }
    final bytes = Uint8List(64);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    await _store.write(keyName, base64Encode(bytes));
    return _Keys(bytes);
  }

  /// `version ‖ nonce ‖ ciphertext ‖ tag`. The code is stored as it was
  /// entered (trimmed), so it prints exactly as it is on the card.
  Future<Uint8List> encrypt(String code) async {
    final keys = await _keys();
    final box = await _aes.encrypt(
      utf8.encode(code.trim()),
      secretKey: keys.aes,
    );
    return Uint8List.fromList([formatVersion, ...box.concatenation()]);
  }

  /// Throws [CodeUnreadableException] for anything that is not a code this
  /// device encrypted.
  Future<String> decrypt(List<int> blob) async {
    final keys = await _keys();
    if (blob.length <= 1 + _nonceLength + _macLength ||
        blob.first != formatVersion) {
      throw const CodeUnreadableException();
    }
    try {
      final box = SecretBox.fromConcatenation(
        blob.sublist(1),
        nonceLength: _nonceLength,
        macLength: _macLength,
      );
      return utf8.decode(await _aes.decrypt(box, secretKey: keys.aes));
    } on SecretBoxAuthenticationError {
      throw const CodeUnreadableException();
    } on FormatException {
      throw const CodeUnreadableException();
    }
  }

  /// The lookup hash of one code. See [hasher] for many.
  Future<String> hash(String code) async => (await hasher())(code);

  /// A synchronous hash function, for hashing a whole batch without a
  /// round trip per card.
  ///
  /// The code goes through [normalizeCode] first — spaces, dashes, digit
  /// shapes and letter case do not make a different card.
  Future<String Function(String code)> hasher() async {
    final hmac = (await _keys()).hmac;
    return (code) => hmac.convert(utf8.encode(normalizeCode(code))).toString();
  }
}
