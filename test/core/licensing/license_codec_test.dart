import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/licensing/base32.dart';
import 'package:souqi/core/licensing/license_codec.dart';
import 'package:souqi/core/licensing/license_keys.dart';
import 'package:souqi/core/licensing/license_service.dart';

/// THE FORMAT, PINNED. `license_vectors.json` holds known codes with known
/// contents, signed with a TEST key; the very same file is in the key
/// generator (../souqi_keygen/test/vectors/) with its own test against it.
/// A change to the format in one project and not the other fails here or
/// there.
///
/// This repository holds the test PUBLIC key and the signed codes only — no
/// private key, test or real.
void main() {
  const vectorsPath = 'test/core/licensing/license_vectors.json';
  late Map<String, Object?> vectors;
  late Uint8List publicKey;

  Uint8List hex(String text) => Uint8List.fromList([
        for (var i = 0; i < text.length; i += 2)
          int.parse(text.substring(i, i + 2), radix: 16),
      ]);

  String toHex(List<int> bytes) =>
      [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

  Future<bool> signedBy(SignedCode code, List<int> key) => Ed25519().verify(
        code.payload,
        signature: Signature(
          code.signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      );

  setUpAll(() {
    vectors = (jsonDecode(File(vectorsPath).readAsStringSync()) as Map)
        .cast<String, Object?>();
    publicKey = hex(vectors['testPublicKeyHex']! as String);
  });

  List<Map<String, Object?>> list(String name) => [
        for (final entry in vectors[name]! as List)
          (entry as Map).cast<String, Object?>(),
      ];

  test('base32, both ways', () {
    for (final v in list('base32')) {
      final bytes = hex(v['hex']! as String);
      expect(base32Encode(bytes), v['text'], reason: '${v['hex']}');
      expect(base32Decode(v['text']! as String), bytes, reason: '${v['hex']}');
    }
    expect(base32Decode('U'), isNull, reason: 'not in the alphabet');
    expect(base32Decode('0'), isNull, reason: 'five bits are not a byte');
    expect(base32Decode('01'), isNull, reason: 'padding bits must be zero');
  });

  test('a code as typed is read the same: spaces, dashes, line breaks, '
      'lower case, Arabic digits, O / I / L', () {
    for (final v in list('normalize')) {
      expect(normalizeCodeText(v['input']! as String), v['output']);
    }
  });

  test('the feature bits are the ones the key generator writes', () {
    expect(vectors['featureBits'], licenseFeatureBits);
    // Every feature of the app has a bit, and every bit a feature.
    expect(
      {for (final f in Feature.values) f.wire: f.bit},
      licenseFeatureBits,
    );
    expect(FeatureGate.maskOf(Feature.values), allLicenseFeatures);
    for (final entry in licenseFeatureRequires.entries) {
      final feature = Feature.values.firstWhere((f) => f.wire == entry.key);
      expect(feature.requires.map((f) => f.wire), entry.value);
    }
  });

  test('the device hash and the request code', () {
    for (final v in list('devices')) {
      final device = deviceHashOf(
        androidId: v['androidId']! as String,
        packageName: v['packageName']! as String,
        salt: v['salt']! as String,
      );
      expect(toHex(device), v['hashHex']);
      expect(device, hasLength(deviceHashLength));
      final requestCode = formatRequestCode(device);
      expect(requestCode, v['requestCode']);
      // 80 bits, in fours: K7QM-29XD-HF4P-8WZN.
      expect(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){3}$')
          .hasMatch(requestCode), isTrue);
      expect(parseRequestCode(requestCode.toLowerCase()), device);
    }
    // The app's own salt is the one the vectors were made with.
    expect(list('devices').first['salt'], licenseDeviceSalt);
    expect(parseRequestCode('K7QM-29XD'), isNull);
  });

  test('every license decodes to its fields and carries a valid signature',
      () async {
    for (final v in list('licenses')) {
      final name = '${v['name']}';
      final code = SignedCode.parse(v['code']! as String)!;
      expect(code.isActivation, isTrue, reason: name);
      expect(toHex(code.payload), v['payloadHex'], reason: name);
      // In fives with dashes, as it is sent: the same code.
      expect(SignedCode.parse(v['display']! as String)!.text, v['code']);
      expect(code.text.startsWith('A'), isTrue, reason: name);

      final license = LicensePayload.decode(code.payload);
      expect(formatRequestCode(license.deviceHash), v['requestCode']);
      expect(license.licenseId, v['licenseId'], reason: name);
      expect(license.features, v['featureMask'], reason: name);
      expect(featureNamesOf(license.features), v['features'], reason: name);
      expect(license.shopName, v['shopName'], reason: name);
      expect(
        license.issuedAt.millisecondsSinceEpoch ~/ 1000,
        v['issuedAt'],
        reason: name,
      );
      expect(
        license.expiresAt == null
            ? null
            : license.expiresAt!.millisecondsSinceEpoch ~/ 1000,
        v['expiresAt'],
        reason: name,
      );
      expect(toHex(license.encode()), v['payloadHex'], reason: name);
      expect(await signedBy(code, publicKey), isTrue, reason: name);
    }
  });

  test('every PIN reset decodes to its fields and carries a valid signature',
      () async {
    for (final v in list('pinResets')) {
      final code = SignedCode.parse(v['code']! as String)!;
      expect(code.isPinReset, isTrue);
      expect(code.text.startsWith('P'), isTrue);
      final reset = PinResetPayload.decode(code.payload);
      expect(formatRequestCode(reset.deviceHash), v['requestCode']);
      expect(reset.resetId, v['resetId']);
      expect(reset.issuedAt.millisecondsSinceEpoch ~/ 1000, v['issuedAt']);
      expect(reset.expiresAt.millisecondsSinceEpoch ~/ 1000, v['expiresAt']);
      expect(toHex(reset.encode()), v['payloadHex']);
      expect(await signedBy(code, publicKey), isTrue);
    }
  });

  test('a code changed after signing, and one signed by a stranger, do not '
      'verify', () async {
    for (final v in list('rejected')) {
      final code = SignedCode.parse(v['code']! as String)!;
      expect(await signedBy(code, publicKey), isFalse, reason: '${v['name']}');
    }
  });

  test('what is not a code at all is not parsed', () {
    expect(SignedCode.parse(''), isNull);
    expect(SignedCode.parse('K7QM-29XD-HF4P-8WZN'), isNull, reason: 'too short');
    expect(SignedCode.parse('not a code !!'), isNull);
    final whole = list('licenses').first['code']! as String;
    expect(SignedCode.parse(whole.substring(0, whole.length - 1)), isNull);
    expect(
      () => LicensePayload.decode(
        SignedCode.parse(list('pinResets').first['code']! as String)!.payload,
      ),
      throwsFormatException,
    );
  });

  test('a code of a NEWER format says so instead of being misread', () {
    final code =
        SignedCode.parse(list('licenses').first['code']! as String)!;
    final newer = Uint8List.fromList(code.payload)..[1] = 2;
    expect(
      () => LicensePayload.decode(newer),
      throwsA(isA<UnsupportedLicenseVersion>()),
    );
  });

  test('a PIN reset never lives longer than 48 hours, whatever it claims',
      () {
    final issued = DateTime.utc(2026, 11, 26, 10);
    final device = List<int>.filled(deviceHashLength, 7);
    expect(
      () => PinResetPayload(
        deviceHash: device,
        resetId: 1,
        issuedAt: issued,
        expiresAt: issued.add(const Duration(hours: 49)),
      ).encode(),
      throwsFormatException,
    );
    // Bytes that claim a year: decoded, and never "live".
    final honest = PinResetPayload(
      deviceHash: device,
      resetId: 1,
      issuedAt: issued,
      expiresAt: issued.add(pinResetLifetime),
    ).encode();
    final year = issued.add(const Duration(days: 365));
    final seconds = year.millisecondsSinceEpoch ~/ 1000;
    final greedy = Uint8List.fromList(honest)
      ..[20] = (seconds >> 24) & 0xFF
      ..[21] = (seconds >> 16) & 0xFF
      ..[22] = (seconds >> 8) & 0xFF
      ..[23] = seconds & 0xFF;
    final decoded = PinResetPayload.decode(greedy);
    expect(decoded.isLiveAt(issued.add(const Duration(hours: 1))), isFalse);
    expect(
      PinResetPayload.decode(honest)
          .isLiveAt(issued.add(const Duration(hours: 47))),
      isTrue,
    );
    expect(
      PinResetPayload.decode(honest)
          .isLiveAt(issued.add(const Duration(hours: 48))),
      isFalse,
    );
  });

  test('the two shared source files are the same in the key generator',
      () {
    const shared = {
      'lib/core/licensing/base32.dart': '../souqi_keygen/lib/src/base32.dart',
      'lib/core/licensing/license_codec.dart':
          '../souqi_keygen/lib/src/license_codec.dart',
      vectorsPath: '../souqi_keygen/test/vectors/license_vectors.json',
    };
    String text(String path) =>
        File(path).readAsStringSync().replaceAll('\r\n', '\n');
    for (final entry in shared.entries) {
      if (!File(entry.value).existsSync()) {
        markTestSkipped('the key generator is not at ../souqi_keygen');
        return;
      }
      expect(text(entry.key), text(entry.value), reason: entry.key);
    }
  });

  group('the public key built into the app', () {
    test('is either not set yet or a real 32-byte key', () {
      if (licensePublicKeyHex.isEmpty) return;
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(licensePublicKeyHex), isTrue);
      // The test key is public: an app built with it would accept codes
      // anybody can sign.
      expect(licensePublicKeyHex, isNot(vectors['testPublicKeyHex']));
    });

    test('does not accept signatures that need no private key', () async {
      if (licensePublicKeyHex.isEmpty) {
        markTestSkipped('licensePublicKeyHex is not set yet');
        return;
      }
      // A degenerate key (all zeros, a low-order point) verifies forged
      // signatures such as these for some messages; a real key for none.
      final key = hex(licensePublicKeyHex);
      final forgeries = [
        Uint8List(64),
        Uint8List(64)..[0] = 1,
      ];
      for (var i = 0; i < 64; i++) {
        final message = Uint8List.fromList(List.filled(30, i));
        for (final forged in forgeries) {
          expect(
            await signedBy(
              SignedCode(payload: message, signature: forged),
              key,
            ),
            isFalse,
          );
        }
      }
    });
  });
}
