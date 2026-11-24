@Tags(['performance'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/dev/invoice_seeder.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/data/repositories/maintenance_repository.dart';
import 'package:souqi/data/repositories/stats_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

/// Times the queries the archive and statistics screens run against a
/// 50,000-invoice archive — the size the brief asks them to stay smooth at.
///
/// On a REAL FILE, not in memory: the page cache and index behaviour of an
/// in-memory database say nothing about a phone.
///
/// Seeding 50,000 invoices takes minutes, so the whole run is gated on an
/// environment variable and skips itself otherwise:
///
///     SOUQI_PERF=1 flutter test test/data/archive_performance_test.dart
///
/// The assertions are deliberately loose: they are there to catch a lost
/// index (a full scan is orders of magnitude slower), not to pin a number to
/// one machine. The printed timings are the point.
void main() {
  // Gated on the environment, not on the tag alone: a tag cannot stop a
  // plain test run from spending two minutes seeding, and this way the
  // expensive setUpAll below is never even registered.
  if (Platform.environment['SOUQI_PERF'] != '1') {
    test('archive timings', () {}, skip: 'set SOUQI_PERF=1 to run');
    return;
  }

  setUpAll(sqfliteFfiInit);

  const invoices = 50000;

  late Directory directory;
  late AppDatabase appDb;
  late ArchiveRepository archive;
  late StatsRepository stats;
  late MaintenanceRepository maintenance;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('souqi-perf');
    appDb = await AppDatabase.open(
      factory: databaseFactoryFfi,
      path: '${directory.path}/souqi.db',
    );
    archive = ArchiveRepository(appDb.db);
    stats = StatsRepository(appDb.db);
    maintenance = MaintenanceRepository(appDb.db, filePath: appDb.path);

    await appDb.db.update(
      'currencies',
      {'rate_num': 13000, 'rate_den': 1, 'rate_updated_at': 1},
      where: 'code = ?',
      whereArgs: ['USD'],
    );
    await insertProduct(appDb.db, name: 'سكر');

    final watch = Stopwatch()..start();
    final created = await seedTestInvoices(appDb.db, count: invoices);
    expect(created, invoices);
    _report('seeding $invoices invoices', watch.elapsed);
    _note(
      'database file',
      '${await maintenance.databaseSizeBytes() ~/ 1024} KB',
    );
  });

  tearDownAll(() async {
    await appDb.close();
    await directory.delete(recursive: true);
  });

  /// Runs [action] and prints how long it took.
  Future<Duration> time(String label, Future<void> Function() action) async {
    final watch = Stopwatch()..start();
    await action();
    final elapsed = watch.elapsed;
    _report(label, elapsed);
    return elapsed;
  }

  final today = DateTime.now();
  final month = DateTime(today.year, today.month);
  final nextMonth = DateTime(today.year, today.month + 1);

  test('the archive summary aggregate', () async {
    final elapsed = await time('archive summary (whole archive)', () async {
      final summary = await archive.summary(const ArchiveFilter());
      expect(summary.count, invoices);
    });
    expect(elapsed.inMilliseconds, lessThan(2000));
  });

  test('the delete confirmation count for a month', () async {
    final elapsed = await time('delete-dialog count (one month)', () async {
      await archive.summary(ArchiveFilter(from: month, to: nextMonth));
    });
    expect(elapsed.inMilliseconds, lessThan(1000));
  });

  test('the first page of the archive', () async {
    final elapsed = await time('first page (30 rows)', () async {
      final page = await archive.page();
      expect(page, hasLength(ArchiveRepository.pageSize));
    });
    expect(elapsed.inMilliseconds, lessThan(1000));
  });

  test('a page deep in the archive', () async {
    // Walk 20 pages in and time the one after: keyset paging must not get
    // slower the further down it goes.
    var cursor = (await archive.page()).last.cursor;
    for (var i = 0; i < 20; i++) {
      cursor = (await archive.page(after: cursor)).last.cursor;
    }
    final elapsed = await time('page 21 (30 rows)', () async {
      final page = await archive.page(after: cursor);
      expect(page, hasLength(ArchiveRepository.pageSize));
    });
    expect(elapsed.inMilliseconds, lessThan(1000));
  });

  test('an Arabic product search', () async {
    final elapsed =
        await time('product search (Arabic, whole archive)', () async {
      final page = await archive.page(
        filter: const ArchiveFilter(productQuery: 'السكر'),
      );
      expect(page, isNotEmpty);
    });
    expect(elapsed.inMilliseconds, lessThan(5000));
  });

  test('a customer search', () async {
    final elapsed = await time('customer search (no match)', () async {
      await archive.page(
        filter: const ArchiveFilter(customerQuery: '0944123456'),
      );
    });
    expect(elapsed.inMilliseconds, lessThan(5000));
  });

  test('the statistics screen for a month', () async {
    final elapsed = await time('stats screen (5 aggregates)', () async {
      await stats.summary(from: month, to: nextMonth, baseDecimals: 0);
      await stats.summary(
        from: DateTime(today.year, today.month - 1),
        to: month,
        baseDecimals: 0,
      );
      await stats.topProducts(
        from: month,
        to: nextMonth,
        baseDecimals: 0,
        ranking: ProductRanking.sales,
      );
      await stats.topProducts(
        from: month,
        to: nextMonth,
        baseDecimals: 0,
        ranking: ProductRanking.amount,
      );
      await stats.byCurrency(from: month, to: nextMonth);
    });
    expect(elapsed.inMilliseconds, lessThan(8000));
  });

  test('the statistics screen for a whole year', () async {
    final elapsed = await time('stats screen (one year)', () async {
      final year = DateTime(today.year - 1, today.month);
      await stats.summary(from: year, to: nextMonth, baseDecimals: 0);
      await stats.topProducts(
        from: year,
        to: nextMonth,
        baseDecimals: 0,
        ranking: ProductRanking.amount,
      );
    });
    expect(elapsed.inMilliseconds, lessThan(10000));
  });

  // Named to sort last: it empties the archive the tests above measure.
  test('zz clearing the whole archive in chunks, then VACUUM', () async {
    final before = await maintenance.databaseSizeBytes();
    var deleted = 0;
    var chunks = 0;
    final elapsed = await time('delete all $invoices (chunked)', () async {
      while (true) {
        final gone = await archive.deleteMatchingChunk(const ArchiveFilter());
        if (gone == 0) break;
        deleted += gone;
        chunks++;
      }
    });
    expect(deleted, invoices);
    expect(await archive.countMatching(const ArchiveFilter()), 0);
    _report(
      'per chunk of ${ArchiveRepository.deleteChunkSize}',
      Duration(microseconds: elapsed.inMicroseconds ~/ chunks),
    );

    await time('VACUUM', () => maintenance.vacuum());
    final after = await maintenance.databaseSizeBytes();
    expect(after, lessThan(before));
    _note(
      'file after VACUUM',
      '${after ~/ 1024} KB (was ${before ~/ 1024} KB)',
    );
  });
}

void _report(String label, Duration elapsed) =>
    _note(label, '${elapsed.inMilliseconds} ms');

void _note(String label, String value) {
  // ignore: avoid_print
  print('PERF  ${label.padRight(40)} $value');
}
