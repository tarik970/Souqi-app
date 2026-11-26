/// THE LOCAL ERROR LOG: what went wrong on this phone, kept on this phone.
///
/// The app has no internet and no crash service. An error nobody caught is
/// written to a small text file in the app's own storage instead, and
/// Settings → About → "Share error log" hands those files to the share sheet
/// when the SHOP decides to send them (to the developer, on WhatsApp).
/// Nothing leaves the phone by itself.
///
/// - One file per engine (`errors-app.log` for the app, `errors-worker.log`
///   for the daily job's background engine), so two engines never write the
///   same file.
/// - ROTATING: a file that would grow past [maxFileBytes] becomes `.1`, the
///   old `.1` becomes `.2`, the old `.2` is deleted. At most
///   [keptGenerations] files per engine — under a megabyte in all.
/// - An error that repeats (a widget failing on every frame) is written
///   once and then counted, not written again.
/// - WHAT IS IN IT: the time, the app version, the error's own text and its
///   stack trace. In a release build the trace is obfuscated; it is read
///   with the symbols of that version
///   (`flutter symbolize -i <log> -d symbols/<version>/…`), which is why
///   every entry carries the version. The values a database error quotes
///   after its SQL (`args [...]` — names, amounts) are cut off: the log is
///   about the code, not the shop's data.
///
/// Writing never throws and never blocks the caller: an error log that can
/// crash the app is worse than none.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

class ErrorLog {
  ErrorLog._();

  /// The log of this engine. [init] decides where it writes.
  static final ErrorLog instance = ErrorLog._();

  /// Most bytes of one log file before it is rotated.
  static const int maxFileBytes = 256 * 1024;

  /// Files kept per engine: the current one and two older.
  static const int keptGenerations = 3;

  /// Most characters of one error's text, and of one stack trace.
  static const int maxMessageChars = 2000;
  static const int maxStackChars = 12000;

  /// Entries written per minute at most: a broken loop must not grind the
  /// phone's storage.
  static const int maxEntriesPerMinute = 30;

  Directory? _directory;
  String _engine = 'app';

  /// The version on the entries ("1.0.0+1"). It is read from the platform
  /// after the log has started, so the first entries may carry "?".
  String appVersion = '';
  DateTime Function() _now = DateTime.now;

  /// The write in flight, and behind it the ones waiting: one after
  /// another, in the order the errors came. Null while nothing is being
  /// written — never a finished future kept around to chain on.
  Future<void>? _queue;

  String? _lastSignature;
  int _repeats = 0;
  DateTime? _windowStart;
  int _windowCount = 0;

  bool get isReady => _directory != null;

  /// Where this engine's current file is. Null before [init].
  File? get currentFile {
    final directory = _directory;
    return directory == null
        ? null
        : File(p.join(directory.path, _name(_engine, 0)));
  }

  static String _name(String engine, int generation) => generation == 0
      ? 'errors-$engine.log'
      : 'errors-$engine.$generation.log';

  /// Starts the log of this engine in [directory] (created when missing).
  /// [engine] is `app` or `worker`; [appVersion] ("1.0.0+1") goes on every
  /// entry. Errors recorded before this call are dropped.
  void init({
    required Directory directory,
    required String appVersion,
    String engine = 'app',
    DateTime Function() now = DateTime.now,
  }) {
    _directory = directory;
    _engine = engine;
    this.appVersion = appVersion;
    _now = now;
    _lastSignature = null;
    _repeats = 0;
    _windowStart = null;
    _windowCount = 0;
  }

  /// Writes one error. [context] says where it was caught ("uncaught",
  /// "flutter", "daily job"). Returns at once; the write is queued. Never
  /// throws.
  void record(Object error, StackTrace? stack, {String context = 'uncaught'}) {
    final directory = _directory;
    if (directory == null) return;
    try {
      final now = _now();
      final message = _clip(scrub('$error'), maxMessageChars);
      final trace = stack == null ? '' : _clip('$stack'.trimRight(), maxStackChars);
      final signature = '$context|$message|${_firstLine(trace)}';

      // The same error again: counted, not written.
      if (signature == _lastSignature) {
        _repeats++;
        return;
      }
      // Too many different ones in a minute: dropped.
      final windowStart = _windowStart;
      if (windowStart == null ||
          now.difference(windowStart).abs() >= const Duration(minutes: 1)) {
        _windowStart = now;
        _windowCount = 0;
      }
      if (++_windowCount > maxEntriesPerMinute) return;

      final entry = StringBuffer();
      if (_repeats > 0) {
        entry.writeln('     (the error above came $_repeats more times)');
      }
      _lastSignature = signature;
      _repeats = 0;
      entry
        ..writeln('==== ${_stamp(now)} [$_engine] $context · v$appVersion')
        ..writeln(message);
      if (trace.isNotEmpty) entry.writeln(trace);
      entry.writeln();
      final text = entry.toString();
      final before = _queue;
      late final Future<void> mine;
      mine = (before == null
              ? _append(directory, text)
              : before.then((_) => _append(directory, text)))
          .whenComplete(() {
        if (identical(_queue, mine)) _queue = null;
      });
      _queue = mine;
    } catch (_) {
      // Never from here.
    }
  }

