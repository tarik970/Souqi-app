import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/security/code_cipher.dart';

/// THE SWAP of a restore — the one step that replaces the shop's data — and
/// its way back.
///
/// Until the restored database is checked, migrated and ready, nothing of
/// the current data is touched (that work happens on a copy, see
/// `BackupService.restore`). Then, with a JOURNAL on disk so that a crash or
/// a dead battery half-way can be undone on the next start:
///
///  1. the current card-code keys are kept aside in the Keystore;
///  2. the marker `souqi.restore.json` says "swapping";
///  3. the live database is closed and renamed `souqi.before-restore.db`;
///  4. the prepared one is renamed `souqi.db`;
///  5. the restored keys are written (or the entry removed when the backup
///     had none);
///  6. the database is opened again;
///  7. the marker says "committed"; the old file and the kept keys go.
///
/// Any failure in 3–6 rolls back: the old file goes back to its name, the old
/// keys back into the Keystore, and the old database is opened again.
/// [recover] does the same on app start for a restore that never finished.
/// Renames within one folder are atomic, so at every moment one of the two
/// complete databases is there.
class RestoreJournal {
  RestoreJournal({required this.dbPath, required this.keys});

  /// The live database file (`…/databases/souqi.db`).
  final String dbPath;
  final SecretKeyStore keys;

  String get _dir => p.dirname(dbPath);

  /// Where the prepared database waits (same folder: the rename is atomic).
  String get stagedPath => p.join(_dir, 'souqi.restore.db');

  String get beforePath => p.join(_dir, 'souqi.before-restore.db');

  String get markerPath => p.join(_dir, 'souqi.restore.json');

  /// The Keystore entry the current card-code keys wait in meanwhile.
  static const String keptKeysName = '${CodeCipher.keyName}.before-restore';

  /// "There was no key": a restore over a phone that never had card codes.
  static const String _noKey = '-';

  static const _sidecars = ['', '-journal', '-wal', '-shm'];

  /// Whether a restore was left half-way (the app was killed during the
  /// swap). The background engine stays away from the database then.
  static Future<bool> pending(String dbPath) =>
      File(p.join(p.dirname(dbPath), 'souqi.restore.json')).exists();

  Future<void> _writeMarker(String stage) async {
    final tmp = File('$markerPath.tmp');
    await tmp.writeAsString(jsonEncode({'stage': stage}), flush: true);
    await tmp.rename(markerPath);
  }

  Future<String?> _readStage() async {
    final file = File(markerPath);
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(await file.readAsString());
      return json is Map ? json['stage'] as String? : 'swapping';
    } on Object {
      // A marker cut short is a swap that had begun.
      return 'swapping';
    }
  }

  static Future<void> deleteDatabaseFiles(String path) async {
    for (final suffix in _sidecars) {
      final file = File('$path$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  /// Renames the database and whatever journal files go with it (SQLite
  /// finds them by name, so they must move together).
  static Future<void> _move(String from, String to) async {
    await deleteDatabaseFiles(to);
    for (final suffix in _sidecars) {
      final file = File('$from$suffix');
      if (await file.exists()) await file.rename('$to$suffix');
    }
  }

  /// Steps 1–7. [close] closes the live database, [open] opens the one at
  /// [dbPath]; [fault] lets the tests break the swap at a named step.
  ///
  /// Returns the opened restored database. On failure everything is put
  /// back and [RestoreFailedException] carries the reopened OLD database,
  /// which the app goes on with.
  Future<T> swap<T>({
    required String? newKeys,
    required Future<void> Function() close,
    required Future<T> Function() open,
    required Future<void> Function(T db) closeOpened,
    void Function(String step)? fault,
  }) async {
    if (!await File(stagedPath).exists()) {
      throw StateError('no prepared database at $stagedPath');
    }
    // 1–2: nothing has changed yet if this fails.
    final current = await keys.read(CodeCipher.keyName);
    await keys.write(keptKeysName, current ?? _noKey);
    await _writeMarker('swapping');

    await close();
    T? opened;
    try {
      await _move(dbPath, beforePath);
      fault?.call('moved-old');
      await _move(stagedPath, dbPath);
      fault?.call('moved-new');
      if (newKeys == null) {
        await keys.delete(CodeCipher.keyName);
      } else {
        await keys.write(CodeCipher.keyName, newKeys);
      }
      fault?.call('keys');
      opened = await open();
      fault?.call('opened');
      await _writeMarker('committed');
    } on Object catch (error, stack) {
      if (opened != null) {
        try {
          await closeOpened(opened);
        } on Object {
          // Closing is all that is left to do with it.
        }
      }
      await rollBack();
      final T old;
      try {
        old = await open();
      } on Object {
        Error.throwWithStackTrace(error, stack);
      }
      throw RestoreFailedException(error, old);
    }
    try {
      await _cleanUp();
    } on Object {
      // Committed: the next start's [recover] finishes the tidying.
    }
    return opened as T;
  }

  /// Puts the shop back as it was before the swap began.
  Future<void> rollBack() async {
    if (await File(beforePath).exists()) {
      // The restored file (if it got there) gives way to the old one.
      await _move(beforePath, dbPath);
    }
    final kept = await keys.read(keptKeysName);
    if (kept != null) {
      if (kept == _noKey) {
        await keys.delete(CodeCipher.keyName);
      } else {
        await keys.write(CodeCipher.keyName, kept);
      }
      await keys.delete(keptKeysName);
    }
    await deleteDatabaseFiles(stagedPath);
    final marker = File(markerPath);
    if (await marker.exists()) await marker.delete();
  }

  Future<void> _cleanUp() async {
    await deleteDatabaseFiles(beforePath);
    await deleteDatabaseFiles(stagedPath);
    await keys.delete(keptKeysName);
    final marker = File(markerPath);
    if (await marker.exists()) await marker.delete();
  }

  /// ON APP START, before the database is opened: finishes or undoes a
  /// restore the app was killed in the middle of. Returns what it did.
  Future<RestoreRecovery> recover() async {
    final stage = await _readStage();
    switch (stage) {
      case null:
        // A prepared file left by a restore that failed before the swap.
        await deleteDatabaseFiles(stagedPath);
        return RestoreRecovery.none;
      case 'committed':
        await _cleanUp();
        return RestoreRecovery.completed;
      default:
        await rollBack();
        return RestoreRecovery.rolledBack;
    }
  }
}

enum RestoreRecovery { none, completed, rolledBack }

/// The restore failed during the swap and was undone; [database] is the
/// shop's own database, opened again.
class RestoreFailedException<T> implements Exception {
  const RestoreFailedException(this.cause, this.database);

  final Object cause;
  final T database;

  @override
  String toString() => 'RestoreFailedException($cause)';
}
