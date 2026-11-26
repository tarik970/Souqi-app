/// OFFLINE LICENSING, in one place: who this device is, whether the code it
/// holds is the developer's and its own, what the trial has left, what time
/// it really is — and the checks the app makes before it sells, prints or
/// writes to the ledger.
///
/// No server and no network. A license is a short text signed with the
/// developer's Ed25519 PRIVATE key, which exists only on the developer's
/// laptop; the app holds the PUBLIC key (license_keys.dart) and can check a
/// code but never make one.
///
/// CHECKED IN SEVERAL PLACES, NOT ONCE: [start] on every app start,
/// [ensureCanSell] before an invoice is saved, [ensureCanPrint] before
/// anything is printed or shared, [ensureCanRecordDebt] before a ledger
/// entry, and [start] again (read-only) in the background engine of the
/// daily job. Each of them verifies the SIGNATURE of the stored code again —
/// none trusts a flag an earlier check left behind.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:sqflite/sqflite.dart';

import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/counter_repository.dart';
import '../../data/repositories/pin_repository.dart';
import '../../domain/models/voucher.dart';
import '../constants/settings_keys.dart';
import '../platform/license_platform.dart';
import '../security/code_cipher.dart';
import 'clock_guard.dart';
import 'license_codec.dart';
import 'license_keys.dart';
import 'license_status.dart';
import 'license_store.dart';

/// The first 80 bits of SHA-256 over `ANDROID_ID|package name|salt` — what a
/// license is bound to, and (in base32) the request code a phone shows.
Uint8List deviceHashOf({
  required String androidId,
  required String packageName,
  String salt = licenseDeviceSalt,
}) {
  final digest =
      crypto.sha256.convert(utf8.encode('$androidId|$packageName|$salt'));
  return Uint8List.fromList(digest.bytes.sublist(0, deviceHashLength));
}

/// Why an activation code was not accepted.
enum ActivationError {
  /// The app has no public key yet (`licensePublicKeyHex` is empty).
  notConfigured,

  /// Not a code at all: a typing mistake, a part missing.
  malformed,

  /// It is a PIN reset code — it goes into "Forgot PIN?", not here.
  pinResetCode,

  /// Made by a newer key generator than this app understands.
  newerFormat,

  /// Not signed by the developer (or changed after it was signed).
  badSignature,

  /// Signed by the developer, for another device.
  wrongDevice,

  /// Already past its end.
  expired,

  /// A newer license is already active on this phone.
  olderThanCurrent,

  /// This copy of the app is not the developer's build.
  modifiedApp,

  /// A release build made before its signing fingerprint was filled in.
  unsealedBuild,

  /// The phone did not say who it is.
  deviceUnknown,
}

class ActivationResult {
  const ActivationResult.ok(LicensePayload this.license) : error = null;

  const ActivationResult.failed(ActivationError this.error) : license = null;

  final LicensePayload? license;
  final ActivationError? error;

  bool get ok => license != null;
}

/// What became of a PIN reset code.
enum PinResetCheck {
  ok,
  malformed,
  badSignature,
  wrongDevice,
  expired,
  alreadyUsed,
}

class LicenseService implements LicenseGuard {
  LicenseService({
    required Database db,
    required SecretKeyStore keys,
    required this.platform,
    this.clock = DateTime.now,
    String publicKeyHex = licensePublicKeyHex,
    String expectedSigner = expectedSigningCertSha256,
    bool? checkSigner,
    this.deviceSalt = licenseDeviceSalt,
  })  : _db = db,
        _store = LicenseStore(db, keys),
        _publicKey = _hexBytes(publicKeyHex),
        _expectedSigner = _hexOnly(expectedSigner),
        // The ONLY builds that skip the signing check are debug builds.
        _checkSigner = checkSigner ?? !kDebugMode;

  final Database _db;
  final LicenseStore _store;
  final LicensePlatform platform;

  /// The phone's clock (tests set it).
  final DateTime Function() clock;
  final String deviceSalt;
  final Uint8List? _publicKey;
  final String _expectedSigner;
  final bool _checkSigner;

  static final _ed25519 = Ed25519();

