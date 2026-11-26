import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/app.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/config/support.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/licensing/license_codec.dart';
import 'package:souqi/core/licensing/license_service.dart';
import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/features/archive/archive_screen.dart';
import 'package:souqi/features/customers/quick_search.dart';
import 'package:souqi/features/debts/payment_form_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:souqi/features/license/license_providers.dart';
import 'package:souqi/features/license/license_screen.dart';
import 'package:souqi/features/products/product_form_screen.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/security/pin_recovery.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/licensing/license_test_kit.dart';
import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// LICENSING ON THE SCREENS: where an unlicensed app opens, what the
/// activation screen does, what the trial shows — and that a license's
/// feature mask really removes what it turns off, wherever it appears.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);
  tearDown(FeatureGate.reset);

  late TestDeveloper developer;
  late AppDatabase database;
  late InMemoryKeyStore keys;
  late FakeLicensePlatform phone;
  late TestClock clock;
  late FakeNativeBridge bridge;
  late List<AppRestartNotice?> restarts;

  final t0 = DateTime.utc(2026, 11, 26, 10);

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// A page or a dialog has finished sliding in or out.
  Future<void> animated(WidgetTester tester) => settle(tester, 30);

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  /// A database write that returns nothing.
  Future<void> act(WidgetTester tester, Future<void> Function() action) =>
      tester.runAsync(action);

  /// The licensing service of an app start on this phone, started.
  Future<LicenseService> startService(WidgetTester tester) => db(tester, () async {
        final service = testLicenseService(
          db: database.db,
          keys: keys,
          platform: phone,
          clock: clock,
          developer: developer,
        );
        await service.start();
        return service;
      });

  Future<String> licenseFor(
    WidgetTester tester, {
    FakeLicensePlatform? device,
    Iterable<Feature>? features,
    String shop = 'Al Noor Market',
    DateTime? expiresAt,
  }) =>
      db(
        tester,
        () => developer.license(
          device: (device ?? phone).device,
          features: features,
          issuedAt: clock.now,
          expiresAt: expiresAt,
          shop: shop,
        ),
      );

  /// A phone-shaped window; [tall] builds a whole settings page at once, so
  /// "is not there" is not just "is below the fold".
  void window(WidgetTester tester, {bool tall = false}) {
    tester.view.physicalSize = Size(1200, tall ? 9000 : 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  List<Override> overrides(LicenseService? service) => [
        databaseProvider.overrideWithValue(database),
        if (service != null) licenseServiceProvider.overrideWithValue(service),
        appLocaleProvider
            .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
        setupDoneProvider.overrideWith(() => SetupDoneNotifier(true)),
        platformBridgeProvider.overrideWithValue(bridge),
        secretKeyStoreProvider.overrideWithValue(keys),
        appRestartProvider.overrideWithValue((_, notice) async {
          restarts.add(notice);
        }),
      ];

  /// The whole app, as `SouqiRoot` builds it — with [service] in place.
  Future<void> pumpApp(WidgetTester tester, LicenseService? service) async {
    window(tester);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: overrides(service),
        child: const SouqiApp(),
      ),
    );
    await settle(tester);
  }

  /// One screen.
  Future<void> pumpScreen(
    WidgetTester tester,
    Widget home, {
    LicenseService? service,
    bool tall = false,
    List<Override> more = const [],
  }) async {
    window(tester, tall: tall);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [...overrides(service), ...more],
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

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

  /// The request code as the screen shows it: four groups, each its own
  /// text.
  void expectRequestCodeShown(String requestCode) {
    final shown = find.byKey(const ValueKey('license-request-code'));
    expect(shown, findsOneWidget);
    for (final group in requestCode.split('-').toSet()) {
      expect(
        find.descendant(of: shown, matching: find.text(group)),
        findsWidgets,
        reason: group,
      );
    }
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester, 4);
  }

  setUpAll(() async => developer = await TestDeveloper.create());

  setUp(() async {
    database = await openTestDb();
    keys = InMemoryKeyStore();
    phone = FakeLicensePlatform();
    clock = TestClock(t0);
    bridge = FakeNativeBridge();
    restarts = [];
  });

  tearDown(() async => database.close());

  group('not licensed', () {
    testWidgets('the app opens on the activation screen with the request '
        'code; the data can still be browsed, selling cannot be done',
        (tester) async {
      final service = await startService(tester);
      await db(tester, () => insertInvoice(database.db, invoiceNo: 1));
      clock.advance(const Duration(days: 8));
      await db(tester, service.refresh);

      await pumpApp(tester, service);
      expect(find.byType(LicenseScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('license-status-unlicensed')),
        findsOneWidget,
      );
      expect(find.text('The 7-day trial has ended.'), findsOneWidget);
      expectRequestCodeShown(phone.requestCode);

      // "Browse my data": the home screen, with the lock said on top.
      final browse = find.byKey(const ValueKey('license-browse'));
      await reveal(tester, browse);
      await tester.tap(browse);
      await settle(tester);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Not activated — selling is locked'), findsOneWidget);

      // The archive opens and shows what the shop has.
      await tester.tap(find.text('Archive'));
      await animated(tester);
      expect(find.byType(ArchiveScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await animated(tester);

      // The sale does not.
      await tester.tap(find.text('Sale'));
      await animated(tester);
      expect(find.byType(SaleScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('license-locked')), findsOneWidget);
      expect(
        find.text('Selling is locked until Souqi is activated.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('sale-search-field')), findsNothing);
      expect(find.byKey(const ValueKey('sale-save')), findsNothing);

      // …and leads back to the activation screen.
      await tester.tap(find.byKey(const ValueKey('license-locked-activate')));
      await animated(tester);
      expectRequestCodeShown(phone.requestCode);
    });

    testWidgets('a payment cannot be recorded; the screen says why',
        (tester) async {
      final ahmad = await db(tester, () => insertCustomer(database.db));
      final service = await startService(tester);
      clock.advance(const Duration(days: 8));
      await db(tester, service.refresh);

      await pumpScreen(
        tester,
        RecordPaymentScreen(customerId: ahmad),
        service: service,
      );
      expect(find.byKey(const ValueKey('license-locked')), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-amount')), findsNothing);
      expect(
        find.text('New debts and payments are locked until Souqi is '
            'activated. Balances stay readable.'),
        findsOneWidget,
      );
    });

    testWidgets('nothing is printed or shared, and the refusal names the '
        'activation', (tester) async {
      final service = await startService(tester);
      clock.advance(const Duration(days: 8));
      await db(tester, service.refresh);
      await pumpScreen(tester, const Scaffold(), service: service);
      final output = containerOf(tester).read(invoiceOutputProvider);
      final invoice = sypInvoice().copyWith(id: 1);

      for (final attempt in <Future<void> Function()>[
        () => output.printInvoice(invoice),
        () => output.shareImage(invoice),
        () => output.sharePdfFile(invoice),
        () => output.saveImage(invoice),
        () => output.savePdf(invoice),
        () => output.sendToWhatsApp(
              invoice,
              package: whatsAppPackage,
              internationalPhone: '963944123456',
            ),
      ]) {
        Object? thrown;
        await tester.runAsync(() async {
          try {
            await attempt();
          } on Object catch (e) {
            thrown = e;
          }
        });
        expect(
          thrown,
          isA<OutputException>().having(
            (e) => e.failure,
            'failure',
            OutputFailure.licenseRequired,
          ),
        );
      }
      expect(bridge.printed, isEmpty);
      expect(bridge.shared, isEmpty);
      expect(bridge.saved, isEmpty);
      expect(bridge.whatsAppSends, isEmpty);
    });
  });

  group('the activation screen', () {
    testWidgets('a valid code activates: the app starts over on the home '
        'screen with the license in force', (tester) async {
      final service = await startService(tester);
      clock.advance(const Duration(days: 8));
      await db(tester, service.refresh);
      final code = await licenseFor(
        tester,
        features: [Feature.customers, Feature.barcode],
        shop: 'Al Noor Market',
      );

      await pumpApp(tester, service);
      expect(find.byType(LicenseScreen), findsOneWidget);
      final field = find.byKey(const ValueKey('license-code-field'));
      await reveal(tester, field);
      await tester.enterText(field, code);
      final activate = find.byKey(const ValueKey('license-activate'));
      await reveal(tester, activate);
      await tester.tap(activate);
      await settle(tester, 30);

      expect(service.status.isLicensed, isTrue);
      expect(restarts, [AppRestartNotice.activated]);
      // The gate lets the home screen through.
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('license-banner')), findsNothing);
      // `featureOn` answers by the license from now on.
      expect(featureOn(Feature.customers), isTrue);
      expect(featureOn(Feature.barcode), isTrue);
      expect(featureOn(Feature.debt), isFalse);
      expect(featureOn(Feature.vouchers), isFalse);
      expect(featureOn(Feature.backup), isFalse);
    });

    testWidgets('a wrong code is refused with its reason, and nothing '
        'changes', (tester) async {
      final service = await startService(tester);
      final other = FakeLicensePlatform(androidId: 'ffff0000eeee1111');
      final foreign = await licenseFor(tester, device: other);
      final good = await licenseFor(tester);
      final parsed = SignedCode.parse(good)!;
      final changed = SignedCode(
        payload: Uint8List.fromList(parsed.payload)..[16] ^= 0x01,
        signature: parsed.signature,
      ).text;
      final reset = await db(
        tester,
        () => developer.pinReset(device: phone.device, issuedAt: clock.now),
      );
      final expired = await db(
        tester,
        () => developer.license(
          device: phone.device,
          issuedAt: t0.subtract(const Duration(days: 60)),
          expiresAt: t0.subtract(const Duration(days: 30)),
        ),
      );

      await pumpScreen(tester, const LicenseScreen(), service: service);
      expect(
        find.byKey(const ValueKey('license-status-trial')),
        findsOneWidget,
      );
      final field = find.byKey(const ValueKey('license-code-field'));
      final activate = find.byKey(const ValueKey('license-activate'));

      Future<void> tryCode(String code, String message) async {
        await reveal(tester, field);
        await tester.enterText(field, code);
        await reveal(tester, activate);
        await tester.tap(activate);
        await settle(tester, 20);
        expect(find.text(message), findsOneWidget, reason: message);
        expect(service.status.mode, LicenseMode.trial);
      }

      await tryCode(
        foreign,
        'This code was issued for another phone. Send the request code '
            'shown above.',
      );
      await tryCode(
        changed,
        'This code is not valid. Make sure it was copied completely.',
      );
      await tryCode(expired, 'This code has already expired.');
      await tryCode(
        reset,
        'This is a PIN reset code, not an activation code. Enter it under '
            '"Forgot PIN?".',
      );
      await tryCode(
        'K7QM-29XD',
        'This is not a complete activation code. Paste the whole code.',
      );
      expect(restarts, isEmpty);

      // The right one, at last.
      await reveal(tester, field);
      await tester.enterText(field, good);
      await reveal(tester, activate);
      await tester.tap(activate);
      await settle(tester, 30);
      expect(
        find.byKey(const ValueKey('license-status-licensed')),
        findsOneWidget,
      );
      expect(find.text('Activated for Al Noor Market'), findsOneWidget);
      expect(find.text('Licensed to: Al Noor Market'), findsOneWidget);
      expect(find.text('Lifetime license'), findsOneWidget);
    });

    testWidgets('the request code can be copied, pasted into WhatsApp, and '
        'the activation code pasted or scanned back', (tester) async {
      final service = await startService(tester);
      final code = await licenseFor(tester);

      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          switch (call.method) {
            case 'Clipboard.setData':
              clipboard = (call.arguments as Map)['text'] as String?;
              return null;
            case 'Clipboard.getData':
              return {'text': clipboard};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await pumpScreen(
        tester,
        const LicenseScreen(),
        service: service,
        more: [
          licenseScannerProvider.overrideWithValue((_) async => code),
        ],
      );
      expectRequestCodeShown(phone.requestCode);

      // Copy.
      await tester.tap(find.byKey(const ValueKey('license-copy')));
      await settle(tester);
      expect(clipboard, phone.requestCode);
      expect(find.text('Request code copied'), findsOneWidget);

      // Send on WhatsApp: the request code as a message. With the developer's
      // number in the build (config/support.dart) the chat with THAT number
      // opens, the message already typed; while the constant is still a
      // placeholder the message is handed to WhatsApp and the shop picks the
      // chat. Whichever the build has is what is checked here.
      final number = developerWhatsAppNumber;
      final send = find.byKey(const ValueKey('license-whatsapp'));
      await tester.tap(send);
      await settle(tester);
      if (number.isNotEmpty) {
        final chat = bridge.chats.single;
        expect(chat.package, whatsAppPackage);
        expect(chat.phone, number);
        expect(chat.text, contains(phone.requestCode));
        expect(bridge.sharedTexts, isEmpty);
      } else {
        expect(bridge.chats, isEmpty);
        expect(bridge.sharedTexts.single.package, whatsAppPackage);
        expect(bridge.sharedTexts.single.text, contains(phone.requestCode));
      }

      // The chat cannot be opened: the message still goes to WhatsApp, which
      // asks for the chat.
      bridge.chatOpens = false;
      bridge.sharedTexts.clear();
      await tester.tap(send);
      await settle(tester);
      expect(bridge.sharedTexts.single.package, whatsAppPackage);
      expect(bridge.sharedTexts.single.text, contains(phone.requestCode));
      expect(find.textContaining('Could not open WhatsApp'), findsNothing);

      // No WhatsApp on the phone: the share sheet, and no chat is tried.
      bridge.installedWhatsApp = const [];
      final chatsSoFar = bridge.chats.length;
      await tester.tap(send);
      await settle(tester);
      expect(bridge.chats, hasLength(chatsSoFar));
      expect(bridge.sharedTexts.last.package, isNull);
      expect(bridge.sharedTexts.last.text, contains(phone.requestCode));

      // Paste puts what was copied into the field.
      clipboard = '  $code  ';
      final paste = find.byKey(const ValueKey('license-paste'));
      await reveal(tester, paste);
      await tester.tap(paste);
      await settle(tester);
      expect(
        tester
            .widget<TextField>(
                find.byKey(const ValueKey('license-code-field')))
            .controller!
            .text,
        code,
      );

      // Scan reads the QR code and activates.
      final scan = find.byKey(const ValueKey('license-scan'));
      await reveal(tester, scan);
      await tester.tap(scan);
      await settle(tester, 30);
      expect(service.status.isLicensed, isTrue);
      expect(restarts, [AppRestartNotice.activated]);
    });

    testWidgets('a phone that cannot be identified says so instead of '
        'showing a code', (tester) async {
      phone.broken = true;
      final service = await startService(tester);
      await pumpScreen(tester, const LicenseScreen(), service: service);
      expect(
        find.byKey(const ValueKey('license-request-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('license-copy')), findsNothing);
    });
  });

  group('the trial', () {
    testWidgets('shows on the home screen, with what is left',
        (tester) async {
      final service = await startService(tester);
      await act(tester, () => setInvoiceCounter(database.db, 12));
      clock.advance(const Duration(days: 2, hours: 1));
      await db(tester, service.refresh);

      await pumpApp(tester, service);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.text('Trial version — 5 days / 18 invoices left'),
        findsOneWidget,
      );
      // The banner is the way to the activation screen.
      await tester.tap(find.byKey(const ValueKey('license-banner')));
      await animated(tester);
      expect(find.byType(LicenseScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('license-trial-left')),
        findsOneWidget,
      );
    });

    testWidgets('a clock set back is said on the home screen',
        (tester) async {
      final service = await startService(tester);
      clock.advance(const Duration(days: 3));
      await db(tester, service.refresh);
      clock.now = t0.subtract(const Duration(days: 40));
      await db(tester, service.refresh);

      await pumpApp(tester, service);
      expect(
        find.byKey(const ValueKey('license-clock-warning')),
        findsOneWidget,
      );
      // Four days left, as before the date was changed.
      expect(
        find.text('Trial version — 4 days / 30 invoices left'),
        findsOneWidget,
      );
    });

    testWidgets('an invoice of the trial prints a small "trial version" '
        'line; a licensed one does not, and carries the license\'s shop '
        'name', (tester) async {
      await act(
        tester,
        () => SettingsRepository(database.db).setMany({
          SettingsKeys.shopName: 'My own name',
          SettingsKeys.headerText: 'Opposite the post office',
          SettingsKeys.invoiceLanguage: 'en',
        }),
      );
      final service = await startService(tester);

      Future<void> showInvoice() async {
        await pumpScreen(tester, const Scaffold(), service: service);
        final render = await db(
          tester,
          () => containerOf(tester).read(invoiceRenderContextProvider.future),
        );
        await pumpScreen(
          tester,
          Scaffold(
            body: SingleChildScrollView(
              child: InvoiceView(
                invoice: sypInvoice(),
                settings: render.settings,
                currencies: render.currencies,
                logo: render.logo,
              ),
            ),
          ),
          service: service,
          tall: true,
        );
      }

      // On the trial: the shop's own name, and the trial line.
      await showInvoice();
      expect(find.byKey(const ValueKey('invoice-trial-line')), findsOneWidget);
      expect(find.text('Trial version'), findsOneWidget);
      expect(find.text('My own name'), findsOneWidget);
      expect(find.text('Opposite the post office'), findsOneWidget);

      // Licensed: the license's name; the header text is still the shop's.
      final code = await licenseFor(tester, shop: 'Al Noor Market');
      await db(tester, () => service.activate(code));
      await showInvoice();
      expect(find.byKey(const ValueKey('invoice-trial-line')), findsNothing);
      expect(find.text('Al Noor Market'), findsOneWidget);
      expect(find.text('My own name'), findsNothing);
      expect(find.text('Opposite the post office'), findsOneWidget);
    });
  });

  group('a license that ends', () {
    testWidgets('is said on the home screen in its last two weeks, and '
        'not before', (tester) async {
      final service = await startService(tester);
      final code = await licenseFor(
        tester,
        expiresAt: t0.add(const Duration(days: 60)),
      );
      await db(tester, () => service.activate(code));

      await pumpApp(tester, service);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('license-banner')), findsNothing);

      clock.advance(const Duration(days: 50));
      await db(tester, service.refresh);
      await pumpApp(tester, service);
      expect(
        find.text('The license ends in 10 days. Ask the developer for a '
            'new activation code.'),
        findsOneWidget,
      );

      // And once it has ended, the app opens on the activation screen.
      clock.advance(const Duration(days: 11));
      await db(tester, service.refresh);
      await pumpApp(tester, service);
      expect(find.byType(LicenseScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('license-status-unlicensed')),
        findsOneWidget,
      );
      expect(find.text('Licensed to: Al Noor Market'), findsOneWidget);
    });
  });

  group('the shop name', () {
    testWidgets('is typed in the invoice settings before activation, and '
        'only shown after it', (tester) async {
      final service = await startService(tester);
      await pumpScreen(
        tester,
        const InvoiceSettingsScreen(),
        service: service,
        tall: true,
      );
      expect(
        find.byKey(const ValueKey('shop-name'), skipOffstage: false),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('shop-name-licensed'), skipOffstage: false),
        findsNothing,
      );

      final code = await licenseFor(tester, shop: 'Al Noor Market');
      await db(tester, () => service.activate(code));
      await pumpScreen(
        tester,
        const InvoiceSettingsScreen(),
        service: service,
        tall: true,
      );
      expect(
        find.byKey(const ValueKey('shop-name'), skipOffstage: false),
        findsNothing,
      );
      final shown =
          find.byKey(const ValueKey('shop-name-licensed'), skipOffstage: false);
      expect(shown, findsOneWidget);
      expect(
        find.descendant(
          of: shown,
          matching: find.text('Al Noor Market', skipOffstage: false),
        ),
        findsOneWidget,
      );
      // The header text is still the shop's to write.
      expect(
        await db(
          tester,
          () => SettingsRepository(database.db)
              .getString(SettingsKeys.shopName),
        ),
        'Al Noor Market',
      );
    });
  });

  group('the feature mask turns modules on and off', () {
    /// What shows each feature on a screen: there with everything on, gone
    /// with that one feature off.
    final home = <Feature, List<Finder>>{
      Feature.customers: [
        find.text('Customers'),
        find.byType(QuickSearchField),
      ],
      Feature.accounts: [find.text('Due for renewal')],
      Feature.vouchers: [find.text('Card stock')],
      Feature.debt: [find.byType(HomeDebtsCard)],
    };
    final settings = <Feature, List<Finder>>{
      Feature.accounts: [find.text('Customers & renewals')],
      Feature.multiCurrency: [find.text('Currencies & exchange rates')],
      Feature.backup: [
        find.byKey(const ValueKey('setting-backup')),
        find.text('Backup'),
      ],
      Feature.debt: [
        find.text('Debts'),
        find.byKey(const ValueKey('setting-opening-balances')),
        find.byKey(const ValueKey('setting-debt-report')),
      ],
      Feature.dailyReport: [
        find.byKey(const ValueKey('setting-debt-report')),
      ],
    };

    Future<void> shopOfCards(WidgetTester tester) => act(
          tester,
          () => SettingsRepository(database.db)
              .setString(SettingsKeys.shopType, 'CARDS'),
        );

    testWidgets('home: every tile and card of a feature goes with it',
        (tester) async {
      await shopOfCards(tester);
      await pumpScreen(tester, const HomeScreen(), tall: true);
      for (final finders in home.values) {
        for (final finder in finders) {
          // (A cards shop has "Due for renewal" twice: the tile and the
          // card above the tiles.)
          expect(finder, findsWidgets);
        }
      }
      for (final entry in home.entries) {
        FeatureGate.applyWithout([entry.key]);
        await pumpScreen(tester, const HomeScreen(), tall: true);
        for (final finder in entry.value) {
          // (No `$finder` in the reason: a finder that matched in an
          // earlier tree prints the elements of that tree.)
          expect(finder, findsNothing, reason: 'with ${entry.key.name} off');
        }
        expect(tester.takeException(), isNull, reason: entry.key.name);
      }
      // Customers off takes accounts and the ledger with it.
      FeatureGate.applyWithout([Feature.customers]);
      await pumpScreen(tester, const HomeScreen(), tall: true);
      expect(find.text('Due for renewal'), findsNothing);
      expect(find.byType(HomeDebtsCard), findsNothing);
      // What needs no license feature is always there.
      for (final label in ['Sale', 'Products', 'Archive', 'Statistics']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('settings: every section of a feature goes with it',
        (tester) async {
      await pumpScreen(tester, const SettingsScreen(), tall: true);
      for (final finders in settings.values) {
        for (final finder in finders) {
          expect(finder, findsOneWidget);
        }
      }
      for (final entry in settings.entries) {
        FeatureGate.applyWithout([entry.key]);
        await pumpScreen(tester, const SettingsScreen(), tall: true);
        for (final finder in entry.value) {
          // (No `$finder` in the reason: a finder that matched in an
          // earlier tree prints the elements of that tree.)
          expect(finder, findsNothing, reason: 'with ${entry.key.name} off');
        }
        expect(tester.takeException(), isNull, reason: entry.key.name);
      }
      // The daily report alone off: the rest of the ledger's settings stay.
      FeatureGate.applyWithout([Feature.dailyReport]);
      await pumpScreen(tester, const SettingsScreen(), tall: true);
      expect(find.text('Debts'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('setting-opening-balances')),
        findsOneWidget,
      );
      // The way to the activation screen is always there.
      expect(find.byKey(const ValueKey('setting-license')), findsOneWidget);
    });

    testWidgets('sale: the scanner, the credit button and the other '
        'currencies', (tester) async {
      await db(tester, () => insertProduct(database.db, name: 'Sugar'));

      Future<void> openMenu() async {
        await tester.tap(find.byType(PopupMenuButton<void>));
        await animated(tester);
      }

      await pumpScreen(tester, const SaleScreen());
      expect(find.byKey(const ValueKey('sale-scan')), findsOneWidget);
      await openMenu();
      expect(find.text('Secondary total'), findsOneWidget);

      FeatureGate.applyWithout([Feature.barcode, Feature.multiCurrency]);
      await pumpScreen(tester, const SaleScreen());
      expect(find.byKey(const ValueKey('sale-scan')), findsNothing);
      await openMenu();
      expect(find.text('Secondary total'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('product form: the barcode and the price currency',
        (tester) async {
      Finder currency() => find.text('Price currency', skipOffstage: false);
      Finder barcode() =>
          find.byKey(const ValueKey('product-barcode'), skipOffstage: false);

      await pumpScreen(tester, const ProductFormScreen(), tall: true);
      expect(barcode(), findsOneWidget);
      expect(currency(), findsOneWidget);

      FeatureGate.applyWithout([Feature.barcode, Feature.multiCurrency]);
      await pumpScreen(tester, const ProductFormScreen(), tall: true);
      expect(barcode(), findsNothing);
      expect(currency(), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the activation screen lists what the license includes',
        (tester) async {
      final service = await startService(tester);
      final code = await licenseFor(
        tester,
        features: [Feature.debt, Feature.barcode],
        expiresAt: DateTime.utc(2027, 12, 31, 23, 59, 59),
      );
      await db(tester, () => service.activate(code));
      await pumpScreen(tester, const LicenseScreen(), service: service);
      for (final on in ['debt', 'customers', 'barcode']) {
        expect(find.byKey(ValueKey('license-feature-$on')), findsOneWidget);
      }
      for (final off in ['vouchers', 'backup', 'multiCurrency', 'accounts']) {
        expect(find.byKey(ValueKey('license-feature-$off')), findsNothing);
      }
      expect(find.byKey(const ValueKey('license-validity')), findsOneWidget);
      expect(find.text('Lifetime license'), findsNothing);
    });
  });

  group('"Forgot PIN?" with the developer\'s reset code', () {
    testWidgets('shows the request code, and a reset code sets a new PIN — '
        'once', (tester) async {
      final service = await startService(tester);
      final pins = PinRepository(SettingsRepository(database.db));
      await db(tester, () => pins.set('1234'));
      final code = await db(
        tester,
        () => developer.pinReset(device: phone.device, issuedAt: clock.now),
      );

      Future<void> openDialog() async {
        await pumpScreen(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) => const PinRecoveryDialog(),
                  ),
                  child: const Text('forgot'),
                ),
              ),
            ),
          ),
          service: service,
        );
        await tester.tap(find.text('forgot'));
        await animated(tester);
      }

      await openDialog();
      // The request code the shop sends to the developer.
      expect(find.text(phone.requestCode), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('recovery-field')),
        code,
      );
      await tester.tap(find.byKey(const ValueKey('recovery-ok')));
      await settle(tester, 40);
      // The code was accepted: the "new PIN" dialog is up.
      expect(find.text('This code is not valid'), findsNothing);
      expect(await db(tester, () => service.checkPinReset(code)),
          PinResetCheck.ok, reason: 'not used until the new PIN is saved');

      // Saving the new PIN is what uses the code up.
      final recovery = await tester.runAsync(
        () => pins.resetWithSignedCode(
          code: code,
          newPin: '5678',
          authority: service.pinReset,
        ),
      );
      expect(recovery, isNotNull);

      // A second time, from the dialog: refused.
      await openDialog();
      await tester.enterText(
        find.byKey(const ValueKey('recovery-field')),
        code,
      );
      await tester.tap(find.byKey(const ValueKey('recovery-ok')));
      await settle(tester, 40);
      expect(find.text('This code is not valid'), findsOneWidget);
      expect(await db(tester, () => pins.verify('5678')), isA<PinCorrect>());
    });
  });
}
