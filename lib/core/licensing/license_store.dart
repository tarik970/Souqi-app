/// Where licensing keeps what it must not forget — in TWO places, each a
/// copy of the other: the Android Keystore (flutter_secure_storage) and the
/// `settings` table.
///
/// Two, because each can be lost alone: a Keystore entry can vanish with an
/// OS update or a lock-screen change, and the database is replaced by a
/// restore. Reading merges them so that losing either one — or putting an
/// older one back — never gains anything: the EARLIEST trial start, the
/// LATEST time seen, the NEWEST license, every used reset code.
library;

import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import '../constants/settings_keys.dart';
import '../security/code_cipher.dart';
import 'clock_guard.dart';

/// What licensing remembers, apart from the activation code itself.
class LicenseMemory {
  const LicenseMemory({
    this.trialStartMs = 0,
    this.trialInvoiceBase = 0,
    this.clock = const ClockState(),
    this.maxIssuedAt = 0,
    this.usedResets = const {},
  });

  /// When the trial began (epoch milliseconds, UTC); 0 = not begun.
  final int trialStartMs;

  /// The invoice counter when the trial began: a shop that already had
  /// invoices when licensing arrived gets thirty more, like anyone else.
  final int trialInvoiceBase;

  /// The clock guard's state.
  final ClockState clock;

  /// "Issued at" (seconds) of the newest license ever activated.
  final int maxIssuedAt;

  /// PIN reset codes already used: reset id → its "expires at" (seconds).
  final Map<int, int> usedResets;

  bool get isEmpty =>
      trialStartMs == 0 &&
      clock.isEmpty &&
      maxIssuedAt == 0 &&
      usedResets.isEmpty;

  LicenseMemory copyWith({
    int? trialStartMs,
    int? trialInvoiceBase,
    ClockState? clock,
    int? maxIssuedAt,
    Map<int, int>? usedResets,
  }) =>
      LicenseMemory(
        trialStartMs: trialStartMs ?? this.trialStartMs,
        trialInvoiceBase: trialInvoiceBase ?? this.trialInvoiceBase,
        clock: clock ?? this.clock,
        maxIssuedAt: maxIssuedAt ?? this.maxIssuedAt,
        usedResets: usedResets ?? this.usedResets,
      );

  /// Both memories as one, each fact taken from the side that gives away
  /// less.
  static LicenseMemory merge(LicenseMemory a, LicenseMemory b) {
    // The trial belongs to whoever began it first.
    final LicenseMemory trial;
    if (a.trialStartMs == 0) {
      trial = b;
    } else if (b.trialStartMs == 0) {
      trial = a;
    } else {
      trial = a.trialStartMs <= b.trialStartMs ? a : b;
    }
    return LicenseMemory(
      trialStartMs: trial.trialStartMs,
      trialInvoiceBase: trial.trialInvoiceBase,
      clock: ClockState.newer(a.clock, b.clock),
      maxIssuedAt: a.maxIssuedAt > b.maxIssuedAt ? a.maxIssuedAt : b.maxIssuedAt,
      usedResets: {...a.usedResets, ...b.usedResets},
    );
  }

  Map<String, Object?> toJson() => {
        'v': 1,
        'trial': trialStartMs,
        'base': trialInvoiceBase,
        'latest': clock.latestMs,
        'last': clock.lastNowMs,
        'issued': maxIssuedAt,
        'resets': {
          for (final entry in usedResets.entries) '${entry.key}': entry.value,
        },
      };