  /// How far the mark may move before it is written again: the database
  /// first (cheap), the Keystore less often. What a crash loses is made up
  /// by the next look at the clock.
  static const Duration _databaseClockStep = Duration(minutes: 10);
  static const Duration _secureClockStep = Duration(hours: 1);

  bool _readOnly = false;
  bool _started = false;
  bool _secureWritable = true;

  Uint8List? _device;
  BuildIntegrity _integrity = BuildIntegrity.ok;
  LicenseMemory _memory = const LicenseMemory();

  /// The activation code in force: the text of the license of this device.
  String? _code;
  bool _foreignCode = false;

  int _databaseClockSaved = 0;
  int _secureClockSaved = 0;
  bool _lastWentBack = false;

  LicenseStatus _status = const LicenseStatus(
    mode: LicenseMode.unlicensed,
    reason: UnlicensedReason.trialDaysOver,
    featureMask: allLicenseFeatures,
    canSell: false,
    canPrint: false,
  );

  /// Told of every change of [status] (the app's `LicenseController`).
  void Function(LicenseStatus status)? onChanged;

  /// The last check's result. Closed ([LicenseMode.unlicensed]) until
  /// [start] has run.
  LicenseStatus get status => _status;

  /// Whether the app holds a public key at all.
  bool get configured => _publicKey != null;

  /// The 80 device bits, or null when the phone did not say who it is.
  Uint8List? get deviceHash => _device;

  /// "K7QM-29XD-HF4P-8WZN" — what the shop sends the developer. Null when
  /// the phone did not say who it is.
  String? get requestCode {
    final device = _device;
    return device == null ? null : formatRequestCode(device);
  }

  /// The licensing time of the last check.
  DateTime get now => observeClock(_memory.clock, clock()).now;

  // ---- Start -----------------------------------------------------------

  /// The check of an app start: reads both stores, puts them in step, finds
  /// the license of this device, looks at the clock, and decides.
  ///
  /// [readOnly] is the background engine's: it decides the same way and
  /// writes NOTHING — neither store, nor the trial's start, nor the clock
  /// (the app's own engine may be writing at the same moment).
  Future<LicenseStatus> start({bool readOnly = false}) async {
    _readOnly = readOnly;
    _device = await _identify();
    _integrity = await _checkIntegrity();

    final loaded = await _store.load();
    _secureWritable = loaded.secureReadable;
    _memory = loaded.memory;
    final picked =
        await _pickLicense([loaded.secureCode, loaded.databaseCode]);

    final reading = observeClock(_memory.clock, clock());
    _memory = _memory.copyWith(clock: reading.state);
    if (_memory.trialStartMs == 0) {
      // The first start with licensing: the trial begins now, and counts
      // invoices from here.
      _memory = _memory.copyWith(
        trialStartMs: reading.now.millisecondsSinceEpoch,
        trialInvoiceBase: await _invoiceCounter(),
      );
    }
    _lastWentBack = reading.wentBack;
    _started = true;

    if (!readOnly) {
      final code = _code;
      if (loaded.databaseMemory != _memory ||
          (code != null && loaded.databaseCode != code)) {
        await LicenseStore.saveDatabase(_db, _memory, code: code);
      }
      if (_secureWritable &&
          (loaded.secureMemory != _memory ||
              (code != null && loaded.secureCode != code))) {
        await _store.saveSecure(_memory, code: code ?? loaded.secureCode);
      }
      _databaseClockSaved = _secureClockSaved = _memory.clock.latestMs;
      // The shop name printed on every paper is the license's: written
      // into the shop-name setting, which the invoice settings then only
      // show.
      if (picked != null) await _writeShopName(_db, picked.shopName);
    }
    return _decide(reading, await _invoiceCounter(), verified: picked);
  }

  Future<Uint8List?> _identify() async {
    try {
      final identity = await platform.deviceIdentity();
      if (identity.packageName.isEmpty) return null;
      var unique = identity.androidId.trim();
      if (unique.isEmpty) {
        // A phone without an ANDROID_ID: an id of our own stands in. It is
        // lost with the app's data, and the request code with it.
        unique = await _store.installId(create: !_readOnly) ?? '';
      }
      if (unique.isEmpty) return null;
      return deviceHashOf(
        androidId: unique,
        packageName: identity.packageName,
        salt: deviceSalt,
      );
    } on Object {
      return null;
    }
  }

