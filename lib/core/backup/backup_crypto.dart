/// The backup password and what it protects.
///
/// A backup carries the two card-code keys (AES ‖ HMAC, see `CodeCipher`) —
/// whoever has them and the database can read every card in stock. So they
/// are never written in the clear: they travel sealed with AES-256-GCM under
/// a key DERIVED from the backup password,
///
///     master = PBKDF2-HMAC-SHA256(password, salt, iterations)   (32 bytes)
///     enc    = HMAC-SHA256(master, "souqi-backup-enc-v1")
///     mac    = HMAC-SHA256(master, "souqi-backup-mac-v1")
///
/// with a random 16-byte salt per password and [backupKdfIterations] rounds
/// (both recorded in the manifest, so they can change later). `enc` seals the
/// secrets; `mac` signs the manifest, whose checksums cover every file — a
/// file altered after the fact fails once the password is entered.
///
/// GCM's tag is what tells a wrong password: it fails safely, before anything
/// is written.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../security/pin_hash.dart';
import '../utils/normalize.dart';

/// PBKDF2 rounds for a NEW password: about three seconds on a low-end phone
/// (a PIN's 20,000 take a fifth of one), run off the UI thread. Each guess
/// at a stolen backup file costs the same.
const int backupKdfIterations = 310000;

/// The fewest rounds a backup file may declare: a file that asks for fewer
/// was not made by this app.
const int backupKdfMinIterations = 1000;

const int backupSaltLength = 16;

/// The shortest password accepted.
const int backupPasswordMinLength = 6;

/// The password as typed, made comparable across keyboards: Arabic-Indic
/// and Persian digits become 0-9 (a backup made on a Latin keyboard must open
/// on a phone with an Arabic one). Nothing else is changed — spaces and
/// letter case are part of the password.
String normalizeBackupPassword(String input) => normalizeDigits(input);

bool isValidBackupPassword(String input) =>
    normalizeBackupPassword(input).runes.length >= backupPasswordMinLength;

Uint8List newBackupSalt([Random? random]) {
  final source = random ?? Random.secure();
  return Uint8List.fromList(
    List<int>.generate(backupSaltLength, (_) => source.nextInt(256)),
  );
}

/// The password did not open the backup.
class WrongBackupPasswordException implements Exception {
  const WrongBackupPasswordException();

  @override
  String toString() => 'WrongBackupPasswordException';
}

/// The key a password gives, with what made it. [master] never leaves the
/// phone except sealed inside the Keystore (the automatic backup's entry).
class BackupKey {
  BackupKey({
    required this.salt,
    required this.iterations,
    required Uint8List master,
  })  : assert(master.length == 32),
        _master = master;

  final Uint8List salt;
  final int iterations;
  final Uint8List _master;

  Uint8List _sub(String label) => Uint8List.fromList(
        crypto.Hmac(crypto.sha256, _master).convert(utf8.encode(label)).bytes,
      );

  late final Uint8List _enc = _sub('souqi-backup-enc-v1');
  late final Uint8List _mac = _sub('souqi-backup-mac-v1');

  static final _aes = AesGcm.with256bits();

  /// `nonce (12) ‖ ciphertext ‖ tag (16)`.
  Future<Uint8List> seal(List<int> plaintext) async {
    final box = await _aes.encrypt(plaintext, secretKey: SecretKey(_enc));
    return Uint8List.fromList(box.concatenation());
  }

  /// Throws [WrongBackupPasswordException] when the tag does not match —
  /// the password is wrong (or the bytes were damaged, which looks the same).
  Future<Uint8List> open(List<int> sealed) async {
    if (sealed.length < 12 + 16) throw const WrongBackupPasswordException();
    try {
      final box = SecretBox.fromConcatenation(
        sealed,
        nonceLength: 12,
        macLength: 16,
      );
      return Uint8List.fromList(
        await _aes.decrypt(box, secretKey: SecretKey(_enc)),
      );
    } on SecretBoxAuthenticationError {
      throw const WrongBackupPasswordException();
    }
  }

  /// HMAC-SHA256 of [bytes] with the signing key, hex.
  String sign(List<int> bytes) =>
      crypto.Hmac(crypto.sha256, _mac).convert(bytes).toString();

  /// Constant time.
  bool verify(List<int> bytes, String signature) {
    final expected = sign(bytes);
    if (expected.length != signature.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ signature.codeUnitAt(i);
    }
    return diff == 0;
  }

  /// The form kept in the Keystore for the automatic backup: the derived
  /// key, never the password.
  String toStored() => jsonEncode({
        'v': 1,
        'salt': base64Encode(salt),
        'iterations': iterations,
        'key': base64Encode(_master),
      });

  /// Null for anything that is not such an entry.
  static BackupKey? fromStored(String? stored) {
    if (stored == null || stored.isEmpty) return null;
    try {
      final map = jsonDecode(stored);
      if (map is! Map || map['v'] != 1) return null;
      final master = base64Decode(map['key'] as String);
      final salt = base64Decode(map['salt'] as String);
      final iterations = map['iterations'] as int;
      if (master.length != 32 || salt.isEmpty || iterations < 1) return null;
      return BackupKey(salt: salt, iterations: iterations, master: master);
    } on Object {
      return null;
    }
  }
}

/// Derives the key of [password] — slow on purpose, so it runs in an
/// isolate and the screen keeps moving.
Future<BackupKey> deriveBackupKey(
  String password, {
  required List<int> salt,
  int iterations = backupKdfIterations,
}) async {
  final secret = utf8.encode(normalizeBackupPassword(password));
  final saltCopy = Uint8List.fromList(salt);
  final master = await Isolate.run(
    () => pbkdf2Sha256(secret, saltCopy, iterations),
  );
  return BackupKey(salt: saltCopy, iterations: iterations, master: master);
}

/// A new password: a fresh salt, today's iteration count.
Future<BackupKey> newBackupKey(
  String password, {
  int iterations = backupKdfIterations,
  Random? random,
}) =>
    deriveBackupKey(
      password,
      salt: newBackupSalt(random),
      iterations: iterations,
    );
