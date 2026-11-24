import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/app.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/maintenance_repository.dart';
import 'package:souqi/features/settings/about_screen.dart';
import 'package:souqi/features/settings/storage_providers.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// Settings → About reads its figures from the database, so its futures only
/// progress inside [WidgetTester.runAsync] — see [settle].
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;

  setUp(() async => database = await openTestDb());
  tearDown(() async => database.close());

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  Future<void> pump(WidgetTester tester, Widget home,
      {double textScale = 1.0}) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(360, 640) * 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(database)],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildTheme(),
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('About shows how many invoices are stored', (tester) async {
    await tester.runAsync(() async {
      await insertInvoice(database.db, invoiceNo: 1);
      await insertInvoice(database.db, invoiceNo: 2);
      await insertInvoice(database.db, invoiceNo: 3);
    });

    await pump(tester, const AboutScreen());

    expect(find.text('Invoices stored'), findsOneWidget);
    expect(find.text('Database size'), findsOneWidget);
    final count = tester.widget<ListTile>(
      find.byKey(const ValueKey('about-invoice-count')),
    );
    expect((count.trailing! as Text).data, '3');
    // The test database is in memory: no file to measure.
    expect(find.text('0 B'), findsOneWidget);
  });

  testWidgets('About fits a small phone at a large system font',
      (tester) async {
    await pump(tester, const AboutScreen(), textScale: 1.3);
    expect(tester.takeException(), isNull);
  });

  group('the optimizing indicator', () {
    /// Pumps the app shell, whose builder hosts the indicator. The VACUUM is
    /// held open by [held] so the indicator can be caught mid-flight.
    Future<void> pumpApp(WidgetTester tester, {Completer<void>? held}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            appLocaleProvider
                .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
            setupDoneProvider.overrideWith(() => SetupDoneNotifier(true)),
            if (held != null)
              maintenanceRepositoryProvider.overrideWith(
                (ref) => _HeldVacuum(database.db, held),
              ),
          ],
          child: const SouqiApp(),
        ),
      );
      await settle(tester);
    }

    testWidgets('is hidden until a VACUUM runs, then goes away',
        (tester) async {
      final held = Completer<void>();
      await pumpApp(tester, held: held);
      expect(find.text('Optimizing…'), findsNothing);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(SouqiApp)),
      );
      final vacuum = container.read(housekeepingProvider.notifier).vacuum();
      await tester.pump();
      expect(find.text('Optimizing…'), findsOneWidget);

      held.complete();
      await vacuum;
      await tester.pump();
      expect(find.text('Optimizing…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the app does not run startup housekeeping in tests',
        (tester) async {
      await pumpApp(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SouqiApp)),
      );
      expect(container.read(housekeepingOnStartProvider), isFalse);
    });
  });
}

/// A maintenance repository whose VACUUM takes exactly as long as the test
/// wants it to.
class _HeldVacuum extends MaintenanceRepository {
  _HeldVacuum(super.db, this._held) : super(filePath: ':memory:');

  final Completer<void> _held;

  @override
  Future<void> vacuum() => _held.future;
}