  Future<BuildIntegrity> _checkIntegrity() async {
    if (!_checkSigner) return BuildIntegrity.ok;
    if (_expectedSigner.isEmpty) return BuildIntegrity.unsealed;
    try {
      final signers = await platform.signingCertificates();
      return signers.any((s) => _hexOnly(s) == _expectedSigner)
          ? BuildIntegrity.ok
          : BuildIntegrity.modified;
    } on Object {
      return BuildIntegrity.modified;
    }
  }

  /// Of the codes the stores hold, the license of THIS device (the newest,
  /// if both hold one).
  Future<LicensePayload?> _pickLicense(List<String?> candidates) async {
    LicensePayload? best;
    String? bestText;
    var foreign = false;
    for (final text in {...candidates.whereType<String>()}) {
      final (payload, problem) = await _readActivation(text);
      if (payload == null) {
        foreign = foreign || problem == ActivationError.wrongDevice;
        continue;
      }
      if (best == null || payload.issuedAt.isAfter(best.issuedAt)) {
        best = payload;
        bestText = SignedCode.parse(text)!.text;
      }
    }
    _code = bestText;
    _foreignCode = best == null && foreign;
    return best;
  }

  /// The license in [text] if the developer signed it for this device —
  /// expired or not. Otherwise why not.
  Future<(LicensePayload?, ActivationError?)> _readActivation(
    String text,
  ) async {
    final code = SignedCode.parse(text);
    if (code == null) return (null, ActivationError.malformed);
    if (code.isPinReset) return (null, ActivationError.pinResetCode);
    if (!code.isActivation) return (null, ActivationError.malformed);
    if (!configured) return (null, ActivationError.notConfigured);
    if (!await _signedByDeveloper(code)) {
      return (null, ActivationError.badSignature);
    }
    final LicensePayload payload;
    try {
      payload = LicensePayload.decode(code.payload);
    } on UnsupportedLicenseVersion {
      return (null, ActivationError.newerFormat);
    } on FormatException {
      return (null, ActivationError.malformed);
    }
    final device = _device;
    if (device == null) return (null, ActivationError.deviceUnknown);
    if (!payload.isFor(device)) return (null, ActivationError.wrongDevice);
    return (payload, null);
  }

  Future<bool> _signedByDeveloper(SignedCode code) async {
    final key = _publicKey;
    if (key == null) return false;
    try {
      return await _ed25519.verify(
        code.payload,
        signature: Signature(
          code.signature,
          publicKey: SimplePublicKey(key, type: KeyPairType.ed25519),
        ),
      );
    } on Object {
      return false;
    }
  }

  // ---- Deciding ----------------------------------------------------------

  Future<int> _invoiceCounter() async {
    final rows = await _db.query(
      'counters',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: [CounterRepository.invoiceNo],
      limit: 1,
    );
    return rows.isEmpty ? 0 : rows.first['value'] as int;
  }

  /// [verified] is the license when the caller has JUST verified the
  /// stored code itself; otherwise the code is verified here — every time,
  /// not remembered from the start.
  Future<LicenseStatus> _decide(
    ClockReading reading,
    int invoiceCounter, {
    LicensePayload? verified,
  }) async {
    final text = _code;
    final license = text == null
        ? null
        : verified ?? (await _readActivation(text)).$1;
    final next = evaluateLicense(
      license: license,
      integrity: _integrity,
      trialStartedAt: DateTime.fromMillisecondsSinceEpoch(
        _memory.trialStartMs,
        isUtc: true,
      ),
      invoicesUsed: invoiceCounter - _memory.trialInvoiceBase,
      clock: reading,
      storedCodeForOtherDevice: _foreignCode,
    );
    final changed = next != _status;
    _status = next;
    if (changed) onChanged?.call(next);
    return next;
  }

