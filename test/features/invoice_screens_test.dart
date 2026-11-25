import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/features/invoice/invoice_actions.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:souqi/features/setup/setup_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// The invoice settings screen and the output actions, driven through the
/// real widgets with a real database and a fake Android bridge.
///
/// Database futures and image rasterisation only progress in real async, so
/// frames are driven with [settle] (see the note in sale_screen_test.dart).
void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late FakeNativeBridge bridge;
  late Directory outputDir;

  Future<void> settle(WidgetTester tester, [int rounds = 14]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Pumps frames (and lets real async work run) until [done] holds.
  /// Rendering, encoding and file writes take a variable amount of real
  /// time, so output actions are awaited by their effect, not by a fixed
  /// number of frames.
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

  /// Waits for the running output action to finish: its button is disabled
  /// while it runs.
  Future<void> untilIdle(
    WidgetTester tester, [
    Key button = const ValueKey('invoice-more'),
  ]) async {
    await tester.pump();
    await until(
      tester,
      () => tester.widget<ButtonStyleButton>(find.byKey(button)).onPressed != null,
    );
    // Let a snack bar that replaces an earlier one finish animating in.
    await settle(tester, 30);
  }

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Future<String> stored(WidgetTester tester, String key) => db(
        tester,
        () async {
          final rows = await database.db
              .query('settings', where: 'key = ?', whereArgs: [key]);
          return rows.isEmpty ? '<absent>' : rows.single['value'] as String;
        },
      );

  Future<void> store(WidgetTester tester, Map<String, String> values) => db(
        tester,
        () async {
          for (final entry in values.entries) {
            await database.db.insert(
              'settings',
              {'key': entry.key, 'value': entry.value, 'updated_at': 0},
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          return true;
        },
      );

  Future<void> pumpScreen(
    WidgetTester tester,
    Widget home, {
    Locale locale = const Locale('en'),
  }) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(locale)),
          nativeBridgeProvider.overrideWithValue(bridge),
          outputDirectoryProvider.overrideWithValue(() async => outputDir),
        ],
        child: MaterialApp(
          locale: locale,
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

  /// Scrolls the settings list until [finder] is built and on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    final list = find.byType(Scrollable).last;
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.drag(list, const Offset(0, -250));
      await settle(tester, 2);
    }
    await tester.ensureVisible(finder);
    await settle(tester, 2);
  }

  Finder inPreview(Finder matching) => find.descendant(
        of: find.byKey(const ValueKey('invoice-preview')),
        matching: matching,
      );

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
    outputDir = await Directory.systemTemp.createTemp('souqi_test_');
  });

  tearDown(() async {
    await database.close();
    try {
      if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle for a moment; the OS temp folder is
      // cleaned up on its own.
    }
  });

  group('invoice settings screen', () {
    testWidgets('shows the computed printable width and follows the paper',
        (tester) async {
      await pumpScreen(tester, const InvoiceSettingsScreen());
      expect(tester.takeException(), isNull);
      expect(find.text('Printable width: 512 dots (64.1 mm)'), findsOneWidget);
      expect(find.byType(InvoiceView), findsOneWidget);

      await tester.tap(find.text('58 mm'));
      await settle(tester);
      expect(find.text('Printable width: 384 dots (48.0 mm)'), findsOneWidget);
      // Stored: the paper AND the margin that matches its print head.
      expect(await stored(tester, SettingsKeys.paperWidthMm), '58');
      expect(await stored(tester, SettingsKeys.sideMarginMm), '5');

      await tester.tap(find.text('80 mm'));
      await settle(tester);
      expect(find.text('Printable width: 512 dots (64.1 mm)'), findsOneWidget);
      expect(await stored(tester, SettingsKeys.sideMarginMm), '7.5');
    });

    testWidgets('the advanced override replaces the computed width',
        (tester) async {
      await pumpScreen(tester, const InvoiceSettingsScreen());
      await reveal(tester, find.text('Advanced'));
      await tester.tap(find.text('Advanced'));
      await settle(tester);
      await reveal(tester, find.byKey(const ValueKey('dots-override')));

      final field = find.descendant(
        of: find.byKey(const ValueKey('dots-override')),
        matching: find.byType(TextField),
      );
      // The info line sits just above the field and may be scrolled out of
      // view (still built, but "offstage" for finders).
      Finder info(String text) =>
          find.textContaining(text, skipOffstage: false);

      await tester.enterText(field, '560');
      await settle(tester);
      expect(info('Printable width: 560 dots'), findsOneWidget);
      expect(await stored(tester, SettingsKeys.printableDotsOverride), '560');

      // Out of range: an error, and the stored value is left alone.
      await tester.enterText(field, '7');
      await settle(tester);
      expect(find.text('Invalid number'), findsOneWidget);
      expect(await stored(tester, SettingsKeys.printableDotsOverride), '560');

      // Empty: back to the computed width.
      await tester.enterText(field, '');
      await settle(tester);
      expect(info('Printable width: 512 dots'), findsOneWidget);
      expect(await stored(tester, SettingsKeys.printableDotsOverride), '');
    });

    testWidgets('the preview updates as settings change, and they are saved',
        (tester) async {
      await pumpScreen(tester, const InvoiceSettingsScreen());

      // Default invoice language is Arabic even though the app is English.
      expect(inPreview(find.text('سكر')), findsOneWidget);
      expect(
        Directionality.of(tester.element(inPreview(find.text('سكر')))),
        TextDirection.rtl,
      );

      await reveal(tester, find.byKey(const ValueKey('shop-name')));
      await tester.enterText(
        find.byKey(const ValueKey('shop-name')),
        'Abu Ahmad Market',
      );
      await settle(tester);
      expect(inPreview(find.text('Abu Ahmad Market')), findsOneWidget);
      expect(await stored(tester, SettingsKeys.shopName), 'Abu Ahmad Market');

      await reveal(tester, find.byKey(const ValueKey('footer-text')));
      await tester.enterText(
        find.byKey(const ValueKey('footer-text')),
        'Thank you\nSee you again',
      );
      await settle(tester);
      expect(inPreview(find.text('Thank you\nSee you again')), findsOneWidget);

      await reveal(tester, find.byKey(const ValueKey('invoice-language')));
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('invoice-language')),
        matching: find.text('English'),
      ));
      await settle(tester);
      expect(inPreview(find.text('Sugar')), findsOneWidget);
      expect(
        Directionality.of(tester.element(inPreview(find.text('Sugar')))),
        TextDirection.ltr,
      );
      expect(await stored(tester, SettingsKeys.invoiceLanguage), 'en');

      // Item codes are off by default; switching them on shows them at once.
      expect(inPreview(find.text('101')), findsNothing);
      await reveal(tester, find.byKey(const ValueKey('toggle-item-code')));
      await tester.tap(find.byKey(const ValueKey('toggle-item-code')));
      await settle(tester);
      expect(inPreview(find.text('101')), findsOneWidget);
      expect(await stored(tester, SettingsKeys.showItemCode), '1');
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in Arabic without exceptions', (tester) async {
      await pumpScreen(
        tester,
        const InvoiceSettingsScreen(),
        locale: const Locale('ar'),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('الفاتورة والطباعة'), findsOneWidget);
    });

    testWidgets('test print without a printer explains what to do',
        (tester) async {
      await pumpScreen(tester, const InvoiceSettingsScreen());
      await tester.tap(find.byKey(const ValueKey('test-print')));
      await settle(tester);
      expect(
        find.text('No printer selected. Choose one in Settings → Invoice & printing.'),
        findsOneWidget,
      );
      expect(bridge.printed, isEmpty);
    });

    testWidgets('choosing a paired printer remembers it, and test print uses it',
        (tester) async {
      bridge.devices = const [
        PairedDevice(name: 'Headphones', address: '11:22:33:44:55:66'),
        PairedDevice(
          name: 'XP-P323B',
          address: 'AA:BB:CC:DD:EE:FF',
          looksLikePrinter: true,
        ),
      ];
      await pumpScreen(tester, const InvoiceSettingsScreen());
      await tester.tap(find.text('Choose printer'));
      await settle(tester);
      await tester.tap(find.text('XP-P323B'));
      await settle(tester);
      // The picker now asks for the printer's language; Receipt (ESC/POS)
      // is the default.
      expect(find.text('Receipt (ESC/POS)'), findsOneWidget);
      expect(find.text('Label (TSPL)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('printer-language-confirm')));
      await settle(tester);

      expect(await stored(tester, SettingsKeys.printerMac), 'AA:BB:CC:DD:EE:FF');
      expect(await stored(tester, SettingsKeys.printerName), 'XP-P323B');
      expect(find.text('XP-P323B'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('test-print')));
      await untilIdle(tester, const ValueKey('test-print'));
      expect(bridge.printed, hasLength(1));
      expect(bridge.printed.single.address, 'AA:BB:CC:DD:EE:FF');
      expect(bridge.printed.single.bytes.sublist(0, 6),
          [0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00]);
      expect(find.text('Sent to the printer'), findsOneWidget);
    });

    testWidgets('Bluetooth off is reported in the printer picker',
        (tester) async {
      bridge.status = const BluetoothStatus(
        supported: true,
        enabled: false,
        permissionGranted: true,
      );
      await pumpScreen(tester, const InvoiceSettingsScreen());
      await tester.tap(find.text('Choose printer'));
      await settle(tester);
      expect(
        find.text('Bluetooth is off. Turn it on and try again.'),
        findsOneWidget,
      );
    });
  });

  group('invoice actions', () {
    Future<void> pumpActions(WidgetTester tester, Invoice invoice) =>
        pumpScreen(
          tester,
          Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: InvoiceActions(invoice: invoice),
            ),
          ),
        );

    const printKey = ValueKey('invoice-primary-print');
    const shareKey = ValueKey('invoice-primary-shareImage');
    const whatsAppKey = ValueKey('invoice-whatsapp');

    testWidgets('output mode Print: Print is the primary button',
        (tester) async {
      await pumpActions(tester, sypInvoice());
      expect(find.byKey(printKey), findsOneWidget);
      expect(find.byKey(shareKey), findsNothing);
      // No customer phone → no direct WhatsApp button.
      expect(find.byKey(whatsAppKey), findsNothing);

      // Everything else stays reachable under "More".
      await tester.tap(find.byKey(const ValueKey('invoice-more')));
      await settle(tester);
      expect(find.text('Share as image'), findsOneWidget);
      expect(find.text('Share as PDF'), findsOneWidget);
      expect(find.text('Send on WhatsApp'), findsOneWidget);
      expect(find.text('Save image to phone'), findsOneWidget);
      expect(find.text('Save PDF to phone'), findsOneWidget);
    });

    testWidgets('output mode Share: Share is primary and sends a 2× PNG',
        (tester) async {
      await store(tester, {SettingsKeys.outputMode: 'SHARE'});
      await pumpActions(tester, sypInvoice(invoiceNo: 41));
      expect(find.byKey(shareKey), findsOneWidget);
      expect(find.byKey(printKey), findsNothing);

      await tester.tap(find.byKey(shareKey));
      await untilIdle(tester);
      expect(bridge.shared, hasLength(1));
      final share = bridge.shared.single;
      expect(share.mimeType, 'image/png');
      expect(share.path, endsWith('invoice-41.png'));
      final size = readPngSize(File(share.path).readAsBytesSync());
      expect(size!.width, 2 * 512);
      expect(tester.takeException(), isNull);
    });

    testWidgets('output mode Print + Share: both are primary', (tester) async {
      await store(tester, {SettingsKeys.outputMode: 'BOTH'});
      await pumpActions(tester, sypInvoice());
      expect(find.byKey(printKey), findsOneWidget);
      expect(find.byKey(shareKey), findsOneWidget);
    });

    testWidgets('printing sends an ESC/POS raster to the remembered printer',
        (tester) async {
      await store(tester, {
        SettingsKeys.printerMac: 'AA:BB:CC:DD:EE:FF',
        SettingsKeys.printerName: 'XP-80',
        SettingsKeys.cutPaper: '1',
        SettingsKeys.feedLines: '2',
      });
      await pumpActions(tester, sypInvoice());
      await tester.tap(find.byKey(printKey));
      await untilIdle(tester);

      expect(bridge.printed, hasLength(1));
      final bytes = bridge.printed.single.bytes;
      expect(bytes.sublist(0, 8), [0x1B, 0x40, 0x1D, 0x76, 0x30, 0x00, 64, 0]);
      // Feed 2 lines, then cut.
      expect(bytes.sublist(bytes.length - 7),
          [0x1B, 0x64, 2, 0x1D, 0x56, 0x42, 0x00]);
      expect(find.text('Sent to the printer'), findsOneWidget);
    });

    testWidgets('printer problems give a clear message', (tester) async {
      await store(tester, {
        SettingsKeys.printerMac: 'AA:BB:CC:DD:EE:FF',
        SettingsKeys.printerName: 'XP-80',
      });
      await pumpActions(tester, sypInvoice());

      // Bluetooth off.
      bridge.status = const BluetoothStatus(
        supported: true,
        enabled: false,
        permissionGranted: true,
      );
      await tester.tap(find.byKey(printKey));
      await untilIdle(tester);
      expect(find.text('Bluetooth is off. Turn it on and try again.'),
          findsOneWidget);
      expect(find.text('Bluetooth settings'), findsOneWidget);

      // Permission denied (Android 12+).
      bridge
        ..status = const BluetoothStatus(
          supported: true,
          enabled: true,
          permissionGranted: false,
        )
        ..grantPermissionOnRequest = false;
      await tester.tap(find.byKey(printKey));
      await untilIdle(tester);
      expect(bridge.permissionRequests, 1);
      expect(find.textContaining('not allowed to use Bluetooth'), findsOneWidget);
      expect(find.text('App settings'), findsOneWidget);

      // Printer switched off / out of range.
      bridge
        ..status = const BluetoothStatus(
          supported: true,
          enabled: true,
          permissionGranted: true,
        )
        ..printError = const OutputException(OutputFailure.printerUnreachable);
      await tester.tap(find.byKey(printKey));
      await untilIdle(tester);
      expect(find.textContaining('Cannot reach the printer XP-80'),
          findsOneWidget);
      expect(bridge.printed, isEmpty);
    });

    testWidgets('a customer phone adds Send on WhatsApp to that chat',
        (tester) async {
      await pumpActions(tester, sypInvoice(customerPhone: '0944 123 456'));
      expect(find.byKey(whatsAppKey), findsOneWidget);

      await tester.tap(find.byKey(whatsAppKey));
      await untilIdle(tester);
      expect(bridge.whatsAppSends, hasLength(1));
      final send = bridge.whatsAppSends.single;
      expect(send.phone, '963944123456');
      expect(send.package, whatsAppPackage);
      expect(send.mimeType, 'image/png');
      expect(File(send.path).existsSync(), isTrue);
      expect(bridge.shared, isEmpty);
    });

    testWidgets('both WhatsApp apps installed: the user picks one',
        (tester) async {
      bridge.installedWhatsApp = const [whatsAppPackage, whatsAppBusinessPackage];
      await pumpActions(tester, sypInvoice(customerPhone: '+963944123456'));
      await tester.tap(find.byKey(whatsAppKey));
      await until(
        tester,
        () => find.text('WhatsApp Business').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('WhatsApp Business'));
      await untilIdle(tester);
      expect(bridge.whatsAppSends.single.package, whatsAppBusinessPackage);
      expect(bridge.whatsAppSends.single.phone, '963944123456');
    });

    testWidgets('no WhatsApp, or no direct chat: falls back to the share sheet',
        (tester) async {
      bridge.installedWhatsApp = const [];
      await pumpActions(tester, sypInvoice(customerPhone: '0944123456'));
      await tester.tap(find.byKey(whatsAppKey));
      await untilIdle(tester);
      expect(bridge.whatsAppSends, isEmpty);
      expect(bridge.shared, hasLength(1));

      bridge
        ..installedWhatsApp = const [whatsAppPackage]
        ..whatsAppOpens = false;
      await tester.tap(find.byKey(whatsAppKey));
      await untilIdle(tester);
      expect(bridge.whatsAppSends, hasLength(1));
      expect(bridge.shared, hasLength(2));
    });

    testWidgets('the default country code setting is used', (tester) async {
      await store(tester, {SettingsKeys.defaultCountryCode: '90'});
      await pumpActions(tester, sypInvoice(customerPhone: '0532 123 45 67'));
      await tester.tap(find.byKey(whatsAppKey));
      await untilIdle(tester);
      expect(bridge.whatsAppSends.single.phone, '905321234567');
    });

    testWidgets('save to phone goes to Downloads/Souqi as image and as PDF',
        (tester) async {
      await pumpActions(tester, sypInvoice(invoiceNo: 9));
      await tester.tap(find.byKey(const ValueKey('invoice-more')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('invoice-more-saveImage')));
      await untilIdle(tester);
      expect(bridge.saved.single.fileName, 'invoice-9.png');
      expect(bridge.saved.single.mimeType, 'image/png');
      expect(find.text('Saved to Download/Souqi/invoice-9.png'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('invoice-more')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('invoice-more-savePdf')));
      await untilIdle(tester);
      expect(bridge.saved.last.fileName, 'invoice-9.pdf');
      expect(bridge.saved.last.mimeType, 'application/pdf');
      final pdf = File(bridge.saved.last.path).readAsBytesSync();
      expect(String.fromCharCodes(pdf.sublist(0, 5)), '%PDF-');
    });
  });

  group('first-launch setup', () {
    testWidgets('"no printer" makes Share the output mode', (tester) async {
      await pumpScreen(tester, const SetupScreen());
      expect(find.text('Do you have a receipt printer?'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('setup-printer-false')));
      await tester.tap(find.byKey(const ValueKey('setup-printer-false')));
      await settle(tester, 2);
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await settle(tester);
      expect(await stored(tester, SettingsKeys.outputMode), 'SHARE');
      expect(await stored(tester, SettingsKeys.setupDone), '1');
    });

    testWidgets('the default answer keeps Print', (tester) async {
      await pumpScreen(tester, const SetupScreen());
      await tester.ensureVisible(find.text('Start'));
      await tester.tap(find.text('Start'));
      await settle(tester);
      expect(await stored(tester, SettingsKeys.outputMode), 'PRINT');
    });
  });
}