  /// Completes when everything recorded so far is on disk.
  Future<void> flush() => _queue ?? Future<void>.value();

  Future<void> _append(Directory directory, String text) async {
    try {
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, _name(_engine, 0)));
      final size = await file.exists() ? await file.length() : 0;
      if (size > 0 && size + text.length > maxFileBytes) {
        await _rotate(directory);
      }
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } on Object {
      // Storage full or gone: the app goes on without its log.
    }
  }

  Future<void> _rotate(Directory directory) async {
    final oldest = File(p.join(directory.path, _name(_engine, keptGenerations - 1)));
    if (await oldest.exists()) await oldest.delete();
    for (var generation = keptGenerations - 2; generation >= 0; generation--) {
      final file = File(p.join(directory.path, _name(_engine, generation)));
      if (await file.exists()) {
        await file.rename(p.join(directory.path, _name(_engine, generation + 1)));
      }
    }
  }

  /// Every log file in [directory] — of both engines, and the Android
  /// side's own (`errors-native.log`) — oldest entries first.
  static Future<List<File>> filesIn(Directory directory) async {
    if (!await directory.exists()) return const [];
    final files = <File>[];
    await for (final entity in directory.list()) {
      final name = p.basename(entity.path);
      if (entity is File && name.startsWith('errors-') && name.endsWith('.log')) {
        files.add(entity);
      }
    }
    // errors-app.2.log, errors-app.1.log, errors-app.log, then the next
    // engine: within an engine the highest generation is the oldest.
    int generation(String name) {
      final parts = name.split('.');
      return parts.length == 3 ? int.tryParse(parts[1]) ?? 0 : 0;
    }

    String engine(String name) => name.split('.').first;
    files.sort((a, b) {
      final nameA = p.basename(a.path);
      final nameB = p.basename(b.path);
      final byEngine = engine(nameA).compareTo(engine(nameB));
      return byEngine != 0
          ? byEngine
          : generation(nameB).compareTo(generation(nameA));
    });
    return files;
  }

  /// Every log file as one text, and how many errors it holds — the body of
  /// what "Share error log" sends (the caller puts the app version, the
  /// phone and the license state on top).
  static Future<ErrorLogExport> export(Directory directory) async {
    final out = StringBuffer();
    var entries = 0;
    for (final file in await filesIn(directory)) {
      String text;
      try {
        text = await file.readAsString();
      } on FileSystemException {
        continue;
      } on FormatException {
        // A file cut off in the middle of a character (the phone lost
        // power while it was written).
        text = String.fromCharCodes(await file.readAsBytes());
      }
      if (text.trim().isEmpty) continue;
      entries += '\n$text'.split('\n==== ').length - 1;
      // The Android side's file has no "====" lines: each crash starts with
      // "#### ".
      entries += '\n$text'.split('\n#### ').length - 1;
      out
        ..writeln('---- ${p.basename(file.path)} ----')
        ..writeln(text.trimRight())
        ..writeln();
    }
    return ErrorLogExport(text: out.toString(), entryCount: entries);
  }

  /// Deletes every log file in [directory].
  static Future<void> clear(Directory directory) async {
    for (final file in await filesIn(directory)) {
      try {
        await file.delete();
      } on FileSystemException {
        // In use by the other engine: it stays.
      }
    }
    instance
      .._lastSignature = null
      .._repeats = 0;
  }

  /// [message] without the VALUES of a failed SQL statement. sqflite quotes
  /// them after the statement (`… sql 'INSERT …' args [Ahmad, 5000]`); the
  /// statement says what failed, the values are the shop's data.
  static String scrub(String message) {
    final at = message.indexOf(' args [');
    return at < 0 ? message : '${message.substring(0, at)} args [...]';
  }

  static String _clip(String text, int most) =>
      text.length <= most ? text : '${text.substring(0, most)}\n… (cut)';

  static String _firstLine(String text) {
    final end = text.indexOf('\n');
    return end < 0 ? text : text.substring(0, end);
  }

  /// Local time with its offset, readable and sortable.
  static String _stamp(DateTime moment) {
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = moment.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${moment.year}-${two(moment.month)}-${two(moment.day)} '
        '${two(moment.hour)}:${two(moment.minute)}:${two(moment.second)} '
        '$sign${two(minutes ~/ 60)}:${two(minutes % 60)}';
  }
}

class ErrorLogExport {
  const ErrorLogExport({required this.text, required this.entryCount});

  final String text;

  /// How many errors the text holds; 0 = nothing was ever recorded.
  final int entryCount;
}

/// Records an error that WAS caught — the user saw a message and the app
/// went on — but that the developer will want to know about: a print that
/// failed for an unknown reason, a screen that could not load.
void reportError(Object error, StackTrace? stack, {required String context}) =>
    ErrorLog.instance.record(error, stack, context: context);