  /// Checks again, now: the signature of the stored code, the device, the
  /// clock, the trial's counters.
  Future<LicenseStatus> refresh() async {
    if (!_started) return start(readOnly: _readOnly);
    return _decide(await _look(), await _invoiceCounter());
  }

  /// One look at the clock: the mark moves, and is written when it has
  /// moved far enough.
  Future<ClockReading> _look() async {
    final reading = observeClock(_memory.clock, clock());
    _memory = _memory.copyWith(clock: reading.state);
    await _saveClock(reading);
    return reading;
  }

  Future<void> _saveClock(ClockReading reading) async {
    if (_readOnly) return;
    final latest = reading.state.latestMs;
    final turned = reading.wentBack != _lastWentBack;
    _lastWentBack = reading.wentBack;
    try {
      if (turned ||
          (latest - _databaseClockSaved).abs() >=
              _databaseClockStep.inMilliseconds) {
        await LicenseStore.saveDatabase(_db, _memory);
        _databaseClockSaved = latest;
      }
      if (_secureWritable &&
          (turned ||
              (latest - _secureClockSaved).abs() >=
                  _secureClockStep.inMilliseconds)) {
        await _store.saveSecure(_memory, code: _code);
        _secureClockSaved = latest;
      }
    } on DatabaseException {
      // The mark is in memory; the next look writes it.
    }
  }

  // ---- The guard ---------------------------------------------------------

  Future<void> _ensure(LicensedAction action) async {
    final status = await refresh();
    if (!status.allows(action)) {
      throw LicenseRequiredException(action, status);
    }
  }

  @override
  Future<void> ensureCanSell() => _ensure(LicensedAction.sell);

  @override
  Future<void> ensureCanPrint() => _ensure(LicensedAction.print);

  @override
  Future<void> ensureCanRecordDebt() => _ensure(LicensedAction.recordDebt);

  @override
  Future<void> saleSaved() async {
    try {
      // The sale was let through by [ensureCanSell] a moment ago — the
      // full check. This is only the trial's count moving on, so the
      // license of that check is used as it is.
      await _decide(
        await _look(),
        await _invoiceCounter(),
        verified: _status.license,
      );
    } on Object {
      // The sale is saved; the next check counts it.
    }
  }

  // ---- Activation --------------------------------------------------------

  /// Takes an activation code as typed, pasted or scanned. On success the
  /// code is stored (Keystore and database), the shop name of the license
  /// becomes the shop's, and [status] is licensed.
  Future<ActivationResult> activate(String input) async {
    if (!_started) await start();
    if (_integrity != BuildIntegrity.ok) {
      return ActivationResult.failed(
        _integrity == BuildIntegrity.unsealed
            ? ActivationError.unsealedBuild
            : ActivationError.modifiedApp,
      );
    }
    final (payload, problem) = await _readActivation(input);
    if (payload == null) return ActivationResult.failed(problem!);

    var reading = observeClock(_memory.clock, clock());
    final newest = payload.issuedAt.millisecondsSinceEpoch ~/ 1000 >
        _memory.maxIssuedAt;
    if (newest) {
      // A license newer than any before it: the developer's "issued at" is
      // a time the app can trust, so the clock guard starts over from it.
      reading = observeClock(restartClock(clock(), payload.issuedAt), clock());
    }
    if (!payload.isLiveAt(reading.now)) {
      return const ActivationResult.failed(ActivationError.expired);
    }
    final current = _status.license;
    if (_status.isLicensed &&
        current != null &&
        payload.issuedAt.isBefore(current.issuedAt)) {
      return const ActivationResult.failed(ActivationError.olderThanCurrent);
    }

    final text = SignedCode.parse(input)!.text;
    _code = text;
    _foreignCode = false;
    _memory = _memory.copyWith(
      clock: reading.state,
      maxIssuedAt: newest
          ? payload.issuedAt.millisecondsSinceEpoch ~/ 1000
          : _memory.maxIssuedAt,
    );
    await _db.transaction((txn) async {
      await LicenseStore.saveDatabase(txn, _memory, code: text);
      await _writeShopName(txn, payload.shopName);
      await AuditRepository(txn).log(
        AuditAction.licenseActivate,
        entityType: 'license',
        entityId: payload.licenseId,
        details: {
          'shop': payload.shopName,
          'features': featureNamesOf(payload.features).join(','),
          'expires_at': payload.expiresAt?.millisecondsSinceEpoch,
        },
      );
    });
    if (_secureWritable) await _store.saveSecure(_memory, code: text);
    _databaseClockSaved = _secureClockSaved = _memory.clock.latestMs;
    _lastWentBack = reading.wentBack;
    await _decide(reading, await _invoiceCounter(), verified: payload);
    return ActivationResult.ok(payload);
  }

