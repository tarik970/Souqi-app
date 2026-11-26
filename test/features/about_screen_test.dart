import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:souqi/app.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/settings/about_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// Settings → About as phase 6 left it: version, build number, license
/// state, "Share error log" — and no developer tools on a customer's phone.
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late Directory temp;
  late FakeNativeBridge bridge;

  setUp(() async {
    database = await openTestDb();
    temp = await Directory.systemTemp.createTemp('souqi_about_test');
    bridge = FakeNativeBridge();
    PackageInfo.setMockInitialValues(
      appName: 'Souqi',
      packageName: 'com.souqi.souqi',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
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

  Future<void> pump(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    // Tall enough for the whole page: "not shown" must not mean "below the
    // fold".
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1200, 6000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          nativeBridgeProvider.overrideWithValue(bridge),
          outputDirectoryProvider.overrideWithValue(
            () async => Directory(p.join(temp.path, 'share')).create(),
          ),
          errorLogDirectoryProvider.overrideWithValue(
            () async => Directory(p.join(temp.path, 'logs')),
          ),
        ],
        child: MaterialApp(
          locale: locale,
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

  testWidgets('version, build number and license state each have a row',
      (tester) async {
    await pump(tester, const AboutScreen());

    final version = tester.widget<ListTile>(
      find.byKey(const ValueKey('about-version')),
    );
    expect((version.title! as Text).data, 'Version');
    expect((version.trailing! as Text).data, '1.0.0');
    final build = tester.widget<ListTile>(
      find.byKey(const ValueKey('about-build')),
    );
    expect((build.title! as Text).data, 'Build number');
    expect((build.trailing! as Text).data, '1');
    // No license service in this scope: the state of an activated phone.
    expect(find.byKey(const ValueKey('about-license')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('about-license-state')))
          .data,
      'Activated · Lifetime license',
    );
  });

  testWidgets('the developer tools are a debug-build thing: the page a '
      'customer sees has none', (tester) async {
    // In a debug build (tests are one) they are there…
    await pump(tester, const AboutScreen());
    expect(find.byKey(const ValueKey('about-seed-invoices')), findsOneWidget);
    expect(find.text('Developer tools (debug build)'), findsOneWidget);

    // …and the release page — the same widget with the tools off, which is
    // what kDebugMode == false compiles to — shows the rest and none of them.
    await pump(tester, const AboutScreen(showDeveloperTools: false));
    expect(find.byKey(const ValueKey('about-version')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('about-share-error-log')),
      findsOneWidget,
    );
    for (final key in [
      'about-seed-invoices',
      'about-seed-customers',
      'about-seed-cards',
      'about-seed-debts',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNothing, reason: key);
    }
    expect(find.text('Developer tools (debug build)'), findsNothing);
  });

  testWidgets('"Share error log" hands one text file to the share sheet, '
      'with the version, the database and the license on top', (tester) async {
    await tester.runAsync(() async {
      final logs = await Directory(p.join(temp.path, 'logs')).create();
      await File(p.join(logs.path, 'errors-app.log')).writeAsString(
        '==== 2026-11-26 14:05:09 +03:00 [app] uncaught · v1.0.0+1\n'
        'Bad state: something broke\n#0 main\n\n',
      );
    });
    await pump(tester, const AboutScreen(showDeveloperTools: false));
    expect(find.textContaining('Errors recorded: 1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about-share-error-log')));
    for (var i = 0; i < 40 && bridge.shared.isEmpty; i++) {
      await settle(tester, 2);
    }
    final shared = bridge.shared.single;
    expect(shared.mimeType, 'text/plain');
    expect(p.basename(shared.path), startsWith('souqi-error-log-'));
    final text = await tester.runAsync(() => File(shared.path).readAsString());
    expect(text, contains('Souqi error log'));
    expect(text, contains('App: 1.0.0+1'));
    expect(text, contains('Database: schema ${AppDatabase.schemaVersion}'));
    expect(text, contains('License: activated, lifetime'));
    expect(text, contains('Errors recorded: 1'));
    expect(text, contains('Bad state: something broke'));
  });

  testWidgets('an empty log is still shared — with "none" on top — and the '
      'page reads in Arabic', (tester) async {
    await pump(
      tester,
      const AboutScreen(showDeveloperTools: false),
      locale: const Locale('ar'),
    );
    expect(find.text('مشاركة سجل الأخطاء'), findsOneWidget);
    expect(find.textContaining('لا توجد أخطاء مسجَّلة'), findsOneWidget);
    expect(find.text('الإصدار'), findsOneWidget);
    expect(find.text('رقم البناء'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('about-share-error-log')));
    for (var i = 0; i < 40 && bridge.shared.isEmpty; i++) {
      await settle(tester, 2);
    }
    final text = await tester
        .runAsync(() => File(bridge.shared.single.path).readAsString());
    expect(text, contains('Errors recorded: none'));
  });
}
