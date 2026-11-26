import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:souqi/core/logging/error_log.dart';
import 'package:souqi/core/logging/error_reporting.dart';

void main() {
  late Directory dir;
  late DateTime now;
  final log = ErrorLog.instance;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('souqi_error_log_test');
    now = DateTime(2026, 11, 26, 14, 5, 9);
    log.init(
      directory: dir,
      appVersion: '1.0.0+1',
      engine: 'app',
      now: () => now,
    );
  });

  tearDown(() async {
    await log.flush();
    await dir.delete(recursive: true);
  });

  Future<String> current() async {
    await log.flush();
    final file = File(p.join(dir.path, 'errors-app.log'));
    return file.existsSync() ? file.readAsString() : '';
  }

  test('an error is written with its time, engine, context, version and stack',
      () async {
    log.record(
      StateError('boom'),
      StackTrace.fromString('#0 main (file.dart:1)\n#1 other'),
      context: 'uncaught',
    );
    final text = await current();
    expect(text, contains('==== 2026-11-26 14:05:09'));
    expect(text, contains('[app] uncaught · v1.0.0+1'));
    expect(text, contains('Bad state: boom'));
    expect(text, contains('#0 main (file.dart:1)'));
  });

  test('the values of a failed SQL statement are cut off', () async {
    const message = "DatabaseException(UNIQUE constraint failed) sql "
        "'INSERT INTO customers (name, phone) VALUES (?, ?)' "
        'args [Ahmad Khatib, 0944123456]';
    expect(
      ErrorLog.scrub(message),
      "DatabaseException(UNIQUE constraint failed) sql "
      "'INSERT INTO customers (name, phone) VALUES (?, ?)' args [...]",
    );
    log.record(Exception(message), null);
    final text = await current();
    expect(text, contains('INSERT INTO customers'));
    expect(text, isNot(contains('Ahmad')));
    expect(text, isNot(contains('0944123456')));
  });

  test('an error that repeats is written once and counted', () async {
    final stack = StackTrace.fromString('#0 build (widget.dart:10)');
    for (var i = 0; i < 50; i++) {
      log.record(StateError('every frame'), stack, context: 'flutter');
    }
    log.record(StateError('another'), stack, context: 'flutter');
    final text = await current();
    expect('every frame'.allMatches(text), hasLength(1));
    expect(text, contains('came 49 more times'));
    expect(text, contains('another'));
  });

  test('a storm of different errors is capped per minute', () async {
    for (var i = 0; i < 200; i++) {
      log.record(StateError('error $i'), null);
    }
    var text = await current();
    expect('===='.allMatches(text), hasLength(ErrorLog.maxEntriesPerMinute));
    // A minute later the log writes again.
    now = now.add(const Duration(minutes: 2));
    log.record(StateError('later'), null);
    text = await current();
    expect(text, contains('later'));
  });

  test('the file rotates: three generations, the oldest is dropped', () async {
    // Entries of about 11 KB: some twenty fill a file.
    final big = StackTrace.fromString('y' * 11000);
    for (var i = 0; i < 90; i++) {
      // Different text and time each, so nothing is deduplicated or capped.
      now = now.add(const Duration(minutes: 2));
      log.record(StateError('entry $i.'), big);
    }
    await log.flush();
    final names = [
      for (final f in await ErrorLog.filesIn(dir)) p.basename(f.path),
    ];
    expect(names, ['errors-app.2.log', 'errors-app.1.log', 'errors-app.log']);
    for (final f in await ErrorLog.filesIn(dir)) {
      expect(await f.length(), lessThanOrEqualTo(ErrorLog.maxFileBytes));
    }
    // The newest entry is in the current file, the first ones are gone.
    expect(await current(), contains('entry 89.'));
    final all = (await ErrorLog.export(dir)).text;
    expect(all, isNot(contains('entry 0.')));
    expect(all, contains('entry 60.'));
  });

  test('the export joins both engines and the native file, oldest first, '
      'and counts the errors', () async {
    log.record(StateError('from the app'), null);
    await log.flush();
    log.init(directory: dir, appVersion: '1.0.0+1', engine: 'worker');
    log.record(StateError('from the worker'), null, context: 'daily job');
    await log.flush();
    await File(p.join(dir.path, 'errors-native.log')).writeAsString(
      '#### 2026-11-26 14:00:00 +0300 [native] thread main · v1.0.0+1\n'
      'java.lang.IllegalStateException: native\n\n',
    );
    await File(p.join(dir.path, 'unrelated.txt')).writeAsString('no');

    final export = await ErrorLog.export(dir);
    expect(export.entryCount, 3);
    expect(export.text, contains('---- errors-app.log ----'));
    expect(export.text, contains('from the app'));
    expect(export.text, contains('---- errors-worker.log ----'));
    expect(export.text, contains('[worker] daily job'));
    expect(export.text, contains('IllegalStateException: native'));
    expect(export.text, isNot(contains('unrelated')));

    final header = errorLogHeader(
      appVersion: '1.0.0+1',
      createdAt: DateTime(2026, 11, 26, 14, 12),
      errorCount: export.entryCount,
      facts: const {'Database': 'schema 7', 'License': 'activated, lifetime'},
    );
    expect(header, contains('App: 1.0.0+1'));
    expect(header, contains('Database: schema 7'));
    expect(header, contains('License: activated, lifetime'));
    expect(header, contains('Errors recorded: 3'));
    expect(errorLogFileName(DateTime(2026, 11, 26, 14, 12)),
        'souqi-error-log-20261126-1412.txt');
  });

  test('an empty log exports as nothing, and says so', () async {
    final export = await ErrorLog.export(dir);
    expect(export.entryCount, 0);
    expect(export.text, isEmpty);
    expect(
      errorLogHeader(
        appVersion: '1.0.0+1',
        createdAt: now,
        errorCount: 0,
      ),
      contains('Errors recorded: none'),
    );
  });

  test('recording never throws, even where nothing can be written', () async {
    // A FILE where the folder should be.
    final blocked = File(p.join(dir.path, 'not-a-folder'));
    await blocked.writeAsString('x');
    log.init(directory: Directory(blocked.path), appVersion: '1', engine: 'app');
    expect(() => log.record(StateError('lost'), null), returnsNormally);
    await log.flush();
  });
}
