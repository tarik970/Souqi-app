import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/app.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/archive_repository.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/invoice/invoice_actions.dart';
import 'package:souqi/features/invoice/invoice_preview.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// The archive, its detail screen and the statistics screen all read from the
/// database, so their futures only progress inside [WidgetTester.runAsync] —
/// see [settle].
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late FakeNativeBridge bridge;

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
  });
  tearDown(() async => database.close());

  Future<void> settle(WidgetTester tester, [int rounds = 14]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Seeds rows: the sqflite futures only run inside runAsync.
  Future<void> seed(WidgetTester tester, Future<void> Function() action) =>
      tester.runAsync(action);

  /// Long enough for a menu, dialog or sheet to finish animating in.
  Future<void> animated(WidgetTester tester) async {
    await settle(tester, 28);
    for (var i = 0; i < 20 && tester.binding.transientCallbackCount > 0; i++) {
      await settle(tester, 4);
    }
  }

  /// Local midnight today. Every seeded timestamp hangs off this, so the
  /// tests do not change meaning when they happen to run just after midnight.
  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<void> pump(WidgetTester tester, Widget home) async {
    // Tall: the archive, the invoice preview and the statistics cards are
    // all long scrolling pages.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider
              .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
          nativeBridgeProvider.overrideWithValue(bridge),
        ],
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

  /// Three sales: sugar today, tea today, rice a year ago.
  Future<void> seedSales(AppDatabase database) async {
    final sugar = await insertInvoice(
      database.db,
      invoiceNo: 1,
      createdAt: today().add(const Duration(hours: 9)),
      subtotalMinor: 5000,
      customerName: 'أحمد العلي',
      customerPhone: '0944123456',
    );
    await insertInvoiceItem(database.db,
        invoiceId: sugar, name: 'السكر الناعم', unitPriceMinor: 5000);
    final tea = await insertInvoice(
      database.db,
      invoiceNo: 2,
      createdAt: today().add(const Duration(hours: 10)),
      subtotalMinor: 3000,
    );
    await insertInvoiceItem(database.db,
        invoiceId: tea, name: 'شاي أخضر', unitPriceMinor: 3000);
    final rice = await insertInvoice(
      database.db,
      invoiceNo: 3,
      createdAt: today().subtract(const Duration(days: 365)),
      subtotalMinor: 1000,
    );
    await insertInvoiceItem(database.db, invoiceId: rice, name: 'Rice');
  }

  group('the archive list', () {
    testWidgets('shows the invoices newest first with their totals',
        (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      expect(find.byKey(const ValueKey('archive-invoice-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      expect(find.textContaining('5,000'), findsOneWidget);
      expect(find.text('Items: 1'), findsNothing,
          reason: 'the count is part of the subtitle line');
      expect(find.textContaining('Items: 1'), findsWidgets);

      // Newest first: invoice 3 is a year old and sits last.
      final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
      expect(tiles, hasLength(3));
    });

    testWidgets('an empty archive says so', (tester) async {
      await pump(tester, const ArchiveScreen());
      expect(find.text('No invoices yet'), findsOneWidget);
    });

    testWidgets('the match summary counts and totals what is shown',
        (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());
      expect(
        find.byKey(const ValueKey('archive-match-summary')),
        findsOneWidget,
      );
      expect(find.textContaining('3 invoices'), findsOneWidget);
    });
  });

  group('filters', () {
    testWidgets('today drops the invoice from a year ago', (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());
      expect(find.byType(ListTile), findsNWidgets(3));

      await tester.tap(find.byKey(const ValueKey('archive-period-today')));
      await settle(tester);

      expect(find.byKey(const ValueKey('archive-invoice-3')), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(2));
    });

    testWidgets('a product search matches the Arabic name as typed',
        (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      // "سكر" without the leading "ال" still finds "السكر الناعم".
      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        'سكر',
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-invoice-2')), findsNothing);
    });

    testWidgets('a customer search matches the phone snapshot',
        (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.tap(find.byKey(const ValueKey('archive-search-target')));
      await animated(tester);
      // Tap the menu item, not its label: the item's ListTile ignores
      // pointers, so a tap aimed at the Text "misses" (the hit lands on the
      // item around it). Fatal here, so a real miss fails the test.
      final customerItem = find.ancestor(
        of: find.text('Customer, phone or card number'),
        matching: find.byWidgetPredicate((w) => w is CheckedPopupMenuItem),
      );
      await tester.ensureVisible(customerItem);
      await animated(tester);
      final wasFatal = WidgetController.hitTestWarningShouldBeFatal;
      WidgetController.hitTestWarningShouldBeFatal = true;
      try {
        await tester.tap(customerItem);
      } finally {
        WidgetController.hitTestWarningShouldBeFatal = wasFatal;
      }
      await animated(tester);

      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        '0944',
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('archive-invoice-1')), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(1));
    });

    testWidgets('a search with no match says so', (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());
      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        'zzzz',
      );
      await settle(tester);
      expect(find.text('No invoice matches these filters'), findsOneWidget);
    });
  });

  group('paging', () {
    testWidgets('scrolling to the bottom loads the next page', (tester) async {
      await seed(tester, () async {
        for (var i = 1; i <= 45; i++) {
          await insertInvoice(
            database.db,
            invoiceNo: i,
            createdAt: DateTime(2026, 11, 1).add(Duration(minutes: i)),
          );
        }
      });
      await pump(tester, const ArchiveScreen());

      // The first page only: 30 rows, newest first.
      expect(find.byKey(const ValueKey('archive-invoice-45')), findsOneWidget);
      expect(find.byKey(const ValueKey('archive-invoice-1')), findsNothing);

      // Dragged by hand rather than with scrollUntilVisible: the next page
      // comes out of the database, and only [settle] lets that future run.
      final oldest = find.byKey(const ValueKey('archive-invoice-1'));
      for (var i = 0; i < 25 && oldest.evaluate().isEmpty; i++) {
        await tester.drag(
          find.byKey(const ValueKey('archive-list')),
          const Offset(0, -1500),
        );
        await settle(tester);
      }

      expect(oldest, findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('the range confirmation states the exact count and total',
        (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester);

      expect(
        find.byKey(const ValueKey('archive-delete-range-dialog')),
        findsOneWidget,
      );
      // 5,000 + 3,000 + 1,000 in the base currency.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('archive-delete-range-dialog')),
          matching: find.textContaining('3 invoices totalling 9,000'),
        ),
        findsOneWidget,
      );
      // No date range: the warning that this is the whole archive.
      expect(
        find.textContaining('EVERY invoice in the archive'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);
      expect(find.byType(ListTile), findsNWidgets(3));
    });

    testWidgets('confirming deletes only the chosen period', (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.tap(find.byKey(const ValueKey('archive-period-today')));
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester);
      expect(find.textContaining('2 invoices totalling'), findsOneWidget);
      // A date range is set, so no whole-archive warning.
      expect(find.textContaining('EVERY invoice'), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester);

      final left = await db(
        tester,
        () => database.db.query('invoices', columns: ['invoice_no']),
      );
      expect(left.map((r) => r['invoice_no']), [3]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a range with nothing in it cannot be confirmed',
        (tester) async {
      await pump(tester, const ArchiveScreen());
      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester);

      expect(
        find.text('There are no invoices in this range.'),
        findsOneWidget,
      );
      // Delete is dead: there is nothing to delete.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('the confirmation opens on the same frame, counting inside it',
        (tester) async {
      // The bug: the count ran BEFORE the dialog, so a big archive left the
      // app looking frozen for seconds and invited a second tap.
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);

      await tester.tap(find.text('Delete these invoices'));
      // Two plain frames and NO runAsync: nothing the database answers can
      // have resolved yet. If the count were awaited before the dialog, as
      // it used to be, the dialog would simply not be here.
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('archive-delete-range-dialog')),
        findsOneWidget,
      );
      await settle(tester);
      expect(find.textContaining('3 invoices totalling'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('Delete is dead while the count is still being made',
        (tester) async {
      // The aggregate never answers, which is what a cold open of a big
      // archive looks like for its first moments.
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(database),
            appLocaleProvider
                .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
            archiveRepositoryProvider.overrideWith(
              (ref) => _NeverCounts(database.db),
            ),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ArchiveScreen(),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester);

      expect(find.text('Counting…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete'))
            .onPressed,
        isNull,
        reason: 'nobody confirms a deletion whose size they were not told',
      );
    });

    testWidgets('is not offered at all while a search is narrowing the list',
        (tester) async {
      // Deleting means a PERIOD. A search that quietly narrowed it would be
      // a nasty surprise, so the action is withdrawn until the search is
      // cleared — and it says so.
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        'سكر',
      );
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);

      expect(
        tester
            .widget<PopupMenuItem<void>>(
              find.byKey(const ValueKey('archive-delete-range')),
            )
            .enabled,
        isFalse,
      );
      expect(find.text('Clear the search to delete a period'), findsOneWidget);

      // Tapping it does nothing at all.
      await tester.tap(find.text('Delete these invoices'), warnIfMissed: false);
      await settle(tester);
      expect(
        find.byKey(const ValueKey('archive-delete-range-dialog')),
        findsNothing,
      );
    });

    testWidgets('comes back once the search is cleared', (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.enterText(
        find.byKey(const ValueKey('archive-search')),
        'سكر',
      );
      await settle(tester);
      await tester.enterText(find.byKey(const ValueKey('archive-search')), '');
      await settle(tester);

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      expect(
        tester
            .widget<PopupMenuItem<void>>(
              find.byKey(const ValueKey('archive-delete-range')),
            )
            .enabled,
        isTrue,
      );
      expect(find.text('Clear the search to delete a period'), findsNothing);
    });

    testWidgets('a big delete shows progress and clears the whole range',
        (tester) async {
      // Past one chunk boundary, so the loop really comes round again.
      const count = ArchiveRepository.deleteChunkSize + 40;
      await seed(tester, () async {
        final batch = database.db.batch();
        for (var i = 1; i <= count; i++) {
          batch.insert('invoices', {
            'invoice_no': i,
            'created_at':
                today().add(Duration(hours: 9, seconds: i)).millisecondsSinceEpoch,
            'currency_code': 'SYP',
            'base_currency_code': 'SYP',
            'rate_num': 1,
            'rate_den': 1,
            'subtotal_minor': 1000,
            'total_minor': 1000,
            'total_base_minor': 1000,
          });
        }
        await batch.commit(noResult: true);
      });
      await pump(tester, const ArchiveScreen());

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();

      // The progress dialog is up straight away, and it blocks the back
      // button while it is.
      expect(
        find.byKey(const ValueKey('archive-deleting-dialog')),
        findsOneWidget,
      );
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await settle(tester, 40);

      // It closed itself, the list refreshed, and the archive is empty.
      expect(
        find.byKey(const ValueKey('archive-deleting-dialog')),
        findsNothing,
      );
      expect(find.text('No invoices yet'), findsOneWidget);
      final left = await db(
        tester,
        () => database.db.rawQuery('SELECT COUNT(*) AS n FROM invoices'),
      );
      expect(left.first['n'], 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('one final message, not one per chunk', (tester) async {
      await seed(tester, () => seedSales(database));
      await pump(tester, const ArchiveScreen());

      await tester.tap(find.byType(PopupMenuButton<void>));
      await settle(tester);
      await tester.tap(find.text('Delete these invoices'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settle(tester, 40);

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('3 invoices deleted'), findsOneWidget);
    });
  });

  group('the invoice detail screen', () {
    /// English invoice language, so the copy mark reads "COPY".
    Future<int> seedOne(AppDatabase database) async {
      await database.db.insert(
        'settings',
        {'key': 'invoice_language', 'value': 'en', 'updated_at': 0},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final id = await insertInvoice(
        database.db,
        invoiceNo: 12,
        subtotalMinor: 5000,
        customerName: 'Ahmad',
      );
      await insertInvoiceItem(database.db,
          invoiceId: id, name: 'Sugar', unitPriceMinor: 5000);
      return id;
    }

    testWidgets('marks the invoice as a COPY, on screen and on the output',
        (tester) async {
      final id = await db(tester, () => seedOne(database));
      await pump(tester, InvoiceDetailScreen(invoiceId: id));

      expect(find.byKey(const ValueKey('archive-invoice-total')), findsOneWidget);
      // Said in words above the buttons…
      expect(
        find.text('Anything printed or shared from here is marked as a copy.'),
        findsOneWidget,
      );
      // …and printed on the receipt itself.
      expect(find.text('COPY'), findsOneWidget);

      final preview = tester.widget<InvoicePaperPreview>(
        find.byKey(const ValueKey('archive-invoice-view')),
      );
      expect(preview.isCopy, isTrue);
      final actions =
          tester.widget<InvoiceActions>(find.byType(InvoiceActions));
      expect(actions.copy, isTrue,
          reason: 'every reprint and re-share carries the mark');
    });

    testWidgets('deleting from the detail screen goes back to the archive',
        (tester) async {
      final id = await db(tester, () => seedOne(database));
      await pump(tester, const ArchiveScreen());
      await tester.tap(find.byKey(const ValueKey('archive-invoice-12')));
      await animated(tester);

      await tester.tap(find.byKey(const ValueKey('archive-delete-invoice')));
      await settle(tester);
      expect(find.byKey(const ValueKey('delete-invoice-dialog')), findsOneWidget);
      expect(find.textContaining('Invoice 12 will be deleted'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await animated(tester);
      await animated(tester);

      expect(find.byType(InvoiceDetailScreen), findsNothing);
      expect(find.text('No invoices yet'), findsOneWidget);
      final left = await db(
        tester,
        () => database.db.query('invoices', where: 'id = ?', whereArgs: [id]),
      );
      expect(left, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an invoice deleted meanwhile says so', (tester) async {
      await pump(tester, const InvoiceDetailScreen(invoiceId: 404));
      expect(
        find.text('This invoice is no longer in the archive.'),
        findsOneWidget,
      );
    });
  });

  group('the statistics screen', () {
    testWidgets('shows the four figures for the period', (tester) async {
      await seed(tester, () async {
        await insertInvoice(
          database.db,
          invoiceNo: 1,
          createdAt: today().add(const Duration(hours: 9)),
          subtotalMinor: 10000,
          discountMinor: 1000,
        );
        await insertInvoice(
          database.db,
          invoiceNo: 2,
          createdAt: today().add(const Duration(hours: 10)),
          subtotalMinor: 5000,
        );
        // Yesterday, so the comparison has something to compare with.
        await insertInvoice(
          database.db,
          invoiceNo: 3,
          createdAt:
              today().subtract(const Duration(days: 1)).add(const Duration(hours: 9)),
          subtotalMinor: 7000,
        );
      });
      await pump(tester, const StatsScreen());

      expect(find.text('Total sales'), findsOneWidget);
      expect(find.text('Invoices'), findsOneWidget);
      expect(find.text('Average invoice'), findsOneWidget);
      expect(find.text('Discounts'), findsOneWidget);

      // 10,000 - 1,000 + 5,000 = 14,000 today.
      final total = tester.widget<Text>(
        find.byKey(const ValueKey('stats-total-value')),
      );
      expect(total.data, contains('14,000'));
      final count = tester.widget<Text>(
        find.byKey(const ValueKey('stats-count-value')),
      );
      expect(count.data, '2');
      final average = tester.widget<Text>(
        find.byKey(const ValueKey('stats-average-value')),
      );
      expect(average.data, contains('7,000'));
    });

    testWidgets('the comparison is in words, not colour alone',
        (tester) async {
      await seed(tester, () async {
        await insertInvoice(
          database.db,
          invoiceNo: 1,
          createdAt: today().add(const Duration(hours: 9)),
          subtotalMinor: 14000,
        );
        await insertInvoice(
          database.db,
          invoiceNo: 2,
          createdAt:
              today().subtract(const Duration(days: 1)).add(const Duration(hours: 9)),
          subtotalMinor: 7000,
        );
      });
      await pump(tester, const StatsScreen());

      final trend = tester.widget<Text>(
        find.byKey(const ValueKey('stats-total-trend')),
      );
      // Doubled: "Up 100.0% · Previous period: 7,000".
      expect(trend.data, contains('Up 100.0%'));
      expect(trend.data, contains('7,000'));
      expect(find.byIcon(Icons.arrow_upward), findsWidgets);
    });

    testWidgets('an empty period says so instead of showing empty tables',
        (tester) async {
      await pump(tester, const StatsScreen());
      expect(find.text('No sales in this period'), findsOneWidget);
      expect(find.byKey(const ValueKey('stats-top-sales')), findsNothing);
    });

    testWidgets('the top tables group an unsaved item by its name',
        (tester) async {
      await seed(tester, () async {
        for (var i = 1; i <= 3; i++) {
          final id = await insertInvoice(
            database.db,
            invoiceNo: i,
            createdAt: today().add(Duration(hours: 9, minutes: i)),
          );
          await insertInvoiceItem(
            database.db,
            invoiceId: id,
            productId: null,
            name: i == 2 ? 'السكر' : 'سكر',
            unitPriceMinor: 1000,
          );
        }
      });
      await pump(tester, const StatsScreen());

      expect(find.byKey(const ValueKey('stats-top-sales')), findsOneWidget);
      expect(find.text('3 sales'), findsOneWidget);
      expect(find.text('not a product'), findsWidgets);
    });
  });
}

/// An archive whose counting never comes back, for the "Delete is dead while
/// the count is still being made" case.
class _NeverCounts extends ArchiveRepository {
  _NeverCounts(super.db);

  @override
  Future<ArchiveRangeSummary> summary(ArchiveFilter filter) =>
      Completer<ArchiveRangeSummary>().future;
}
