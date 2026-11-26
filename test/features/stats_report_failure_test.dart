import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/features/stats/stats_providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// The statistics report asks nine questions at once. When the database goes
/// away under them (a restore closes it; a test's tearDown does) the report
/// fails ONCE, as the provider's own error — nothing is left to fail on its
/// own afterwards, with nobody listening.
void main() {
  setUpAll(sqfliteFfiInit);

  test('a report whose queries fail fails as one error, none left unhandled',
      () async {
    final database = await openTestDb();
    final unhandled = <Object>[];
    Object? reported;

    await runZonedGuarded(() async {
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
        // One attempt: the retries would only fail the same way.
        retry: (_, _) => null,
      );
      // The base currency is read first; the queries after it find the
      // database closed.
      await container.read(baseCurrencyProvider.future);
      await database.close();
      try {
        await container.read(statsReportProvider.future);
      } on Object catch (error) {
        reported = error;
      }
      // Time for a second failure to surface, were there one.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      container.dispose();
    }, (error, _) => unhandled.add(error));

    expect('$reported', contains('database_closed'));
    expect(unhandled, isEmpty);
  });
}