  static LicenseMemory fromJson(Object? json) {
    if (json is! Map) return const LicenseMemory();
    int number(String key) {
      final value = json[key];
      return value is int ? value : 0;
    }

    final resets = <int, int>{};
    final raw = json['resets'];
    if (raw is Map) {
      for (final entry in raw.entries) {
        final id = int.tryParse('${entry.key}');
        final until = entry.value;
        if (id != null && until is int) resets[id] = until;
      }
    }
    return LicenseMemory(
      trialStartMs: number('trial'),
      trialInvoiceBase: number('base'),
      clock: ClockState(latestMs: number('latest'), lastNowMs: number('last')),
      maxIssuedAt: number('issued'),
      usedResets: resets,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LicenseMemory && jsonEncode(other.toJson()) == jsonEncode(toJson());

  @override
  int get hashCode => jsonEncode(toJson()).hashCode;
}

/// What the two stores held when they were read.
class LoadedLicense {
  const LoadedLicense({
    required this.memory,
    required this.secureCode,
    required this.databaseCode,
    required this.secureMemory,
    required this.databaseMemory,
    required this.secureReadable,
  });

  /// Both memories merged.
  final LicenseMemory memory;

  /// The activation code each store holds (the text as stored), or null.
  final String? secureCode;
  final String? databaseCode;

  /// Each store's own memory, to see which one is behind.
  final LicenseMemory secureMemory;
  final LicenseMemory databaseMemory;

  /// False when the Keystore did not answer: nothing is written to it then.
  final bool secureReadable;
}

class LicenseStore {
  LicenseStore(this._db, this._keys);

  final Database _db;
  final SecretKeyStore _keys;

  /// The Keystore entry: `{"code": …, …the memory…}`.
  static const String keyName = 'souqi.license.v1';

  /// A random id made on the first start of a phone that has no ANDROID_ID,
  /// to stand in for it. It dies with the app's data.
  static const String installIdName = 'souqi.install_id.v1';

  Future<String?> _setting(String key) async {
    final rows = await _db.query(
      'settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  static String? _blankToNull(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;

  static Object? _decode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  Future<LoadedLicense> load() async {
    Object? secureJson;
    var secureReadable = true;
    try {
      secureJson = _decode(await _keys.read(keyName));
    } on Object {
      secureReadable = false;
    }
    final secureMemory = LicenseMemory.fromJson(secureJson);
    final databaseMemory =
        LicenseMemory.fromJson(_decode(await _setting(SettingsKeys.licenseState)));
    return LoadedLicense(
      memory: LicenseMemory.merge(secureMemory, databaseMemory),
      secureCode: secureJson is Map ? _blankToNull(secureJson['code']) : null,
      databaseCode: _blankToNull(await _setting(SettingsKeys.licenseCode)),
      secureMemory: secureMemory,
      databaseMemory: databaseMemory,
      secureReadable: secureReadable,
    );
  }

  /// Writes the Keystore's copy. A Keystore that does not answer is not an
  /// error here: the database holds the other copy.
  Future<void> saveSecure(LicenseMemory memory, {String? code}) async {
    try {
      await _keys.write(
        keyName,
        jsonEncode({...memory.toJson(), 'code': ?code}),
      );
    } on Object {
      // The next start writes it again.
    }
  }

  /// The rows of the database's copy, for [executor] (a transaction when
  /// something else must land with them).
  static Future<void> saveDatabase(
    DatabaseExecutor executor,
    LicenseMemory memory, {
    String? code,
  }) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    Future<void> put(String key, String value) => executor.insert(
          'settings',
          {'key': key, 'value': value, 'updated_at': now},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    await put(SettingsKeys.licenseState, jsonEncode(memory.toJson()));
    if (code != null) await put(SettingsKeys.licenseCode, code);
  }

  /// The stand-in for a missing ANDROID_ID; [create] makes one when there is
  /// none yet. Null when there is none and none may be made.
  Future<String?> installId({required bool create}) async {
    try {
      final existing = _blankToNull(await _keys.read(installIdName));
      if (existing != null || !create) return existing;
      final fresh = _randomId();
      await _keys.write(installIdName, fresh);
      return fresh;
    } on Object {
      return null;
    }
  }

  static String _randomId() {
    final random = Random.secure();
    return [
      for (var i = 0; i < 16; i++)
        random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
  }
}
