import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/invoice/printer_diagnostics_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// PRINTING OUT OF THE BOX: the language of a printer is found out — by its
/// name, or by asking it — when it is chosen, and again at the first print
/// for a printer that could not be asked then.
void main() {
  setUpAll(sqfliteFfiInit);

  const address = 'AA:BB:CC:DD:EE:FF';

  late AppDatabase database;
  late FakeNativeBridge bridge;
  late Directory outputDir;

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
    outputDir = await Directory.systemTemp.createTemp('souqi_detect_test');
  });

  tearDown(() async {
    await database.close();
    await outputDir.delete(recursive: true);
  });

  Future<void> settle(WidgetTester tester, [int rounds = 14]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
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

  Future<Map<String, String>> settings(WidgetTester tester) async {
    final rows = await tester.runAsync(() => database.db.query('settings'));
    return {
      for (final row in rows!) row['key'] as String: row['value'] as String,
    };
  }

  Future<void> store(WidgetTester tester, Map<String, String> values) async {
    await tester.runAsync(() async {
      for (final entry in values.entries) {
        await database.db.insert(
          'settings',
          {'key': entry.key, 'value': entry.value, 'updated_at': 0},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<void> pumpScreen(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1200, 5200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          nativeBridgeProvider.overrideWithValue(bridge),
          outputDirectoryProvider.overrideWithValue(() async => outputDir),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: home,
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> choose(WidgetTester tester, String name) async {
    await tester.tap(find.text('Choose printer'));
    await settle(tester);
    await tester.tap(find.text(name));
    await settle(tester, 20);
  }

  Map<String, Object?> languages(Map<String, String> stored) =>
      // Only what changed is written: no row yet means no printer known.
      jsonDecode(stored[SettingsKeys.printerLanguages] ?? '{}')
          as Map<String, Object?>;

  testWidgets('an XP-365B is recognised by its name: label mode, 512 dots, '
      'centred — and it is never asked anything', (tester) async {
    bridge.devices = const [
      PairedDevice(name: 'XP-365B', address: address, looksLikePrinter: true),
    ];
    // A shop that had set things up for another paper before.
    await store(tester, {
      SettingsKeys.paperWidthMm: '58',
      SettingsKeys.sideMarginMm: '5',
    });
    await pumpScreen(tester, const InvoiceSettingsScreen());
    await choose(tester, 'XP-365B');

    expect(
      find.text('Known printer (XP-365B): its tested settings are used.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('printer-language-confirm')));
    await settle(tester);

    final stored = await settings(tester);
    expect(stored[SettingsKeys.printerMac], address);
    expect(languages(stored), {address: 'TSPL'});
    expect(stored[SettingsKeys.paperWidthMm], '80');
    expect(stored[SettingsKeys.printableDotsOverride] ?? '', '',
        reason: 'no width override: 80 mm with its margin gives 512');
    expect(jsonDecode(stored[SettingsKeys.printerOffsets]!), {address: 0});
    expect(bridge.queries, isEmpty);
    expect(find.textContaining('512'), findsWidgets);

    // The test print is a TSPL job: it starts with the empty line and SIZE.
    await tester.tap(find.byKey(const ValueKey('test-print')));
    await until(tester, () => bridge.printed.isNotEmpty);
    final job = latin1.decode(bridge.printed.single.bytes.sublist(0, 40));
    expect(job, startsWith('\r\nSIZE 80 mm,'));
  });

  testWidgets('an unknown printer that answers as a label printer is set to '
      'TSPL without the shop choosing anything', (tester) async {
    bridge.devices = const [
      PairedDevice(name: 'Printer001', address: address),
    ];
    bridge.statusReplies = const {
      0x1B: [0x00],
    };
    await pumpScreen(tester, const InvoiceSettingsScreen());
    await choose(tester, 'Printer001');

    expect(find.text('The printer answered: Label (TSPL).'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('printer-language-confirm')));
    await settle(tester);
    expect(languages(await settings(tester)), {address: 'TSPL'});
    // Both questions, the ESC/POS one first.
    expect(
      [for (final q in bridge.queries) q.bytes.first],
      [0x10, 0x1B],
    );
  });

  testWidgets('a printer that answers nothing is a receipt printer; a choice '
      'made by hand wins over what was found', (tester) async {
    bridge.devices = const [
      PairedDevice(name: 'POS-80', address: address),
    ];
    await pumpScreen(tester, const InvoiceSettingsScreen());
    await choose(tester, 'POS-80');
    expect(find.textContaining('The printer did not answer'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('printer-language-tspl')));
    await settle(tester, 3);
    await tester.tap(find.byKey(const ValueKey('printer-language-confirm')));
    await settle(tester);
    expect(languages(await settings(tester)), {address: 'TSPL'});
  });

  testWidgets('a printer that was switched off when it was chosen is asked '
      'at the first print, once', (tester) async {
    bridge.devices = const [
      PairedDevice(name: 'POS-80', address: address),
    ];
    bridge.queryError =
        const OutputException(OutputFailure.printerUnreachable);
    await pumpScreen(tester, const InvoiceSettingsScreen());
    await choose(tester, 'POS-80');
    expect(
      find.textContaining('could not be reached right now'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('printer-language-confirm')));
    await settle(tester);
    // Chosen, but nothing is decided about its language yet.
    var stored = await settings(tester);
    expect(stored[SettingsKeys.printerMac], address);
    expect(languages(stored), isEmpty);

    // Switched on: the first print asks it (it is a label printer)…
    bridge
      ..queryError = null
      ..statusReplies = const {
        0x1B: [0x00],
      };
    await tester.tap(find.byKey(const ValueKey('test-print')));
    await until(tester, () => bridge.printed.isNotEmpty);
    expect(bridge.queries, hasLength(2));
    expect(
      latin1.decode(bridge.printed.single.bytes.sublist(0, 6)),
      '\r\nSIZE',
    );
    stored = await settings(tester);
    expect(languages(stored), {address: 'TSPL'});

    // …and the second print does not ask again.
    await until(
      tester,
      () =>
          tester
              .widget<ButtonStyleButton>(
                find.byKey(const ValueKey('test-print')),
              )
              .onPressed !=
          null,
    );
    await tester.tap(find.byKey(const ValueKey('test-print')));
    await until(tester, () => bridge.printed.length == 2);
    expect(bridge.queries, hasLength(2));
  });

  testWidgets('diagnostics: "Detect" finds the language again, and '
      'calibration sits under Advanced', (tester) async {
    await store(tester, {
      SettingsKeys.printerMac: address,
      SettingsKeys.printerName: 'Printer001',
      SettingsKeys.printerLanguages: jsonEncode({address: 'TSPL'}),
    });
    // It answers as a receipt printer now (its switch was changed).
    bridge.statusReplies = const {
      0x10: [0x12],
    };
    await pumpScreen(tester, const PrinterDiagnosticsScreen());

    // Calibration is out of the way until Advanced is opened.
    expect(find.byKey(const ValueKey('diag-calibration-test')), findsNothing);
    expect(find.byKey(const ValueKey('diag-offset')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('diag-detect')));
    await until(
      tester,
      () => find
          .byKey(const ValueKey('diag-detect-result'))
          .evaluate()
          .isNotEmpty,
    );
    expect(
      find.text('The printer answered: Receipt (ESC/POS).'),
      findsOneWidget,
    );
    expect(languages(await settings(tester)), {address: 'ESCPOS'});

    await tester.tap(find.byKey(const ValueKey('diag-advanced')));
    await settle(tester, 30);
    expect(find.byKey(const ValueKey('diag-calibration-test')), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-offset')), findsOneWidget);
    expect(find.byKey(const ValueKey('diag-width')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('diag-tspl-one-is-black')),
      findsOneWidget,
    );
  });
}
