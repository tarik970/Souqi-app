/// The bytes of a Souqi license — what the developer's key generator signs
/// and what the app checks.
///
/// SHARED FILE: an identical copy lives in the developer's key generator
/// (../souqi_keygen/lib/src/license_codec.dart). Change both or neither; the
/// test vectors (license_vectors.json, also in both projects) catch a drift.
///
/// Pure Dart on purpose: no Flutter, no package of the app. Nothing here is
/// secret — a code is only worth something with the developer's signature,
/// and the key that signs is not in the app.
///
/// THE FORMAT (version 1). Every code is
///
///     base32( payload ‖ signature )
///
/// where the signature is Ed25519 (64 bytes) over the payload bytes exactly,
/// and base32 is Crockford's alphabet (base32.dart). Numbers are big-endian.
///
/// ACTIVATION payload — the license of one device:
///
///     offset  bytes  field
///     0       1      kind      0x50 (the code then starts with "A")
///     1       1      version   1
///     2       10     device    the first 80 bits of the device hash
///     12      4      license id
///     16      4      features  bit mask, see [licenseFeatureBits]
///     20      4      issued at   seconds since 1970, UTC
///     24      4      expires at  seconds since 1970, UTC; 0 = never
///     28      1      n = length of the shop name in bytes (1…120)
///     29      n      shop name, UTF-8
///
/// PIN RESET payload — a single-use, short-lived permission to choose a new
/// PIN on one device:
///
///     0       1      kind      0xB0 (the code then starts with "P")
///     1       1      version   1
///     2       10     device
///     12      4      reset id
///     16      4      issued at
///     20      4      expires at  (at most 48 hours after "issued at")
///
/// The REQUEST CODE a device shows is those same 80 device bits in base32,
/// in fours: K7QM-29XD-HF4P-8WZN.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'base32.dart';

const int licenseKindActivation = 0x50;
const int licenseKindPinReset = 0xB0;
const int licenseFormatVersion = 1;

/// Bytes of the device hash a code carries (80 bits).
const int deviceHashLength = 10;

/// An Ed25519 signature.
const int signatureLength = 64;

const int maxShopNameBytes = 120;

/// How long a PIN reset code may live.
const Duration pinResetLifetime = Duration(hours: 48);

/// The licensable features and their bits. The NAMES are what the key
/// generator's `--features` takes; a bit is never reused for something else.
const Map<String, int> licenseFeatureBits = {
  'debt': 1 << 0,
  'customers': 1 << 1,
  'accounts': 1 << 2,
  'vouchers': 1 << 3,
  'barcode': 1 << 4,
  'discount': 1 << 5,
  'multiCurrency': 1 << 6,
  'dailyReport': 1 << 7,
  'backup': 1 << 8,
};

/// Every feature this version knows.
const int allLicenseFeatures = (1 << 9) - 1;

/// A feature that only works with another one: the generator adds what is
/// required, the app refuses to run one without the other.
const Map<String, List<String>> licenseFeatureRequires = {
  'accounts': ['customers'],
  'debt': ['customers'],
  'dailyReport': ['debt', 'customers'],
};

/// The names in [mask], in the order of their bits.
List<String> featureNamesOf(int mask) => [
      for (final entry in licenseFeatureBits.entries)
        if (mask & entry.value != 0) entry.key,
    ];

/// The mask of [names], with everything they require added. Throws
/// [FormatException] for a name that is not a feature. Names are matched
/// without regard to case, dashes or underscores ("multi-currency").
int featureMaskOf(Iterable<String> names) {
  String key(String name) =>
      name.toLowerCase().replaceAll('-', '').replaceAll('_', '').trim();
  final byKey = {
    for (final name in licenseFeatureBits.keys) key(name): name,
  };
  var mask = 0;
  void add(String name) {
    final bit = licenseFeatureBits[name]!;
    if (mask & bit != 0) return;
    mask |= bit;
    for (final needed in licenseFeatureRequires[name] ?? const <String>[]) {
      add(needed);
    }
  }

  for (final raw in names) {
    if (key(raw).isEmpty) continue;
    if (key(raw) == 'all') return allLicenseFeatures;
    final name = byKey[key(raw)];
    if (name == null) throw FormatException('unknown feature "$raw"');
    add(name);
  }
  return mask;
}