  static Future<void> _writeShopName(DatabaseExecutor db, String name) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [SettingsKeys.shopName],
      limit: 1,
    );
    if (rows.isNotEmpty && rows.first['value'] == name) return;
    await db.insert(
      'settings',
      {
        'key': SettingsKeys.shopName,
        'value': name,
        'updated_at': DateTime.now().toUtc().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ---- PIN reset by the developer ----------------------------------------

  /// The check of a developer-signed "PIN reset" code: the developer's
  /// signature, THIS device, not past its end (48 hours at most, by the
  /// licensing clock), and not used before.
  Future<PinResetCheck> checkPinReset(String input) async {
    if (!_started) await start(readOnly: _readOnly);
    final code = SignedCode.parse(input);
    if (code == null || !code.isPinReset) return PinResetCheck.malformed;
    if (!await _signedByDeveloper(code)) return PinResetCheck.badSignature;
    final PinResetPayload payload;
    try {
      payload = PinResetPayload.decode(code.payload);
    } on FormatException {
      return PinResetCheck.malformed;
    }
    final device = _device;
    if (device == null || !payload.isFor(device)) {
      return PinResetCheck.wrongDevice;
    }
    if (_memory.usedResets.containsKey(payload.resetId)) {
      return PinResetCheck.alreadyUsed;
    }
    // By the licensing clock, which remembers: a date set back does not
    // bring an old code back.
    final reading = await _look();
    if (!payload.isLiveAt(reading.now)) return PinResetCheck.expired;
    return PinResetCheck.ok;
  }

  /// Marks a reset code as used — in both stores, at once: it must not work
  /// a second time even if the app is closed the next moment.
  Future<void> consumePinReset(String input) async {
    final code = SignedCode.parse(input);
    if (code == null || !code.isPinReset) return;
    final PinResetPayload payload;
    try {
      payload = PinResetPayload.decode(code.payload);
    } on FormatException {
      return;
    }
    final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;
    _memory = _memory.copyWith(usedResets: {
      // Codes long past their end need no remembering: they are refused
      // for their date.
      for (final entry in _memory.usedResets.entries)
        if (entry.value > nowSeconds - const Duration(days: 30).inSeconds)
          entry.key: entry.value,
      payload.resetId: payload.expiresAt.millisecondsSinceEpoch ~/ 1000,
    });
    await LicenseStore.saveDatabase(_db, _memory);
    if (_secureWritable) await _store.saveSecure(_memory, code: _code);
  }

  /// The `SignedPinReset` the "Forgot PIN?" dialog uses.
  late final SignedPinReset pinReset = _DeveloperPinReset(this);

  // ---- Small things ------------------------------------------------------

  static String _hexOnly(String text) => text
      .toLowerCase()
      .split('')
      .where((c) => '0123456789abcdef'.contains(c))
      .join();

  /// The 32 bytes of a public key, or null for anything that cannot be one:
  /// empty, the wrong length, or one byte repeated (a placeholder).
  static Uint8List? _hexBytes(String hex) {
    final clean = _hexOnly(hex);
    if (clean.length != 64 || clean.length != hex.trim().length) return null;
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
    }
    if (bytes.every((b) => b == bytes.first)) return null;
    return bytes;
  }
}

class _DeveloperPinReset implements SignedPinReset {
  _DeveloperPinReset(this._service);

  final LicenseService _service;

  @override
  Future<bool> verify(String code) async =>
      await _service.checkPinReset(code) == PinResetCheck.ok;

  @override
  Future<void> consume(String code) => _service.consumePinReset(code);
}
