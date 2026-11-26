import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/reports/xlsx_writer.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/debt_report_repository.dart';
import 'package:souqi/data/repositories/debt_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/debt_report.dart';
import 'package:souqi/features/customers/customers_providers.dart';
import 'package:souqi/features/debts/report/daily_job.dart';
import 'package:souqi/features/debts/report/debt_report_pdf.dart';
import 'package:souqi/features/debts/report/debt_report_xlsx.dart';
import 'package:souqi/features/debts/report/report_providers.dart';
import 'package:souqi/features/debts/report/report_schedule.dart';
import 'package:souqi/features/debts/report/report_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../features/report_test_utils.dart';
import 'db_test_utils.dart';

/// The daily debt report: its figures against the ledger, the Excel
/// workbook's sheets and cell types, the PDF's pages, and the daily job —
/// file names, overwriting, keep-N, the fallback to Downloads, the status
/// and the notification.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late DebtRepository debts;
  late CustomerRepository customers;
  late DateTime now;

  setUp(() async {
    database = await openTestDb();
    debts = DebtRepository(database.db);
    customers = CustomerRepository(database.db);
    now = DateTime.now();
  });
  tearDown(() async => database.close());

  DateTime daysAgo(int days) => now.subtract(Duration(days: days));

  Future<DebtEntry> pay(int customer, int amount, DateTime at) =>
      debts.recordPayment(
        customerId: customer,
        amountMinor: amount,
        currencyCode: 'SYP',
        currencyDecimals: 0,
        baseCode: 'SYP',
        baseDecimals: 0,
        at: at,
      );

  /// A ledger with every kind of account:
  /// - Ahmad owes 60,000: an opening balance of 50,000 from 100 days ago
  ///   (due 70 days ago), a debt of 20,000 from 45 days ago, 10,000 paid
  ///   today — FIFO leaves 40,000 in "90+" and 20,000 in "31–60"; overdue.
  /// - Basel owes 7,000 from today, not due yet; a payment of 3,000 today
  ///   was reversed.
  /// - Camil is owed 5,000 (a credit balance).
  /// - Dana owed 1,000 ten days ago and paid it: a zero balance.
  /// - Eyad has no account at all.
  /// - Fadi owes 9,000 from an entry WRITTEN 200 days ago (not today's).
  late int ahmad, basel, camil, dana, eyad, fadi;
  late DebtEntry ahmadPayment, ahmadOpening, baselPayment;

  Future<void> seed() async {
    ahmad = await customers.insert(const Customer(
      name: 'Ahmad',
      phone: '0944 111 222',
      creditLimitBaseMinor: 100000,
    ));
    basel = await customers.insert(const Customer(name: 'Basel'));
    camil = await customers.insert(const Customer(name: 'Camil'));
    dana = await customers.insert(const Customer(name: 'Dana'));
    eyad = await customers.insert(const Customer(name: 'Eyad'));
    fadi = await customers.insert(const Customer(name: 'Fadi', phone: '011 22'));

    ahmadOpening = await debts.addOpeningBalance(
      customerId: ahmad,
      amountBaseMinor: 50000,
      at: daysAgo(100),
      dueAt: daysAgo(70),
    );
    await debts.addManualDebt(
      customerId: ahmad,
      amountBaseMinor: 20000,
      at: daysAgo(45),
      dueAt: daysAgo(15),
    );
    ahmadPayment = await pay(ahmad, 10000, now);

    await debts.addManualDebt(
      customerId: basel,
      amountBaseMinor: 7000,
      at: now,
      dueAt: now.add(const Duration(days: 30)),
    );
    baselPayment = await pay(basel, 3000, now);
    await debts.reverse(baselPayment.id, reason: 'wrong customer');

    await debts.addOpeningBalance(
      customerId: camil,
      amountBaseMinor: 5000,
      customerOwes: false,
    );

    await debts.addManualDebt(
      customerId: dana,
      amountBaseMinor: 1000,
      at: daysAgo(10),
    );
    await pay(dana, 1000, daysAgo(10));

    // Written long ago: dated AND recorded 200 days back.
    final old = daysAgo(200).toUtc().millisecondsSinceEpoch;
    await database.db.insert('debt_transactions', {
      'customer_id': fadi,
      'type': 'MANUAL_DEBT',
      'direction': 1,
      'amount_base_minor': 9000,
      'created_at': old,
      'recorded_at': old,
    });
  }

  group('the report data, against the ledger', () {
    test('summary: outstanding, debtors, overdue, aging, today', () async {
      await seed();
      final data = await DebtReportRepository(database.db).build(now: now);
      final s = data.summary;
      expect(s.totalOutstandingBaseMinor, 60000 + 7000 + 9000);
      expect(s.totalCreditBaseMinor, 5000);
      expect(s.debtorsCount, 3);
      expect(s.overdueCount, 1);
      expect(s.aging, const AgingSummary([7000, 20000, 0, 40000 + 9000]));
      // Ahmad's 10,000; Basel's 3,000 was reversed; Dana paid 10 days ago.
      expect(s.collectedTodayBaseMinor, 10000);
      // Basel's 7,000. Camil's opening balance is not new debt.
      expect(s.newDebtTodayBaseMinor, 7000);

      // It agrees with the debtors list and the statistics.
      final snapshot = await debts.debtors(now: now);
      expect(s.totalOutstandingBaseMinor, snapshot.totalOutstandingBaseMinor);
      expect(s.aging, snapshot.aging);
      final local = now.toLocal();
      final stats = await debts.stats(
        from: DateTime(local.year, local.month, local.day),
        to: DateTime(local.year, local.month, local.day + 1),
        now: now,
      );
      expect(s.collectedTodayBaseMinor, stats.collectedBaseMinor);
      expect(s.newDebtTodayBaseMinor, stats.newDebtBaseMinor);
    });

    test('debtors: who owes, biggest first, with the FIFO dates', () async {
      await seed();
      final data = await DebtReportRepository(database.db).build(now: now);
      expect([for (final d in data.debtors) d.name], ['Ahmad', 'Fadi', 'Basel']);
      final a = data.debtors.first;
      expect(a.balanceBaseMinor, 60000);
      expect(a.phone, '0944 111 222');
      expect(a.creditLimitBaseMinor, 100000);
      expect(a.oldestUnpaidAt, ahmadOpening.createdAt);
      expect(a.lastPaymentAt, ahmadPayment.createdAt);
      expect(a.overdue, isTrue);
      final b = data.debtors.last;
      expect(b.overdue, isFalse);
      // A reversed payment is no "last payment".
      expect(b.lastPaymentAt, isNull);
    });

    test("today's movements: written or dated today, in the order written",
        () async {
      await seed();
      final data = await DebtReportRepository(database.db).build(now: now);
      final moves = data.movements;
      // Everything seeded today — including Ahmad's opening balance dated
      // 100 days back but typed in today — and not Fadi's old entry.
      expect(moves, hasLength(9));
      expect(moves.where((m) => m.customerName == 'Fadi'), isEmpty);
      expect(
        moves.map((m) => m.entry.id).toList(),
        [...moves.map((m) => m.entry.id)]..sort(),
      );
      final reversed = moves.firstWhere((m) => m.entry.id == baselPayment.id);
      expect(reversed.entry.isReversed, isTrue);
      final reversal = moves.firstWhere((m) => m.entry.isReversal);
      expect(reversal.entry.reversedType, DebtEntryType.payment);
      expect(reversal.entry.reversedReceiptNo, baselPayment.receiptNo);
      expect(
        moves.firstWhere((m) => m.entry.id == ahmadPayment.id).entry.receiptNo,
        isNotNull,
      );
    });

    test('all balances: zero and credit ones too, by name', () async {
      await seed();
      final data = await DebtReportRepository(database.db).build(now: now);
      expect(
        [for (final b in data.balances) (b.name, b.balanceBaseMinor)],
        [
          ('Ahmad', 60000),
          ('Basel', 7000),
          ('Camil', -5000),
          ('Dana', 0),
          ('Fadi', 9000),
        ],
      );
      // Eyad has no account in the ledger.
      expect(data.balances.where((b) => b.name == 'Eyad'), isEmpty);
      expect(eyad, isPositive);
      expect(data.balances[3].lastPaymentAt, isNotNull);
    });

    test('language, shop and base currency come from the settings', () async {
      final settings = SettingsRepository(database.db);
      await settings.setMany({
        SettingsKeys.invoiceLanguage: 'en',
        SettingsKeys.shopName: '  Corner Shop ',
      });
      final data = await DebtReportRepository(database.db).build(now: now);
      expect(data.language, 'en');
      expect(data.rightToLeft, isFalse);
      expect(data.shopName, 'Corner Shop');
      expect(data.currency.code, 'SYP');
      expect(data.currency.decimals, 0);
      expect(data.debtors, isEmpty);
      expect(data.summary.totalOutstandingBaseMinor, 0);
    });
  });

  group('the Excel workbook', () {
    Map<String, String> unzip(List<int> bytes) => {
          for (final file in ZipDecoder().decodeBytes(bytes).files)
            if (file.isFile) file.name: utf8.decode(file.content as List<int>),
        };

    String cell(String sheet, String ref) {
      final match = RegExp('<c r="$ref"[^>]*>.*?</c>').firstMatch(sheet);
      return match?[0] ?? '';
    }

    for (final language in ['ar', 'en']) {
      test('[$language] four sheets, numeric cells, phones as text', () async {
        await seed();
        await SettingsRepository(database.db)
            .setString(SettingsKeys.invoiceLanguage, language);
        final data = await DebtReportRepository(database.db).build(now: now);
        final files = unzip(buildDebtReportXlsx(data));

        final names = debtReportSheetNames(language);
        expect(names, hasLength(4));
        expect(names.toSet(), hasLength(4));
        final workbook = files['xl/workbook.xml']!;
        for (final (i, name) in names.indexed) {
          expect(workbook, contains('<sheet name="${const HtmlEscape(HtmlEscapeMode.attribute).convert(name)}" sheetId="${i + 1}"'));
        }
        if (language == 'en') {
          expect(names, ['Summary', 'Debtors', "Today's movements", 'All balances']);
        } else {
          expect(names, ['الملخص', 'المدينون', 'حركات اليوم', 'كل الأرصدة']);
        }

        final summary = files['xl/worksheets/sheet1.xml']!;
        final debtorsSheet = files['xl/worksheets/sheet2.xml']!;
        final moves = files['xl/worksheets/sheet3.xml']!;
        final balances = files['xl/worksheets/sheet4.xml']!;
        for (final sheet in [summary, debtorsSheet, moves, balances]) {
          expect(sheet.contains('rightToLeft="1"'), language == 'ar');
          expect(sheet, contains('state="frozen"'));
          expect(sheet, contains('<cols>'));
        }

        // Summary: the totals are numbers in the money format.
        expect(cell(summary, 'B6'),
            '<c r="B6" s="${XlsxStyle.moneyBold.index}"><v>76000</v></c>');
        expect(cell(summary, 'B7'),
            '<c r="B7" s="${XlsxStyle.integerBold.index}"><v>3</v></c>');
        expect(cell(summary, 'B8'), contains('<v>1</v>'));
        expect(cell(summary, 'B9'), contains('<v>5000</v>'));
        expect(cell(summary, 'B12'), contains('<v>7000</v>'));
        expect(cell(summary, 'B13'), contains('<v>20000</v>'));
        expect(cell(summary, 'B14'), contains('<v>0</v>'));
        expect(cell(summary, 'B15'), contains('<v>49000</v>'));
        expect(cell(summary, 'B17'), contains('<v>10000</v>'));
        expect(cell(summary, 'B18'), contains('<v>7000</v>'));
        // The generation time is a date cell.
        expect(cell(summary, 'B2'), contains('s="${XlsxStyle.dateTime.index}"'));

        // Debtors: name and phone are text, balance and limit numbers,
        // dates are dates, overdue in words.
        expect(cell(debtorsSheet, 'A2'), contains('t="inlineStr"'));
        expect(cell(debtorsSheet, 'B2'), contains('>0944 111 222<'));
        expect(cell(debtorsSheet, 'C2'),
            '<c r="C2" s="${XlsxStyle.money.index}"><v>60000</v></c>');
        expect(cell(debtorsSheet, 'D2'), contains('<v>100000</v>'));
        expect(cell(debtorsSheet, 'E2'), contains('s="${XlsxStyle.date.index}"'));
        expect(cell(debtorsSheet, 'G2'),
            contains(language == 'en' ? '>Yes<' : '>نعم<'));
        expect(RegExp('<row ').allMatches(debtorsSheet), hasLength(4));

        // Today's movements: the header and nine entries; amounts numeric.
        expect(RegExp('<row ').allMatches(moves), hasLength(10));
        expect(moves, contains('s="${XlsxStyle.money.index}"><v>10000</v>'));

        // All balances, a credit as a negative number, zero as zero.
        expect(RegExp('<row ').allMatches(balances), hasLength(6));
        expect(cell(balances, 'C4'), contains('<v>-5000</v>'));
        expect(cell(balances, 'C5'), contains('<v>0</v>'));
      });
    }
  });

  group('the PDF', () {
    DebtReportData many(int count, String language) => DebtReportData(
          generatedAt: DateTime(2026, 11, 26, 22, 1),
          shopName: 'بقالة الحي',
          language: language,
          currency: const ReportCurrency(code: 'SYP', symbol: 'ل.س', decimals: 0),
          summary: DebtReportSummary(
            totalOutstandingBaseMinor: count * 123456,
            totalCreditBaseMinor: 0,
            debtorsCount: count,
            overdueCount: count ~/ 3,
            aging: const AgingSummary([1, 2, 3, 4]),
            collectedTodayBaseMinor: 5000,
            newDebtTodayBaseMinor: 7000,
          ),
          debtors: [
            for (var i = 0; i < count; i++)
              DebtReportDebtor(
                name: i.isEven ? 'عبد الرحمن محمد $i' : 'Customer number $i',
                phone: '0944 ${i.toString().padLeft(6, '0')}',
                balanceBaseMinor: 987654321 - i,
                oldestUnpaidAt: DateTime(2026, 1, 1 + i % 28),
                lastPaymentAt: i % 5 == 0 ? null : DateTime(2026, 11, 1),
                overdue: i % 3 == 0,
              ),
          ],
          movements: const [],
          balances: const [],
        );

    for (final language in ['ar', 'en']) {
      test('[$language] 500 debtors: A4 portrait, paginated', () async {
        final fonts = await testReportFonts();
        final doc = await buildDebtReportDocument(many(500, language), fonts: fonts);
        final pages = doc.document.pdfPageList.pages;
        // About 40 rows a page: the table runs on, it is not cut.
        expect(pages.length, inInclusiveRange(10, 20));
        for (final page in pages) {
          expect(page.pageFormat.width, closeTo(595.28, 0.5));
          expect(page.pageFormat.height, closeTo(841.89, 0.5));
        }
        final bytes = await doc.save();
        expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

        // One page for none; more debtors, more pages.
        final none = await buildDebtReportDocument(many(0, language), fonts: fonts);
        expect(none.document.pdfPageList.pages, hasLength(1));
        final more = await buildDebtReportDocument(many(1000, language), fonts: fonts);
        expect(
          more.document.pdfPageList.pages.length,
          greaterThan(pages.length),
        );
      });
    }
  });

  group('the daily job', () {
    late FakeReportPlatform platform;
    late Directory staging;

    setUp(() async {
      platform = FakeReportPlatform();
      staging = await Directory.systemTemp.createTemp('souqi-report-');
    });
    tearDown(() async {
      if (await staging.exists()) await staging.delete(recursive: true);
    });

    DailyReportJob job({bool featureOn = true}) => DailyReportJob(
          db: database.db,
          platform: platform,
          stagingDir: () async => staging,
          loadFonts: testReportFonts,
          featureOn: featureOn,
        );

    Future<void> configure(DebtReportSettings settings) =>
        SettingsRepository(database.db).setMany(settings.toMap());

    const folder = 'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3AReports';
    final today = DateTime.now();
    String name(String extension, [DateTime? day]) =>
        debtReportFiles.nameFor(day ?? today, extension);

    test('writes souqi-debts-<today>.xlsx and .pdf to the chosen folder',
        () async {
      await seed();
      await configure(const DebtReportSettings(enabled: true, folderUri: folder));
      final result = await job().run(ReportTrigger.scheduled);

      expect(result.outcome, ReportOutcome.ok);
      expect(platform.folder(folder).keys.toSet(), {name('xlsx'), name('pdf')});
      expect(platform.folder(null), isEmpty);
      expect(platform.locked, isFalse, reason: 'the lock is given back');

      final status = DebtReportStatus.fromJson(platform.status);
      expect(status.outcome, ReportOutcome.ok);
      expect(status.lastSuccessAt, isNotNull);
      expect(status.savedToFolderUri, folder);
      expect(status.debtors, 3);
      expect(status.outstandingBaseMinor, 76000);
      // The app's own copies, for "Share".
      expect(status.files, hasLength(2));
      for (final path in status.files) {
        expect(File(path).existsSync(), isTrue);
      }

      expect(platform.notices, hasLength(1));
      final notice = platform.notices.single;
      expect(notice.shareLabel, isNotNull);
      expect(notice.openFolderLabel, isNotNull);
      // App language Arabic by default: "3 مدينين، 76,000 ل.س مستحقة".
      expect(notice.text, contains('76,000'));
      expect(notice.text, contains('3'));
    });

    test('in English: "3 debtors, 76,000 SYP outstanding"', () async {
      await seed();
      await SettingsRepository(database.db)
          .setString(SettingsKeys.appLanguage, 'en');
      await database.db.update('currencies', {'symbol': ''},
          where: 'code = ?', whereArgs: ['SYP']);
      await configure(const DebtReportSettings(enabled: true));
      await job().run(ReportTrigger.scheduled);
      expect(platform.notices.single.title, 'Debt report ready');
      expect(platform.notices.single.text, '3 debtors, 76,000 SYP outstanding');
    });

    test('running again the same day overwrites that day\'s files', () async {
      await seed();
      await configure(const DebtReportSettings(enabled: true, folderUri: folder));
      await job().run(ReportTrigger.scheduled);
      final first = platform.folder(folder)[name('xlsx')]!;
      await debts.addManualDebt(customerId: basel, amountBaseMinor: 1);
      await job().run(ReportTrigger.manual);
      expect(platform.folder(folder).keys.toSet(), {name('xlsx'), name('pdf')});
      expect(platform.folder(folder)[name('xlsx')], isNot(equals(first)));
      // Only the newest set stays in the app's own folder.
      expect(staging.listSync().whereType<File>(), hasLength(2));
    });

    test('only the chosen formats', () async {
      await configure(const DebtReportSettings(
        enabled: true,
        formats: {ReportFormat.pdf},
      ));
      await job().run(ReportTrigger.scheduled);
      expect(platform.folder(null).keys, [name('pdf')]);
    });

    test('keep-N: the newest 30 days stay, other files are left alone',
        () async {
      final mine = platform.folder(folder);
      for (var day = 1; day <= 40; day++) {
        final at = today.subtract(Duration(days: day));
        mine[name('xlsx', at)] = Uint8List(1);
        mine[name('pdf', at)] = Uint8List(1);
      }
      mine['shop photos.jpg'] = Uint8List(1);
      mine['souqi-backup-2020-01-01.souqibak'] = Uint8List(1);
      await configure(const DebtReportSettings(
        enabled: true,
        folderUri: folder,
        keepDays: 30,
      ));
      await job().run(ReportTrigger.scheduled);

      final days = {
        for (final file in mine.keys)
          ?debtReportFiles.dayKeyOf(file),
      };
      expect(days, hasLength(30));
      expect(mine, contains(name('xlsx')));
      expect(mine, contains(name('pdf', today.subtract(const Duration(days: 29)))));
      expect(mine, isNot(contains(name('pdf', today.subtract(const Duration(days: 30))))));
      expect(mine, contains('shop photos.jpg'));
      expect(mine, contains('souqi-backup-2020-01-01.souqibak'));
    });

    test('folder not available: saved to Downloads, said so, notified',
        () async {
      await seed();
      platform.folderOk = false;
      // Even with "Notify me" off: this is exactly when the shop must know.
      await configure(const DebtReportSettings(
        enabled: true,
        folderUri: folder,
        notify: false,
      ));
      final result = await job().run(ReportTrigger.scheduled);

      expect(result.outcome, ReportOutcome.fallback);
      expect(result.problem, ReportProblem.folderUnavailable);
      expect(result.location, FakeReportPlatform.downloadsLabel);
      expect(platform.folder(folder), isEmpty);
      expect(platform.folder(null).keys.toSet(), {name('xlsx'), name('pdf')});
      final status = DebtReportStatus.fromJson(platform.status);
      expect(status.outcome, ReportOutcome.fallback);
      expect(status.lastSuccessAt, isNotNull, reason: 'the data is saved');
      expect(status.savedToFolderUri, isNull);
      expect(platform.notices.single.text, contains(FakeReportPlatform.downloadsLabel));
    });

    test('the folder fails half-way (full): the set goes to Downloads',
        () async {
      platform.folderWritesFail = true;
      await configure(const DebtReportSettings(enabled: true, folderUri: folder));
      final result = await job().run(ReportTrigger.scheduled);
      expect(result.outcome, ReportOutcome.fallback);
      expect(result.problem, ReportProblem.writeFailed);
      expect(platform.folder(null), hasLength(2));
    });

    test('nowhere to write: failed, the last good report is kept', () async {
      await configure(const DebtReportSettings(enabled: true, folderUri: folder));
      await job().run(ReportTrigger.scheduled);
      final good = DebtReportStatus.fromJson(platform.status);

      platform
        ..folderOk = false
        ..downloadsFail = true;
      final result = await job().run(ReportTrigger.manual);
      expect(result.outcome, ReportOutcome.failed);
      final status = DebtReportStatus.fromJson(platform.status);
      expect(status.outcome, ReportOutcome.failed);
      expect(status.problem, ReportProblem.writeFailed);
      expect(status.lastAttemptAt, isNotNull);
      expect(status.lastSuccessAt, good.lastSuccessAt);
      expect(status.files, good.files);
      expect(platform.notices.last.shareLabel, isNull);
    });

    test('app start: re-plans, catches up a missed report once, and drops '
        'the plan when off', () async {
      // Due at midnight: today's has passed, and none was made.
      await configure(DebtReportSettings(
        enabled: true,
        minuteOfDay: 0,
        enabledAt: DateTime.now().subtract(const Duration(days: 3)),
      ));
      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(database),
        reportPlatformProvider.overrideWithValue(platform),
        reportStagingDirProvider.overrideWithValue(() async => staging),
        reportFontsProvider.overrideWithValue(testReportFonts),
        clockProvider.overrideWithValue(DateTime.now),
      ]);
      addTearDown(container.dispose);

      await debtReportOnAppStart(container);
      expect(platform.schedules.single, (minute: 0, replace: false));
      expect(platform.folder(null), hasLength(2));
      expect(DebtReportStatus.fromJson(platform.status).outcome, ReportOutcome.ok);

      // The next start: the report is there, nothing more is made.
      platform.folders.clear();
      await debtReportOnAppStart(container);
      expect(platform.folder(null), isEmpty);
      expect(platform.schedules, hasLength(2));

      // Off: a plan left behind is cancelled, nothing is made.
      await configure(const DebtReportSettings(enabled: false));
      container.invalidate(debtReportSettingsProvider);
      platform.status = null;
      await debtReportOnAppStart(container);
      expect(platform.cancels, 1);
      expect(platform.folder(null), isEmpty);
    });

    test('one run at a time; nothing when off', () async {
      await configure(const DebtReportSettings(enabled: true));
      platform.locked = true;
      expect((await job().run(ReportTrigger.manual)).busy, isTrue);
      expect(platform.folder(null), isEmpty);
      platform.locked = false;

      expect((await job(featureOn: false).run(ReportTrigger.manual)).skipped,
          isTrue);

      await configure(const DebtReportSettings(enabled: false));
      expect((await job().run(ReportTrigger.scheduled)).skipped, isTrue);
      expect((await job().run(ReportTrigger.catchUp)).skipped, isTrue);
      // "Create report now" works with the daily report off.
      expect((await job().run(ReportTrigger.manual)).outcome, ReportOutcome.ok);
    });

    test('"Notify me" off: a good run posts nothing', () async {
      await configure(const DebtReportSettings(enabled: true, notify: false));
      expect((await job().run(ReportTrigger.scheduled)).outcome, ReportOutcome.ok);
      expect(platform.notices, isEmpty);
    });

    test('an extra output (phase 5) shares the folder, keeps its own N',
        () async {
      final mine = platform.folder(folder);
      for (var day = 1; day <= 5; day++) {
        mine[backupFiles.nameFor(today.subtract(Duration(days: day)), 'souqibak')] =
            Uint8List(1);
      }
      await configure(const DebtReportSettings(
        enabled: true,
        folderUri: folder,
        keepDays: 30,
      ));
      final withBackup = DailyReportJob(
        db: database.db,
        platform: platform,
        stagingDir: () async => staging,
        loadFonts: testReportFonts,
        featureOn: true,
        outputsFor: (settings, {required loadFonts}) => [
          ...dailyOutputs(settings, loadFonts: loadFonts),
          _FakeBackupOutput(),
        ],
      );
      final result = await withBackup.run(ReportTrigger.scheduled);
      expect(result.outcome, ReportOutcome.ok);
      expect(mine, contains(name('xlsx')));
      expect(mine, contains(backupFiles.nameFor(today, 'souqibak')));
      // The backup keeps 3 days; the report's 30 are its own business.
      expect(
        mine.keys.where(backupFiles.matches),
        hasLength(3),
      );
      expect(DebtReportStatus.fromJson(platform.status).files, hasLength(3));
    });
  });
}

const backupFiles = DatedFilePattern(
  prefix: 'souqi-backup',
  extensions: ['souqibak'],
);

/// What phase 5's encrypted backup will look like to the job.
class _FakeBackupOutput implements DailyOutput {
  @override
  String get id => 'backup';

  @override
  DatedFilePattern get files => backupFiles;

  @override
  int get keepDays => 3;

  @override
  Future<List<StagedFile>> build(DailyJobContext context) async {
    final name = files.nameFor(context.now, 'souqibak');
    final file = File('${context.stagingDir.path}/$name');
    await file.writeAsBytes([1, 2, 3]);
    return [StagedFile(name: name, path: file.path, mimeType: 'application/octet-stream')];
  }
}
