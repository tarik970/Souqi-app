import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/licensing/license_codec.dart';
import 'package:souqi/core/licensing/license_service.dart';
import 'package:souqi/core/platform/license_platform.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:sqflite/sqflite.dart';

/// A DEVELOPER FOR ONE TEST RUN: an Ed25519 key pair made in memory when the
/// test starts and gone when it ends. It is never written anywhere — the
/// real licensing key is not in this repository, and neither is this one.
/// The service under test is simply given this key's public half.
class TestDeveloper {
  TestDeveloper._(this._pair, this.publicKeyHex);

  final SimpleKeyPair _pair;

  /// What `licensePublicKeyHex` would hold if this were the real developer.
  final String publicKeyHex;

  static final _algorithm = Ed25519();

  static Future<TestDeveloper> create() async {
    final pair = await _algorithm.newKeyPair();
    final public = await pair.extractPublicKey();
    return TestDeveloper._(
      pair,
      [for (final b in public.bytes) b.toRadixString(16).padLeft(2, '0')].join(),
    );
  }

  Future<String> _sign(Uint8List payload) async {
    final signature = await _algorithm.sign(payload, keyPair: _pair);
    return SignedCode(payload: payload, signature: signature.bytes).display;
  }

  /// An activation code, as the key generator's `issue` would print it.
  Future<String> license({
    required List<int> device,
    int id = 1,
    Iterable<Feature>? features,
    required DateTime issuedAt,
    DateTime? expiresAt,
    String shop = 'Test Shop',
  }) =>
      _sign(LicensePayload(
        deviceHash: device,
        licenseId: id,
        features: features == null
            ? allLicenseFeatures
            : featureMaskOf(features.map((f) => f.wire)),
        issuedAt: issuedAt,
        expiresAt: expiresAt,
        shopName: shop,
      ).encode());

  /// A PIN reset code, as the key generator's `pin-reset` would print it.
  Future<String> pinReset({
    required List<int> device,
    int id = 7,
    required DateTime issuedAt,
    DateTime? expiresAt,
  }) =>
      _sign(PinResetPayload(
        deviceHash: device,
        resetId: id,
        issuedAt: issuedAt,
        expiresAt: expiresAt ?? issuedAt.add(pinResetLifetime),
      ).encode());
}

/// A phone, as licensing sees one.
class FakeLicensePlatform implements LicensePlatform {
  FakeLicensePlatform({
    this.androidId = 'a1b2c3d4e5f60718',
    this.packageName = 'com.souqi.souqi',
    this.signers = const [],
  });

  String androidId;
  String packageName;

  /// SHA-256 of the APK's signing certificates, hex.
  List<String> signers;

  /// The channel does not answer.
  bool broken = false;

  /// The 80 device bits a license for this phone must carry.
  Uint8List get device =>
      deviceHashOf(androidId: androidId, packageName: packageName);

  String get requestCode => formatRequestCode(device);

  @override
  Future<DeviceIdentity> deviceIdentity() async {
    if (broken) throw StateError('no platform');
    return DeviceIdentity(androidId: androidId, packageName: packageName);
  }

  @override
  Future<List<String>> signingCertificates() async {
    if (broken) throw StateError('no platform');
    return signers;
  }
}

/// A clock the test moves by hand.
class TestClock {
  TestClock(this.now);

  DateTime now;

  DateTime call() => now;

  void advance(Duration by) => now = now.add(by);
}

/// The licensing service of [db] on a fake phone, trusting [developer].
LicenseService testLicenseService({
  required Database db,
  required SecretKeyStore keys,
  required FakeLicensePlatform platform,
  required TestClock clock,
  required TestDeveloper developer,
  bool checkSigner = false,
  String expectedSigner = '',
}) =>
    LicenseService(
      db: db,
      keys: keys,
      platform: platform,
      clock: clock.call,
      publicKeyHex: developer.publicKeyHex,
      checkSigner: checkSigner,
      expectedSigner: expectedSigner,
    );

/// Makes the invoice counter say [count] invoices were ever saved.
Future<void> setInvoiceCounter(DatabaseExecutor db, int count) => db.insert(
      'counters',
      {'name': 'invoice_no', 'value': count},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
