import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/core/platform/report_platform.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/features/customers/customers_providers.dart';
import 'package:souqi/features/debts/report/debt_report_settings_screen.dart';
import 'package:souqi/features/debts/report/report_launch.dart';
import 'package:souqi/features/debts/report/report_providers.dart';
import 'package:souqi/features/debts/report/report_settings.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';
import 'report_test_utils.dart';

/// Settings → Debts → "Daily debt report": the PIN in front of turning it
/// on and of changing the folder (both logged), what the page says about
/// the last run, "Create report now", the notification's actions, and the
/// page on a 360×640 phone at font scale 1.3.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });

  late AppDatabase database;
  late FakeNativeBridge bridge;
  late FakeReportPlatform platform;
  late Directory staging;

  /// 26 November 2026, 23:00 local time.
  final now = DateTime(2026, 11, 26, 23);
  const folderUri =
      'content://com.android.externalstorage.documents/tree/1A2B-3C4D%3AReports';

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
    platform = FakeReportPlatform();
    staging = await Directory.systemTemp.createTemp('souqi-report-ui-');
  });
  tearDown(() async {
    await database.close();
    if (staging.existsSync()) await staging.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  Future<void> animated(WidgetTester tester) async {
    await settle(tester, 28);
    for (var i = 0; i < 20 && tester.binding.transientCallbackCount > 0; i++) {
      await settle(tester, 4);
    }
  }

  Future<void> until(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 1500 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(done(), isTrue, reason: 'timed out waiting');
    await settle(tester, 3);
  }

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<void> setPin(WidgetTester tester) => db(tester, () async {
        await PinRepository(SettingsRepository(database.db)).set('2580');
        return true;
      });

  Future<void> store(WidgetTester tester, DebtReportSettings settings) =>
      db(tester, () async {
        await SettingsRepository(database.db).setMany(settings.toMap());
        return true;
      });

  Future<DebtReportSettings> stored(WidgetTester tester) => db(
        tester,
        () async => DebtReportSettings.fromMap(
          await SettingsRepository(database.db).getAll(),
        ),
      );

  Future<List<String>> audit(WidgetTester tester) => db(tester, () async {
        final rows = await database.db.query('audit_log', orderBy: 'id');
        return [for (final row in rows) row['action'] as String];
      });

  List<Override> overrides(String locale) => [
        databaseProvider.overrideWithValue(database),
        appLocaleProvider.overrideWith(() => AppLocaleNotifier(Locale(locale))),
        // The fake phone UNDER the app's doorway: the announcements to the
        // PIN locks are real.
        platformBridgeProvider.overrideWithValue(bridge),
        reportPlatformProvider.overrideWithValue(platform),
        reportStagingDirProvider.overrideWithValue(() async => staging),
        reportFontsProvider.overrideWithValue(testReportFonts),
        clockProvider.overrideWithValue(() => now),
      ];

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    String locale = 'en',
    Size size = const Size(600, 1300),
    double textScale = 1,
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides(locale),
        child: MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await settle(tester, 20);
  }

  /// Scrolls the page until [finder] is built, then onto the screen.
  Future<void> reach(WidgetTester tester, Finder finder) async {
    final list = find.byKey(const ValueKey('debt-report-settings'));
    for (final step in const [-200.0, 200.0]) {
      for (var i = 0; i < 30 && finder.evaluate().isEmpty; i++) {
        await tester.drag(list, Offset(0, step), warnIfMissed: false);
        await settle(tester, 2);
      }
    }
    await tester.ensureVisible(finder.first);
    await settle(tester, 4);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await reach(tester, finder);
    await tester.tap(finder);
    await animated(tester);
  }

  Future<void> enterPin(WidgetTester tester, [String pin = '2580']) async {
    await tester.enterText(find.byKey(const ValueKey('pin-entry-field')), pin);
    await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
    await animated(tester);
  }

  final enabledSwitch = find.byKey(const ValueKey('debt-report-enabled'));

  group('PIN gating', () {
    testWidgets('with a PIN set, turning it on asks for it — and is logged',
        (tester) async {
      await setPin(tester);
      platform.batteryExempt = false;
      await pump(tester, const DebtReportSettingsScreen());

      // Cancelled: still off, nothing planned, nothing logged.
      await tap(tester, enabledSwitch);
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect((await stored(tester)).enabled, isFalse);
      expect(platform.schedules, isEmpty);
      expect(await audit(tester), isEmpty);

      // The PIN: on, planned, permission asked, logged.
      await tap(tester, enabledSwitch);
      await enterPin(tester);
      await until(tester, () => platform.schedules.isNotEmpty);
      final settings = await stored(tester);
      expect(settings.enabled, isTrue);
      expect(settings.enabledAt!.isAtSameMomentAs(now), isTrue);
      expect(platform.schedules.single, (minute: 22 * 60, replace: true));
      expect(bridge.notificationRequests, 1);
      expect(await audit(tester), ['DEBT_REPORT_ON']);

      // Not exempt from battery optimization: the app explains and offers.
      await until(
        tester,
        () => find
            .byKey(const ValueKey('debt-report-battery-dialog'))
            .evaluate()
            .isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('debt-report-battery-ok')));
      await animated(tester);
      expect(bridge.batteryRequests, 1);

      // Turning it off needs no PIN, and is logged too.
      await tap(tester, enabledSwitch);
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsNothing);
      expect((await stored(tester)).enabled, isFalse);
      expect(platform.cancels, 1);
      expect(await audit(tester), ['DEBT_REPORT_ON', 'DEBT_REPORT_OFF']);
    });

    testWidgets('without a PIN, it turns on at once (no PIN is forced)',
        (tester) async {
      await pump(tester, const DebtReportSettingsScreen());
      await tap(tester, enabledSwitch);
      await until(tester, () => platform.schedules.isNotEmpty);
      expect(find.byKey(const ValueKey('pin-set-dialog')), findsNothing);
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsNothing);
      expect((await stored(tester)).enabled, isTrue);
      // Exempt already: no battery dialog.
      expect(find.byKey(const ValueKey('debt-report-battery-dialog')),
          findsNothing);
      expect(await audit(tester), ['DEBT_REPORT_ON']);
    });

    testWidgets('changing the folder asks for the PIN — and is logged',
        (tester) async {
      await setPin(tester);
      bridge.folderToPick = const PickedFolder(
        uri: folderUri,
        name: 'Reports',
        kind: 'REMOVABLE',
      );
      await pump(tester, const DebtReportSettingsScreen());
      final choose = find.byKey(const ValueKey('debt-report-choose-folder'));

      // A wrong PIN: the picker never opens.
      await tap(tester, choose);
      await enterPin(tester, '1111');
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(bridge.folderPicks, 0);

      await tap(tester, choose);
      await enterPin(tester);
      await until(tester, () => bridge.folderPicks == 1);
      await settle(tester, 8);
      var settings = await stored(tester);
      expect(settings.folderUri, folderUri);
      expect(settings.folderName, 'Reports');
      expect(settings.folderKind, FolderKind.removable);
      expect(settings.staysOnPhone, isFalse);
      expect(find.text('Reports · SD card / USB drive'), findsOneWidget);
      expect(find.byKey(const ValueKey('debt-report-on-phone-warning')),
          findsNothing);
      final rows = await db(
        tester,
        () => database.db.query('audit_log', orderBy: 'id'),
      );
      expect(rows.single['action'], 'DEBT_REPORT_FOLDER');
      expect(rows.single['details'] as String, contains('Reports'));

      // Back to Downloads: the PIN again, the old grant given up.
      await tap(tester, find.byKey(const ValueKey('debt-report-use-downloads')));
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      await enterPin(tester);
      await until(tester, () => platform.released.isNotEmpty);
      settings = await stored(tester);
      expect(settings.folderUri, isNull);
      expect(platform.released, [folderUri]);
      expect(await audit(tester), ['DEBT_REPORT_FOLDER', 'DEBT_REPORT_FOLDER']);
      expect(find.byKey(const ValueKey('debt-report-on-phone-warning')),
          findsOneWidget);
    });
  });

  group('the page', () {
    testWidgets('says how the last run went', (tester) async {
      await store(tester, const DebtReportSettings(enabled: true));
      platform.status = DebtReportStatus(
        lastAttemptAt: DateTime(2026, 11, 26, 22, 1),
        lastSuccessAt: DateTime(2026, 11, 26, 22, 1),
        outcome: ReportOutcome.ok,
      ).toJson();
      await pump(tester, const DebtReportSettingsScreen());
      expect(find.text('Last report: today 22:01 ✓'), findsOneWidget);
      expect(find.text('Next report: tomorrow 22:00'), findsOneWidget);

      platform.status = DebtReportStatus(
        lastAttemptAt: DateTime(2026, 11, 26, 22, 1),
        lastSuccessAt: DateTime(2026, 11, 25, 22, 3),
        outcome: ReportOutcome.failed,
        problem: ReportProblem.folderUnavailable,
      ).toJson();
      await pump(tester, const DebtReportSettingsScreen());
      expect(find.text('Failed: folder not available'), findsOneWidget);

      platform.status = DebtReportStatus(
        lastSuccessAt: DateTime(2026, 11, 25, 22, 3),
        outcome: ReportOutcome.fallback,
      ).toJson();
      await pump(tester, const Scaffold(body: DebtReportTile()));
      expect(
        find.text('Last report: yesterday 22:03 — saved to Downloads '
            '(folder not available)'),
        findsOneWidget,
      );
    });

    testWidgets('keeps at least one format', (tester) async {
      await store(tester, const DebtReportSettings(formats: {ReportFormat.pdf}));
      await pump(tester, const DebtReportSettingsScreen());
      await tap(tester, find.byKey(const ValueKey('debt-report-pdf')));
      expect(find.text('Keep at least one format.'), findsOneWidget);
      expect((await stored(tester)).formats, {ReportFormat.pdf});
      await tap(tester, find.byKey(const ValueKey('debt-report-xlsx')));
      expect(
        (await stored(tester)).formats,
        {ReportFormat.pdf, ReportFormat.xlsx},
      );
    });

    testWidgets('"Create report now" writes the files and says where',
        (tester) async {
      await pump(tester, const DebtReportSettingsScreen());
      await tap(tester, find.byKey(const ValueKey('debt-report-run-now')));
      await until(
        tester,
        () => find
            .text('Report saved to ${FakeReportPlatform.downloadsLabel}')
            .evaluate()
            .isNotEmpty,
      );
      expect(platform.folder(null).keys.toSet(), {
        'souqi-debts-2026-11-26.xlsx',
        'souqi-debts-2026-11-26.pdf',
      });
      expect(find.text('Last report: today 23:00 ✓'), findsOneWidget);
    });
  });

  group('the notification\'s actions', () {
    Widget host(ReportLaunchAction action) => Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TextButton(
                onPressed: () => handleReportLaunch(context, action),
                child: const Text('tapped'),
              ),
            ),
          ),
        );

    testWidgets('"Share" hands both files to the share sheet', (tester) async {
      final xlsx = File('${staging.path}/souqi-debts-2026-11-26.xlsx')
        ..writeAsBytesSync([1]);
      final pdf = File('${staging.path}/souqi-debts-2026-11-26.pdf')
        ..writeAsBytesSync([2]);
      platform.status = DebtReportStatus(
        outcome: ReportOutcome.ok,
        lastSuccessAt: now,
        files: [xlsx.path, pdf.path],
      ).toJson();
      await pump(tester, host(ReportLaunchAction.share));
      await tester.tap(find.text('tapped'));
      await until(tester, () => bridge.sharedSets.isNotEmpty);
      expect(
        [for (final f in bridge.sharedSets.single) (f.path, f.mimeType)],
        [
          (xlsx.path, ReportFormat.xlsx.mimeType),
          (pdf.path, ReportFormat.pdf.mimeType),
        ],
      );
    });

    testWidgets('"Share" with the PIN-to-open-debts setting asks first',
        (tester) async {
      await setPin(tester);
      await db(tester, () async {
        await SettingsRepository(database.db)
            .setBool(SettingsKeys.debtRequirePin, true);
        return true;
      });
      final pdf = File('${staging.path}/souqi-debts-2026-11-26.pdf')
        ..writeAsBytesSync([2]);
      platform.status = DebtReportStatus(
        outcome: ReportOutcome.ok,
        files: [pdf.path],
      ).toJson();
      await pump(tester, host(ReportLaunchAction.share));
      await tester.tap(find.text('tapped'));
      await animated(tester);
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      expect(bridge.sharedSets, isEmpty);
      await enterPin(tester);
      await until(tester, () => bridge.sharedSets.isNotEmpty);
    });

    testWidgets('"Open folder" opens where the last report went',
        (tester) async {
      platform.status = const DebtReportStatus(
        outcome: ReportOutcome.ok,
        savedToFolderUri: folderUri,
      ).toJson();
      await pump(tester, host(ReportLaunchAction.openFolder));
      await tester.tap(find.text('tapped'));
      await until(tester, () => bridge.openedFolders.isNotEmpty);
      expect(bridge.openedFolders, [folderUri]);

      // Gone files / no file manager: said so.
      bridge.folderOpens = false;
      await tester.tap(find.text('tapped'));
      await until(
        tester,
        () => find
            .text('No app on this phone can open the folder.')
            .evaluate()
            .isNotEmpty,
      );
    });
  });

  group('layout at 360×640, font scale 1.3', () {
    for (final locale in ['ar', 'en']) {
      testWidgets('[$locale] every part of the page, nothing overflows',
          (tester) async {
        await store(
          tester,
          const DebtReportSettings(
            enabled: true,
            folderUri: folderUri,
            folderName: 'تقارير سوقي اليومية على بطاقة الذاكرة',
            folderKind: FolderKind.phone,
            keepDays: 365,
          ),
        );
        platform
          ..batteryExempt = false
          ..notifications = false
          ..status = DebtReportStatus(
            lastAttemptAt: DateTime(2026, 11, 26, 22, 1),
            lastSuccessAt: DateTime(2026, 11, 24, 22, 3),
            outcome: ReportOutcome.fallback,
          ).toJson();
        await pump(
          tester,
          const DebtReportSettingsScreen(),
          locale: locale,
          size: const Size(360, 640),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        for (final key in [
          'debt-report-enabled',
          'debt-report-time',
          'debt-report-pdf',
          'debt-report-folder',
          'debt-report-on-phone-warning',
          'debt-report-use-downloads',
          'debt-report-keep',
          'debt-report-notify',
          'debt-report-notifications-blocked',
          'debt-report-battery-button',
          'debt-report-run-now',
        ]) {
          await reach(tester, find.byKey(ValueKey(key)));
          expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
          expect(tester.takeException(), isNull, reason: key);
        }

        // The battery dialog and the tile in Settings, on the same phone.
        await pump(
          tester,
          Scaffold(
            body: ListView(children: const [DebtReportTile()]),
            floatingActionButton: Builder(
              builder: (context) => FloatingActionButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => const BatteryExemptionDialog(),
                ),
              ),
            ),
          ),
          locale: locale,
          size: const Size(360, 640),
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byType(FloatingActionButton));
        await animated(tester);
        expect(find.byKey(const ValueKey('debt-report-battery-dialog')),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('debt-report-battery-later')));
        await animated(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