int _seconds(DateTime moment) =>
    moment.toUtc().millisecondsSinceEpoch ~/ 1000;

DateTime _moment(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void _putUint32(Uint8List out, int offset, int value) {
  if (value < 0 || value > 0xFFFFFFFF) {
    throw FormatException('$value does not fit in 32 bits');
  }
  out[offset] = (value >> 24) & 0xFF;
  out[offset + 1] = (value >> 16) & 0xFF;
  out[offset + 2] = (value >> 8) & 0xFF;
  out[offset + 3] = value & 0xFF;
}

int _uint32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// The license of one device.
class LicensePayload {
  LicensePayload({
    required List<int> deviceHash,
    required this.licenseId,
    required this.features,
    required DateTime issuedAt,
    DateTime? expiresAt,
    required String shopName,
  })  : deviceHash = Uint8List.fromList(deviceHash),
        issuedAt = _moment(_seconds(issuedAt)),
        expiresAt = expiresAt == null ? null : _moment(_seconds(expiresAt)),
        shopName = shopName.trim();

  /// The first 80 bits of the hash of the device it was issued for.
  final Uint8List deviceHash;
  final int licenseId;

  /// A mask of [licenseFeatureBits].
  final int features;
  final DateTime issuedAt;

  /// Null = a lifetime license.
  final DateTime? expiresAt;
  final String shopName;

  bool isFor(List<int> device) => _sameBytes(deviceHash, device);

  bool hasFeature(String name) =>
      features & (licenseFeatureBits[name] ?? 0) != 0;

  /// Valid at [now]: issued without an end, or not yet past it.
  bool isLiveAt(DateTime now) =>
      expiresAt == null || now.toUtc().isBefore(expiresAt!);

  Uint8List encode() {
    final name = utf8.encode(shopName);
    if (deviceHash.length != deviceHashLength) {
      throw const FormatException('the device hash must be 10 bytes');
    }
    if (name.isEmpty || name.length > maxShopNameBytes) {
      throw const FormatException('the shop name must be 1 to 120 bytes');
    }
    if (features & ~0xFFFFFFFF != 0) {
      throw const FormatException('the feature mask must fit in 32 bits');
    }
    final expires = expiresAt;
    if (expires != null && !expires.isAfter(issuedAt)) {
      throw const FormatException('a license must expire after it is issued');
    }
    final out = Uint8List(29 + name.length);
    out[0] = licenseKindActivation;
    out[1] = licenseFormatVersion;
    out.setRange(2, 12, deviceHash);
    _putUint32(out, 12, licenseId);
    _putUint32(out, 16, features);
    _putUint32(out, 20, _seconds(issuedAt));
    _putUint32(out, 24, expires == null ? 0 : _seconds(expires));
    out[28] = name.length;
    out.setRange(29, 29 + name.length, name);
    return out;
  }

  /// Throws [FormatException] for bytes that are not an activation payload
  /// of this version.
  static LicensePayload decode(List<int> bytes) {
    final b = Uint8List.fromList(bytes);
    if (b.length < 30 || b[0] != licenseKindActivation) {
      throw const FormatException('not an activation code');
    }
    if (b[1] != licenseFormatVersion) {
      throw UnsupportedLicenseVersion(b[1]);
    }
    final n = b[28];
    if (n == 0 || n > maxShopNameBytes || b.length != 29 + n) {
      throw const FormatException('activation code of the wrong length');
    }
    final String name;
    try {
      name = utf8.decode(b.sublist(29));
    } on FormatException {
      throw const FormatException('the shop name is not text');
    }
    final expires = _uint32(b, 24);
    return LicensePayload(
      deviceHash: b.sublist(2, 12),
      licenseId: _uint32(b, 12),
      features: _uint32(b, 16),
      issuedAt: _moment(_uint32(b, 20)),
      expiresAt: expires == 0 ? null : _moment(expires),
      shopName: name,
    );
  }
}

/// A single-use permission to choose a new PIN on one device.
class PinResetPayload {
  PinResetPayload({
    required List<int> deviceHash,
    required this.resetId,
    required DateTime issuedAt,
    required DateTime expiresAt,
  })  : deviceHash = Uint8List.fromList(deviceHash),
        issuedAt = _moment(_seconds(issuedAt)),
        expiresAt = _moment(_seconds(expiresAt));

  final Uint8List deviceHash;
  final int resetId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isFor(List<int> device) => _sameBytes(deviceHash, device);

  /// Not past its end at [now] — and never issued for longer than
  /// [pinResetLifetime], whatever its bytes claim.
  bool isLiveAt(DateTime now) =>
      !expiresAt.isAfter(issuedAt.add(pinResetLifetime)) &&
      now.toUtc().isBefore(expiresAt);

  Uint8List encode() {
    if (deviceHash.length != deviceHashLength) {
      throw const FormatException('the device hash must be 10 bytes');
    }
    if (!expiresAt.isAfter(issuedAt) ||
        expiresAt.isAfter(issuedAt.add(pinResetLifetime))) {
      throw const FormatException('a PIN reset lives at most 48 hours');
    }
    final out = Uint8List(24);
    out[0] = licenseKindPinReset;
    out[1] = licenseFormatVersion;
    out.setRange(2, 12, deviceHash);
    _putUint32(out, 12, resetId);
    _putUint32(out, 16, _seconds(issuedAt));
    _putUint32(out, 20, _seconds(expiresAt));
    return out;
  }

  static PinResetPayload decode(List<int> bytes) {
    final b = Uint8List.fromList(bytes);
    if (b.length < 2 || b[0] != licenseKindPinReset) {
      throw const FormatException('not a PIN reset code');
    }
    if (b[1] != licenseFormatVersion) {
      throw UnsupportedLicenseVersion(b[1]);
    }
    if (b.length != 24) {
      throw const FormatException('PIN reset code of the wrong length');
    }
    return PinResetPayload(
      deviceHash: b.sublist(2, 12),
      resetId: _uint32(b, 12),
      issuedAt: _moment(_uint32(b, 16)),
      expiresAt: _moment(_uint32(b, 20)),
    );
  }
}

/// A code written by a newer key generator than this app understands.
class UnsupportedLicenseVersion extends FormatException {
  const UnsupportedLicenseVersion(this.version)
      : super('license format version not supported');

  final int version;
}

/// A code taken apart: the payload and the signature that covers it. Whether
/// the signature is the developer's is not decided here.
class SignedCode {
  SignedCode({required List<int> payload, required List<int> signature})
      : payload = Uint8List.fromList(payload),
        signature = Uint8List.fromList(signature);

  final Uint8List payload;
  final Uint8List signature;

  /// [licenseKindActivation] or [licenseKindPinReset] (or something this
  /// version does not know).
  int get kind => payload[0];

  bool get isActivation => kind == licenseKindActivation;

  bool get isPinReset => kind == licenseKindPinReset;

  /// The code as one unbroken run of characters.
  String get text => base32Encode([...payload, ...signature]);

  /// [text] in fives, for a message: "A0J3K-9QXA2-…".
  String get display => groupCodeText(text, size: 5);

  /// Null when [input] cannot be a code at all: not base32, or too short to
  /// hold a signature and something to sign. Spaces, dashes and line breaks
  /// in [input] do not matter.
  static SignedCode? parse(String input) {
    final bytes = base32Decode(normalizeCodeText(input));
    if (bytes == null || bytes.length < signatureLength + 2) return null;
    final split = bytes.length - signatureLength;
    return SignedCode(
      payload: bytes.sublist(0, split),
      signature: bytes.sublist(split),
    );
  }
}

/// The request code of a device: its 80 hash bits as "K7QM-29XD-HF4P-8WZN".
String formatRequestCode(List<int> deviceHash) {
  if (deviceHash.length != deviceHashLength) {
    throw const FormatException('the device hash must be 10 bytes');
  }
  return groupCodeText(base32Encode(deviceHash));
}

/// The 80 device bits behind a request code, or null when it is not one.
Uint8List? parseRequestCode(String input) {
  final text = normalizeCodeText(input);
  if (text.length != 16) return null;
  final bytes = base32Decode(text);
  return bytes == null || bytes.length != deviceHashLength ? null : bytes;
}
