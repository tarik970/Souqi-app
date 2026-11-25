import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/platform/native_bridge.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/core/vouchers/code_import.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/invoice_repository.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/data/repositories/voucher_repository.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/domain/models/voucher.dart';
import 'package:souqi/features/archive/invoice_detail_screen.dart';
import 'package:souqi/features/home/home_screen.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/products/product_form_screen.dart';
import 'package:souqi/features/products/products_screen.dart';
import 'package:souqi/features/sale/sale_invoice_screen.dart';
import 'package:souqi/features/sale/sale_screen.dart';
import 'package:souqi/features/security/audit_log_screen.dart';
import 'package:souqi/features/settings/settings_screen.dart';
import 'package:souqi/features/stats/stats_screen.dart';
import 'package:souqi/features/vouchers/add_batch_screen.dart';
import 'package:souqi/features/vouchers/card_stock_screen.dart';
import 'package:souqi/features/vouchers/code_scan_screen.dart';
import 'package:souqi/features/vouchers/expired_codes_screen.dart';
import 'package:souqi/features/vouchers/product_stock_screen.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// Prepaid card codes, driven through the real screens on a real database:
/// the product switch, loading a batch, the stock shown wherever the product
/// is, selling against the stock, and everything behind the PIN — reprint,
/// reveal, void, return, delete, lookup, the audit log.
///
/// One rule is checked again and again along the way: a code is never on
/// screen in the clear unless the PIN was just entered to show it.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    // A tap that lands on nothing must fail the test, not pass it vacuously.
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  const pin = '2580';
  const codeA = '1111222233334444';
  const codeB = '5555666677778888';

  late AppDatabase database;
  late FakeNativeBridge bridge;
  late InMemoryKeyStore keyStore;
  late CodeCipher cipher;
  late VoucherRepository vouchers;
  late Directory outputDir;
  late int cardId; // "Card 5000", SERVICE, code 301, sold from code stock

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Long enough for a page, a sheet or a dialog to finish sliding in or out.
  Future<void> animated(WidgetTester tester) async {
    await settle(tester, 28);
    for (var i = 0; i < 20 && tester.binding.transientCallbackCount > 0; i++) {
      await settle(tester, 4);
    }
  }

  /// Waits on an effect that takes a variable amount of real time (hashing
  /// a PIN, rasterising an invoice) instead of on a fixed number of frames.
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

  Future<int> insertCard(
    String name, {
    required String code,
    int price = 5000,
    int? threshold,
    bool favorite = true,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return database.db.insert('products', {
      'name': name,
      'name_norm': name.toLowerCase(),
      'code': code,
      'kind': 'SERVICE',
      'price_minor': price,
      'currency_code': 'SYP',
      'is_favorite': favorite ? 1 : 0,
      'sold_from_code_stock': 1,
      'low_stock_threshold': threshold,
      'created_at': now,
      'updated_at': now,
    });
  }

  setUp(() async {
    database = await openTestDb();
    bridge = FakeNativeBridge();
    keyStore = InMemoryKeyStore();
    cipher = CodeCipher(keyStore);
    vouchers = VoucherRepository(database.db, cipher);
    outputDir = await Directory.systemTemp.createTemp('souqi_voucher_test');
    cardId = await insertCard('Card 5000', code: '301', threshold: 2);
    await insertProduct(database.db, name: 'Sugar', code: '101');
    await database.db.insert('settings', {
      'key': SettingsKeys.printerMac,
      'value': 'AA:BB:CC:DD:EE:FF',
      'updated_at': 0,
    });
  });

  tearDown(() async {
    await database.close();
    if (outputDir.existsSync()) outputDir.deleteSync(recursive: true);
  });

  /// Loads [codes] as one batch of [productId], the way the screen does.
  Future<ImportReport> load(
    WidgetTester tester,
    List<String> codes, {
    int? productId,
    DateTime? lastDay,
    int? cost,
  }) =>
      db(
        tester,
        () => vouchers.addBatch(
          productId: productId ?? cardId,
          parsed: parseCodeList(
            codes.join('\n'),
            columns: CodeColumns.codeOnly,
          ),
          expiryAt: lastDay == null ? null : expiryFromDate(lastDay),
          costPerCardMinor: cost,
          costCurrencyCode: cost == null ? null : 'SYP',
        ),
      );

  Future<void> setPin(WidgetTester tester) => db(tester, () async {
        await PinRepository(SettingsRepository(database.db)).set(pin);
        return true;
      });

  /// A saved sale of [qty] cards, through the real repository.
  Future<Invoice> sell(WidgetTester tester, {int qty = 1, String? customer}) =>
      db(tester, () {
        final syp = Currency(
          code: 'SYP',
          nameAr: 'SYP',
          nameEn: 'SYP',
          decimalPlaces: 0,
          rate: RateFraction.one,
          rateUpdatedAt: DateTime.utc(2026),
        );
        return InvoiceRepository(database.db, codeCipher: cipher).save(
          Invoice.fromCart(
            cart: const Cart().add(CartLine(
              productId: cardId,
              name: 'Card 5000',
              kind: ProductKind.service,
              unitPriceMinor: 5000,
              priceCurrencyCode: 'SYP',
              qtyThousandths: qty * 1000,
              codeStock: true,
            )),
            ctx: CurrencyContext.of([syp], baseCode: 'SYP'),
            createdAt: DateTime.now().toUtc(),
            customerName: customer,
          ),
        );
      });

  Future<List<Map<String, Object?>>> rows(
    WidgetTester tester,
    String table, {
    String? orderBy,
  }) =>
      db(tester, () => database.db.query(table, orderBy: orderBy ?? 'id'));

  /// What the audit log holds, oldest first — without the "codes loaded"
  /// lines, which the fixture's own [load] writes.
  Future<List<Map<String, Object?>>> audit(WidgetTester tester) async => [
        for (final row in await rows(tester, 'audit_log'))
          if (row['action'] != 'CODE_IMPORT') row,
      ];

  Future<void> pump(WidgetTester tester, Widget home) async {
    // A phone-shaped viewport, 600×1200 logical pixels.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider
              .overrideWith(() => AppLocaleNotifier(const Locale('en'))),
          nativeBridgeProvider.overrideWithValue(bridge),
          secretKeyStoreProvider.overrideWithValue(keyStore),
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

  final pinDialog = find.byKey(const ValueKey('pin-entry-dialog'));
  final pinSetDialog = find.byKey(const ValueKey('pin-set-dialog'));

  /// Types [value] into the PIN dialog and waits for its verdict.
  Future<void> enterPin(WidgetTester tester, String value) async {
    expect(pinDialog, findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('pin-entry-field')), value);
    await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
    if (value == pin) {
      await until(tester, () => pinDialog.evaluate().isEmpty);
      await animated(tester);
    } else {
      await until(
        tester,
        () => find.textContaining('Wrong PIN').evaluate().isNotEmpty ||
            find.textContaining('Too many').evaluate().isNotEmpty,
      );
    }
  }

  /// Chooses [pin] in the "choose a PIN" dialog.
  Future<void> choosePin(WidgetTester tester) async {
    expect(pinSetDialog, findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pin-new-field')), pin);
    await tester.enterText(find.byKey(const ValueKey('pin-again-field')), pin);
    await tester.tap(find.byKey(const ValueKey('pin-set-save')));
    await until(tester, () => pinSetDialog.evaluate().isEmpty);
    await animated(tester);
  }

  /// Every piece of text currently built, in one string — to prove a code
  /// is nowhere on screen.
  String allText(WidgetTester tester) => [
        for (final widget in tester.widgetList<Text>(find.byType(Text)))
          widget.data ?? widget.textSpan?.toPlainText() ?? '',
        for (final field
            in tester.widgetList<EditableText>(find.byType(EditableText)))
          field.controller.text,
      ].join('|');

  void expectNotOnScreen(WidgetTester tester, String code) {
    final text = allText(tester);
    expect(text.contains(code), isFalse, reason: 'the code is on screen');
    // Nor grouped in fours.
    final grouped = [
      for (var i = 0; i < code.length; i += 4) code.substring(i, i + 4),
    ].join(' ');
    expect(text.contains(grouped), isFalse, reason: 'grouped: on screen');
  }

  Future<void> openCodeMenu(WidgetTester tester, int codeId, String action) async {
    final menu = find.byKey(ValueKey('code-menu-$codeId'));
    await tester.ensureVisible(menu);
    await settle(tester, 3);
    await tester.tap(menu);
    await animated(tester);
    await tester.tap(find.byKey(ValueKey('code-action-$action')));
    await animated(tester);
  }

  // ------------------------------------------------------------------------

  group('product form', () {
    final codeStock = find.byKey(const ValueKey('product-code-stock'));
    final threshold = find.byKey(const ValueKey('product-low-stock'));

    testWidgets('the switch is offered for card / service products only',
        (tester) async {
      await pump(tester, const ProductFormScreen());
      expect(codeStock, findsNothing, reason: 'GOODS is the default kind');

      await tester.tap(find.text('Card / service'));
      await settle(tester);
      expect(codeStock, findsOneWidget);
      expect(threshold, findsNothing, reason: 'only once the switch is on');

      await tester.tap(codeStock);
      await settle(tester);
      expect(threshold, findsOneWidget);
    });

    testWidgets('the switch and the threshold are saved', (tester) async {
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProductFormScreen(),
                ),
              ),
              child: const Text('open form'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open form'));
      await animated(tester);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Name'), 'Card 10000');
      await tester.tap(find.text('Card / service'));
      await settle(tester);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Price'), '10000');
      await tester.tap(codeStock);
      await settle(tester);

      // Not a number: the form says so and saves nothing.
      await tester.enterText(threshold, 'few');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await settle(tester);
      // (Just above Save, possibly above the fold now.)
      expect(
        find.text('Invalid number', skipOffstage: false),
        findsOneWidget,
      );

      await tester.enterText(threshold, '٣'); // Arabic-Indic 3
      await tester.tap(find.text('Save'));
      await animated(tester);

      final saved = (await rows(tester, 'products'))
          .firstWhere((row) => row['name'] == 'Card 10000');
      expect(saved['sold_from_code_stock'], 1);
      expect(saved['low_stock_threshold'], 3);
      expect(saved['kind'], 'SERVICE');
    });

    testWidgets('an existing card product opens with its values and a way '
        'to its stock', (tester) async {
      final product = await db(tester, () async {
        final row = (await database.db
                .query('products', where: 'id = ?', whereArgs: [cardId]))
            .single;
        return Product.fromMap(row);
      });
      await pump(tester, ProductFormScreen(product: product));
      expect(tester.widget<SwitchListTile>(codeStock).value, isTrue);
      expect(find.widgetWithText(TextFormField, '2'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('product-open-stock')), findsOneWidget);
    });
  });

  group('loading a batch', () {
    Future<void> openLoader(WidgetTester tester) async {
      await pump(tester, ProductStockScreen(productId: cardId));
      expect(find.byKey(const ValueKey('batch-empty')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('batch-add')));
      await animated(tester);
      expect(find.byType(AddBatchScreen), findsOneWidget);
    }

    final summary = find.byKey(const ValueKey('import-summary'));
    final save = find.byKey(const ValueKey('batch-save'));

    /// The report line, or null while there is nothing to report on.
    String? summaryText(WidgetTester tester) => summary.evaluate().isEmpty
        ? null
        : tester.widget<Text>(summary).data;

    testWidgets(
        'paste: column choice, masked preview, report — and a PIN first',
        (tester) async {
      await openLoader(tester);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(
        find.byKey(const ValueKey('paste-field')),
        'SN1,$codeA\nSN2,$codeB\n\nSN3,1111-2222-3333-4444',
      );
      await tester.tap(find.byKey(const ValueKey('columns-serialThenCode')));
      await animated(tester);

      // The preview shows what was understood, with the code masked.
      Text text(String key) => tester.widget<Text>(find.byKey(ValueKey(key)));
      expect(text('preview-code-0').data, '•••• •••• 4444');
      expect(text('preview-serial-0').data, 'SN1');
      expect(text('preview-code-1').data, '•••• •••• 8888');
      expect(find.byKey(const ValueKey('preview-code-2')), findsNothing);
      expect(
        tester.widget<Text>(summary).data,
        '2 to add, 1 duplicate skipped, 1 empty line',
      );

      // No PIN yet: one must be chosen before codes go into stock.
      await tester.ensureVisible(save);
      await tester.tap(save);
      await animated(tester);
      await choosePin(tester);
      await until(tester, () => find.byType(AddBatchScreen).evaluate().isEmpty);

      expect(
        find.text('2 added, 1 duplicate skipped, 1 empty line'),
        findsOneWidget,
      );
      // Back on the product's stock: two available, one batch.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('count-available'))).data,
        '2',
      );
      expect(find.textContaining('2 cards'), findsOneWidget);
      expectNotOnScreen(tester, codeA);

      final codes = await rows(tester, 'voucher_codes');
      expect([for (final c in codes) c['serial']], ['SN1', 'SN2']);
      expect(await db(tester, () => cipher.decrypt(
          codes.first['code_cipher'] as List<int>)), codeA);
      final log = await rows(tester, 'audit_log');
      expect([for (final l in log) l['action']], ['PIN_SET', 'CODE_IMPORT']);
    });

    testWidgets('codes the product already has are counted before saving',
        (tester) async {
      await load(tester, [codeA]);
      await setPin(tester);
      await pump(tester, ProductStockScreen(productId: cardId));
      await tester.tap(find.byKey(const ValueKey('batch-add')));
      await animated(tester);

      await tester.enterText(
          find.byKey(const ValueKey('paste-field')), '1111 2222 3333 4444');
      await until(
        tester,
        () => summaryText(tester) == '0 to add, 1 duplicate skipped',
      );
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('Nothing new to add'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('paste-field')),
          '1111 2222 3333 4444\n$codeB');
      await until(
        tester,
        () => summaryText(tester) == '1 to add, 1 duplicate skipped',
      );
      // A PIN exists already: saving does not ask for it.
      await tester.ensureVisible(save);
      await tester.tap(save);
      await until(tester, () => find.byType(AddBatchScreen).evaluate().isEmpty);
      expect(pinDialog, findsNothing);
      expect(pinSetDialog, findsNothing);
      expect(await rows(tester, 'voucher_codes'), hasLength(2));
    });

    testWidgets('a .csv file, with its heading line', (tester) async {
      await setPin(tester);
      bridge.fileToPick = const PickedTextFile(
        name: 'cards.csv',
        content: 'Serial,Code\r\nA1,7777000011112222\r\nA2,7777000011113333\r\n',
      );
      await openLoader(tester);
      await tester.tap(find.text('File'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('pick-file')));
      await settle(tester);
      expect(find.textContaining('cards.csv'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('columns-serialThenCode')));
      await animated(tester);
      expect(
        tester.widget<Text>(summary).data,
        '2 to add, heading line left out',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('preview-serial-0'))).data,
        'A1',
      );
      // The file's text is never shown — only its masked preview.
      expectNotOnScreen(tester, '7777000011112222');

      await tester.ensureVisible(save);
      await tester.tap(save);
      await until(tester, () => find.byType(AddBatchScreen).evaluate().isEmpty);
      final codes = await rows(tester, 'voucher_codes');
      expect([for (final c in codes) c['serial']], ['A1', 'A2']);
      expect((await rows(tester, 'audit_log')).last['details'],
          contains('"source":"file"'));
    });

    testWidgets('a file that cannot be read says so', (tester) async {
      await openLoader(tester);
      await tester.tap(find.text('File'));
      await settle(tester);
      // The picker returns nothing: the user backed out.
      await tester.tap(find.byKey(const ValueKey('pick-file')));
      await settle(tester);
      expect(find.byKey(const ValueKey('file-error')), findsNothing);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
    });

    testWidgets('expiry date and cost per card are saved with the batch',
        (tester) async {
      await setPin(tester);
      await openLoader(tester);
      await tester.enterText(find.byKey(const ValueKey('paste-field')), codeA);
      await tester.tap(find.byKey(const ValueKey('batch-expiry')));
      await animated(tester);
      await tester.tap(find.text('OK'));
      await animated(tester);
      await tester.enterText(find.byKey(const ValueKey('batch-cost')), '4500');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await until(tester, () => find.byType(AddBatchScreen).evaluate().isEmpty);

      final batch = (await rows(tester, 'voucher_batches')).single;
      expect(batch['cost_per_card_minor'], 4500);
      expect(batch['cost_currency_code'], 'SYP');
      // Today was picked: sellable through the end of today.
      final today = DateTime.now();
      expect(
        batch['expiry_at'],
        expiryFromDate(DateTime(today.year, today.month, today.day))
            .toUtc()
            .millisecondsSinceEpoch,
      );
      expect(find.textContaining('Cost 4,500'), findsOneWidget);
      expect(find.textContaining('Valid until'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('count-available'))).data,
        '1',
      );
    });
  });

  group('scanned cards', () {
    test('each card counts once, however often it is scanned', () {
      final collector = ScanCollector();
      expect(collector.add(codeA), ScanOutcome.added);
      expect(collector.add(codeB), ScanOutcome.added);
      expect(collector.add(codeA), ScanOutcome.duplicate);
      expect(collector.add('1111-2222-3333-4444'), ScanOutcome.duplicate);
      expect(collector.add('  '), ScanOutcome.ignored);
      expect(collector.add(null), ScanOutcome.ignored);
      expect(collector.count, 2);
      expect(collector.codes, [codeA, codeB]);
      // Only the masked form is ever shown.
      expect(collector.lastMasked, '•••• •••• 8888');
    });

    test('carries on from the cards scanned before', () {
      final collector = ScanCollector([codeA]);
      expect(collector.add(codeA), ScanOutcome.duplicate);
      expect(collector.add(codeB), ScanOutcome.added);
      expect(collector.count, 2);
    });
  });

  group('the stock is shown wherever the product is', () {
    testWidgets('products list', (tester) async {
      await load(tester, [codeA, codeB, '9999000011112222']);
      await pump(tester, const ProductsScreen());
      expect(
        tester.widget<Text>(find.byKey(ValueKey('product-stock-$cardId'))).data,
        'In stock: 3',
      );
      // Sugar is not sold from code stock: no stock line.
      expect(find.textContaining('In stock'), findsOneWidget);
    });

    testWidgets('products list, nothing loaded', (tester) async {
      await pump(tester, const ProductsScreen());
      expect(
        tester.widget<Text>(find.byKey(ValueKey('product-stock-$cardId'))).data,
        'Out of stock',
      );
    });

    testWidgets('favorites bar and sale search', (tester) async {
      await load(tester, [codeA, codeB]);
      await pump(tester, const SaleScreen());
      final pill = find.byKey(ValueKey('favorite-stock-$cardId'));
      expect(
        tester.widget<Text>(
          find.descendant(of: pill, matching: find.byType(Text)),
        ).data,
        '2',
      );

      await tester.enterText(
          find.byKey(const ValueKey('sale-search-field')), 'card');
      await animated(tester);
      expect(find.textContaining('In stock: 2'), findsOneWidget);
    });

    testWidgets('home screen badge counts products that are low or out',
        (tester) async {
      await pump(tester, const HomeScreen());
      final badge = find.byKey(const ValueKey('home-badge-cards'));
      expect(badge, findsOneWidget, reason: 'nothing loaded: out of stock');

      await load(tester, [codeA, codeB]); // at the threshold of 2: low
      await pump(tester, const HomeScreen());
      expect(badge, findsOneWidget);

      await load(tester, ['9999000011112222']); // 3 > 2
      await pump(tester, const HomeScreen());
      expect(badge, findsNothing);
      expect(find.byKey(const ValueKey('home-nav-cards')), findsOneWidget);
    });
  });

  group('selling', () {
    Finder addButton() => find.widgetWithText(FilledButton, 'Add');

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(FilledButton, 'Card 5000'));
      await animated(tester);
    }

    testWidgets('the quantity cannot exceed the stock', (tester) async {
      await load(tester, [codeA, codeB]);
      await pump(tester, const SaleScreen());
      await openSheet(tester);

      final stock = find.byKey(const ValueKey('qty-stock'));
      expect(tester.widget<Text>(stock).data, 'In stock: 2');
      expect(tester.widget<FilledButton>(addButton()).onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('qty-preset-3000')));
      await settle(tester);
      expect(tester.widget<Text>(stock).data, 'Only 2 in stock');
      expect(tester.widget<FilledButton>(addButton()).onPressed, isNull);

      await tester.tap(find.byKey(const ValueKey('qty-preset-2000')));
      await settle(tester);
      expect(tester.widget<FilledButton>(addButton()).onPressed, isNotNull);
      // Whole cards only: the decimal key is off for this product.
      expect(
        tester
            .widget<OutlinedButton>(
                find.byKey(const ValueKey('keypad-separator')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('what is already in the cart counts against the stock',
        (tester) async {
      await load(tester, [codeA, codeB]);
      await pump(tester, const SaleScreen());
      await openSheet(tester);
      await tester.tap(addButton());
      await animated(tester);

      await openSheet(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('qty-stock'))).data,
        'In stock: 1',
      );
      await tester.tap(find.byKey(const ValueKey('qty-preset-2000')));
      await settle(tester);
      expect(tester.widget<FilledButton>(addButton()).onPressed, isNull);
    });

    testWidgets('out of stock: the sheet says so and adds nothing',
        (tester) async {
      await pump(tester, const SaleScreen());
      await openSheet(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('qty-stock'))).data,
        'Out of stock',
      );
      expect(tester.widget<FilledButton>(addButton()).onPressed, isNull);
    });

    testWidgets('a code typed with Enter is refused when the stock is used up',
        (tester) async {
      await load(tester, [codeA]);
      await pump(tester, const SaleScreen());
      final search = find.byKey(const ValueKey('sale-search-field'));

      await tester.enterText(search, '301');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await animated(tester);
      expect(find.byKey(const ValueKey('cart-line-detail-1')), findsOneWidget);

      await tester.enterText(search, '301');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await animated(tester);
      expect(find.text('"Card 5000": 2 wanted, 1 in stock'), findsOneWidget);
      // The typed code stays in the box next to the message. Cleared, the
      // cart shows again — still with one card.
      await tester.enterText(search, '');
      await animated(tester);
      expect(find.textContaining('1 ×'), findsOneWidget, reason: 'still 1');
    });

    testWidgets('stock sold from under an open cart blocks Save, with a reason',
        (tester) async {
      await load(tester, [codeA, codeB]);
      await pump(tester, const SaleScreen());
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('qty-preset-2000')));
      await settle(tester);
      await tester.tap(addButton());
      await animated(tester);
      final save = find.byKey(const ValueKey('sale-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

      // Another till sells one of the two meanwhile. This screen still
      // believes there are two, so Save is pressed — and the save itself,
      // in its transaction, refuses.
      await sell(tester);
      await tester.tap(save);
      await animated(tester);
      expect(find.text('"Card 5000": 2 wanted, 1 in stock'), findsWidgets);
      expect(await rows(tester, 'invoices'), hasLength(1),
          reason: 'only the other till\'s sale');

      // The counts were read again: now the screen knows, and says why
      // there is nothing to press.
      await animated(tester);
      expect(find.byKey(const ValueKey('code-stock-short')), findsOneWidget);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(find.text('Only 1 in stock'), findsOneWidget);
    });

    testWidgets(
        'saving takes the codes; the screen shows them masked; a second '
        'print is a copy behind the PIN', (tester) async {
      await load(tester, [codeA, codeB, '9999000011112222']);
      await setPin(tester);
      await pump(tester, const SaleScreen());
      await openSheet(tester);
      await tester.tap(find.byKey(const ValueKey('qty-preset-2000')));
      await settle(tester);
      await tester.tap(addButton());
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('sale-save')));
      await until(
          tester, () => find.byType(SaleInvoiceScreen).evaluate().isNotEmpty);
      await animated(tester);

      // Two codes left the stock, the oldest first.
      final codes = await rows(tester, 'voucher_codes');
      expect([for (final c in codes) c['status']],
          ['SOLD', 'SOLD', 'AVAILABLE']);

      // On screen: the "Card codes" section and the invoice preview, both
      // masked. Neither code is anywhere in the widget tree.
      expect(find.byKey(const ValueKey('invoice-codes')), findsOneWidget);
      expect(find.text('•••• •••• 4444'), findsOneWidget);
      expect(find.text('•••• •••• 8888'), findsOneWidget);
      expectNotOnScreen(tester, codeA);
      expectNotOnScreen(tester, codeB);
      final preview = [
        for (final text in tester.widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('saved-invoice-view')),
          matching: find.byType(Text),
          skipOffstage: false,
        )))
          text.data ?? '',
      ].join();
      expect(preview, contains('••••••••4444'));
      expect(preview, contains('••••••••8888'));
      expect(preview.contains('1111'), isFalse);

      // The first print is the original: no PIN, no copy.
      final print = find.byKey(const ValueKey('invoice-primary-print'));
      await tester.tap(print);
      await until(tester, () => bridge.printed.length == 1);
      expect(pinDialog, findsNothing);
      expect(await audit(tester), isEmpty);

      // The second is a reprint of cash: the PIN, a COPY mark, a log line.
      await tester.tap(print);
      await animated(tester);
      await enterPin(tester, '0000');
      expect(find.textContaining('Wrong PIN. 4 attempts left'), findsOneWidget);
      expect(bridge.printed, hasLength(1));
      await enterPin(tester, pin);
      await until(tester, () => bridge.printed.length == 2);
      // The copy carries its mark: more rows of raster than the original.
      expect(bridge.printed[1].bytes.length,
          greaterThan(bridge.printed[0].bytes.length));
      final log = (await audit(tester)).single;
      expect(log['action'], 'INVOICE_REPRINT');
      expect(log['product_name'], 'Card 5000');
      expect(log['details'], contains('"count":2'));
      expect(log['details'], contains('"output":"print"'));

      // Backing out of the PIN prints nothing and logs nothing.
      await tester.tap(print);
      await animated(tester);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(bridge.printed, hasLength(2));
      expect(await audit(tester), hasLength(1));
    });

    testWidgets('an invoice without cards prints again with no PIN',
        (tester) async {
      await setPin(tester);
      await pump(tester, const SaleScreen());
      await tester.enterText(
          find.byKey(const ValueKey('sale-search-field')), '101');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('sale-save')));
      await until(
          tester, () => find.byType(SaleInvoiceScreen).evaluate().isNotEmpty);
      await animated(tester);
      expect(find.byKey(const ValueKey('invoice-codes')), findsNothing);

      final print = find.byKey(const ValueKey('invoice-primary-print'));
      await tester.tap(print);
      await until(tester, () => bridge.printed.length == 1);
      await tester.tap(print);
      await until(tester, () => bridge.printed.length == 2);
      expect(pinDialog, findsNothing);
    });
  });

  group('an archived invoice with codes', () {
    late Invoice invoice;
    late int codeId;

    Future<void> open(WidgetTester tester) async {
      await load(tester, [codeA]);
      await setPin(tester);
      invoice = await sell(tester, customer: 'Ahmad');
      codeId = (await rows(tester, 'voucher_codes')).single['id']! as int;
      await pump(tester, InvoiceDetailScreen(invoiceId: invoice.id!));
      await animated(tester);
    }

    testWidgets('reprinting needs the PIN and is logged', (tester) async {
      await open(tester);
      expectNotOnScreen(tester, codeA);
      expect(find.text('•••• •••• 4444'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('invoice-primary-print')));
      await animated(tester);
      expect(find.textContaining('This invoice carries card codes'),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(bridge.printed, isEmpty);

      await tester.tap(find.byKey(const ValueKey('invoice-primary-print')));
      await animated(tester);
      await enterPin(tester, pin);
      await until(tester, () => bridge.printed.length == 1);
      expect((await audit(tester)).single['action'], 'INVOICE_REPRINT');
    });

    testWidgets('sharing as PDF needs it too — the PDF holds the codes',
        (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const ValueKey('invoice-more')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('invoice-more-sharePdf')));
      await animated(tester);
      await enterPin(tester, pin);
      await until(tester, () => bridge.shared.length == 1);
      expect(bridge.shared.single.mimeType, 'application/pdf');
      expect((await audit(tester)).single['details'],
          contains('"output":"sharePdf"'));
    });

    testWidgets('show the code: PIN, then the code grouped in fours',
        (tester) async {
      await open(tester);
      await openCodeMenu(tester, codeId, 'reveal');
      await enterPin(tester, pin);

      final shown = find.byKey(const ValueKey('revealed-code'));
      expect(shown, findsOneWidget);
      expect(
        [
          for (final text in tester.widgetList<Text>(
              find.descendant(of: shown, matching: find.byType(Text))))
            text.data,
        ],
        ['1111', '2222', '3333', '4444'],
      );
      final log = (await audit(tester)).single;
      expect(log['action'], 'CODE_REVEAL');
      expect(log['details'], contains('"tail":"4444"'));
      expect('${log['details']}'.contains(codeA), isFalse);

      // Closed: the code is gone from the screen again.
      await tester.tap(find.byKey(const ValueKey('revealed-code-close')));
      await animated(tester);
      expectNotOnScreen(tester, codeA);
    });

    testWidgets('a wrong PIN shows nothing', (tester) async {
      await open(tester);
      await openCodeMenu(tester, codeId, 'reveal');
      await enterPin(tester, '1234');
      expect(find.byKey(const ValueKey('revealed-code')), findsNothing);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expectNotOnScreen(tester, codeA);
      expect(await audit(tester), isEmpty);
    });

    testWidgets('void: a reason and the PIN; then return to stock',
        (tester) async {
      await open(tester);

      // A reason is required.
      await openCodeMenu(tester, codeId, 'void');
      final confirm = find.byKey(const ValueKey('reason-confirm'));
      await tester.tap(confirm);
      await settle(tester);
      expect(find.text('This field is required'), findsOneWidget);
      await tester.enterText(
          find.byKey(const ValueKey('reason-field')), 'defective card');
      await tester.tap(confirm);
      await animated(tester);
      await enterPin(tester, pin);
      await until(tester, () => find.text('Code voided').evaluate().isNotEmpty);

      var row = (await rows(tester, 'voucher_codes')).single;
      expect(row['status'], 'VOID');
      expect(row['status_note'], 'defective card');
      expect(row['sold_invoice_no'], invoice.invoiceNo,
          reason: 'the sale snapshot stays');
      await animated(tester);
      expect(find.textContaining('Reason: defective card'), findsOneWidget);
      // A voided code is no longer on the reprint.
      final preview = [
        for (final text in tester.widgetList<Text>(find.descendant(
          of: find.byKey(const ValueKey('archive-invoice-view')),
          matching: find.byType(Text),
          skipOffstage: false,
        )))
          text.data ?? '',
      ].join();
      expect(preview.contains('4444'), isFalse);

      // The card was fine after all: back to stock, behind the PIN again.
      await openCodeMenu(tester, codeId, 'return');
      await tester.enterText(
          find.byKey(const ValueKey('reason-field')), 'not defective');
      await tester.tap(confirm);
      await animated(tester);
      await enterPin(tester, pin);
      await until(tester,
          () => find.text('Code returned to stock').evaluate().isNotEmpty);

      row = (await rows(tester, 'voucher_codes')).single;
      expect(row['status'], 'AVAILABLE');
      expect(row['sold_invoice_no'], isNull);
      await animated(tester);
      // It is no longer one of this invoice's codes.
      expect(find.byKey(const ValueKey('invoice-codes')), findsNothing);
      expect(
        [for (final l in await audit(tester)) l['action']],
        ['CODE_VOID', 'CODE_RESTORE'],
      );
    });

    testWidgets('backing out of the reason or of the PIN changes nothing',
        (tester) async {
      await open(tester);
      await openCodeMenu(tester, codeId, 'void');
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(pinDialog, findsNothing);

      await openCodeMenu(tester, codeId, 'void');
      await tester.enterText(find.byKey(const ValueKey('reason-field')), 'x');
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await animated(tester);
      await tester.tap(find.text('Cancel'));
      await animated(tester);

      expect((await rows(tester, 'voucher_codes')).single['status'], 'SOLD');
      expect(await audit(tester), isEmpty);
    });
  });

  group('card stock screen', () {
    testWidgets('warnings first, then expired codes, then the products',
        (tester) async {
      await db(tester,
          () => insertCard('Card 10000', code: '302', favorite: false));
      await load(tester, [codeA]); // 1 ≤ threshold 2: low
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await load(tester, [codeB], lastDay: yesterday);
      await pump(tester, const CardStockScreen());

      final warnings = find.byKey(const ValueKey('stock-warnings'));
      expect(
        find.descendant(
            of: warnings, matching: find.text('Card 5000: only 1 left')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: warnings, matching: find.text('Card 10000: out of stock')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('stock-expired')), findsOneWidget);
      // Above the first product card.
      expect(
        tester.getTopLeft(warnings).dy,
        lessThan(tester
            .getTopLeft(find.byKey(ValueKey('stock-product-$cardId')))
            .dy),
      );

      // Available 1, sold 0, void 0, expired 1.
      Finder figure(String id) => find.descendant(
            of: find.byKey(ValueKey('stock-product-$cardId')),
            matching: find.byKey(ValueKey(id)),
          );
      expect(tester.widget<Text>(figure('count-available')).data, '1');
      expect(tester.widget<Text>(figure('count-sold')).data, '0');
      expect(tester.widget<Text>(figure('count-void')).data, '0');
      expect(tester.widget<Text>(figure('count-expired')).data, '1');
    });

    testWidgets('nothing to warn about: no warning card', (tester) async {
      await load(tester, [codeA, codeB, '9999000011112222']);
      await pump(tester, const CardStockScreen());
      expect(find.byKey(const ValueKey('stock-warnings')), findsNothing);
      expect(find.byKey(const ValueKey('stock-expired')), findsNothing);
    });

    testWidgets('an unsold batch is deleted behind the PIN', (tester) async {
      final report = await load(tester, [codeA, codeB]);
      await setPin(tester);
      await pump(tester, ProductStockScreen(productId: cardId));

      await tester.tap(find.byKey(ValueKey('batch-menu-${report.batchId}')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('batch-action-delete')));
      await animated(tester);
      expect(find.textContaining('Its 2 unsold codes'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('batch-delete-confirm')));
      await animated(tester);
      await enterPin(tester, pin);
      await until(
          tester, () => find.text('2 codes deleted').evaluate().isNotEmpty);

      expect(await rows(tester, 'voucher_codes'), isEmpty);
      expect(await rows(tester, 'voucher_batches'), isEmpty);
      expect((await audit(tester)).single['action'], 'BATCH_DELETE');
    });

    testWidgets('a batch with a sold code is never deleted', (tester) async {
      final report = await load(tester, [codeA, codeB]);
      await setPin(tester);
      await sell(tester);
      await pump(tester, ProductStockScreen(productId: cardId));

      await tester.tap(find.byKey(ValueKey('batch-menu-${report.batchId}')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('batch-action-delete')));
      await animated(tester);
      expect(find.text('This batch has sold codes and cannot be deleted.'),
          findsOneWidget);
      expect(find.byKey(const ValueKey('batch-delete-dialog')), findsNothing);
      expect(await rows(tester, 'voucher_codes'), hasLength(2));
    });

    testWidgets('the codes of a batch are listed masked', (tester) async {
      final report = await load(tester, [codeA, codeB]);
      await sell(tester, customer: 'Ahmad');
      await pump(tester, ProductStockScreen(productId: cardId));
      await tester.tap(find.byKey(ValueKey('batch-${report.batchId}')));
      await animated(tester);

      expect(find.byType(BatchCodesScreen), findsOneWidget);
      expect(find.text('•••• •••• 4444'), findsOneWidget);
      expect(find.text('•••• •••• 8888'), findsOneWidget);
      expect(find.textContaining('Sold'), findsWidgets);
      expect(find.textContaining('Ahmad'), findsOneWidget);
      expect(find.textContaining('In stock'), findsOneWidget);
      expectNotOnScreen(tester, codeA);
      expectNotOnScreen(tester, codeB);
    });

    testWidgets('export: a warning, the PIN, then the file', (tester) async {
      await load(tester, [codeA, codeB]);
      await setPin(tester);
      await sell(tester); // codeA is sold: only codeB is exported
      await pump(tester, ProductStockScreen(productId: cardId));

      await tester.tap(find.byKey(const ValueKey('product-stock-menu')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('product-stock-export')));
      await animated(tester);
      expect(find.textContaining('holds the codes in the clear'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('export-share')));
      await animated(tester);
      await enterPin(tester, pin);
      await until(tester, () => bridge.shared.length == 1);

      final file = File(bridge.shared.single.path);
      expect(file.readAsStringSync(), '$codeB\n');
      expect(bridge.shared.single.mimeType, 'text/plain');
      expect((await audit(tester)).single['action'], 'CODE_EXPORT');
      expectNotOnScreen(tester, codeB);
    });
  });

  group('search by full code', () {
    Future<void> openLookup(WidgetTester tester) async {
      await pump(tester, const CardStockScreen());
      await tester.tap(find.byKey(const ValueKey('stock-lookup')));
      await animated(tester);
      await enterPin(tester, pin);
    }

    Future<void> search(WidgetTester tester, String code) async {
      await tester.enterText(find.byKey(const ValueKey('lookup-field')), code);
      await tester.tap(find.byKey(const ValueKey('lookup-search')));
      await animated(tester);
    }

    testWidgets('needs the PIN; shows status, date, invoice and customer',
        (tester) async {
      await load(tester, [codeA, codeB]);
      await setPin(tester);
      final invoice = await sell(tester, customer: 'Ahmad');
      await openLookup(tester);

      await search(tester, '1111-2222-3333-4444');
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lookup-status'))).data,
        'Sold',
      );
      expect(find.byKey(const ValueKey('lookup-sold-on')), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('lookup-invoice-no')))
            .data,
        'Invoice no. ${invoice.invoiceNo}',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lookup-customer'))).data,
        'Customer: Ahmad',
      );
      expect(
          find.byKey(const ValueKey('lookup-open-invoice')), findsOneWidget);

      // One still in stock, and one that does not exist.
      await search(tester, codeB);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lookup-status'))).data,
        'In stock',
      );
      await search(tester, '0000000000000000');
      expect(find.byKey(const ValueKey('lookup-not-found')), findsOneWidget);

      // Part of a code finds nothing: the search is by hash.
      await search(tester, '11112222');
      expect(find.byKey(const ValueKey('lookup-not-found')), findsOneWidget);

      final log = await audit(tester);
      expect([for (final l in log) l['action']], everyElement('CODE_LOOKUP'));
      expect(log, hasLength(4));
    });

    testWidgets('still answers after the invoice was deleted', (tester) async {
      await load(tester, [codeA]);
      await setPin(tester);
      final invoice = await sell(tester, customer: 'Ahmad');
      await db(tester, () async {
        await database.db
            .delete('invoices', where: 'id = ?', whereArgs: [invoice.id]);
        return true;
      });
      await openLookup(tester);
      await search(tester, codeA);

      expect(
        tester.widget<Text>(find.byKey(const ValueKey('lookup-status'))).data,
        'Sold',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('lookup-invoice-no')))
            .data,
        'Invoice no. ${invoice.invoiceNo}',
      );
      expect(find.text('Customer: Ahmad'), findsOneWidget);
      expect(find.byKey(const ValueKey('lookup-open-invoice')), findsNothing);
      expect(
        find.text('The invoice itself was deleted from the archive'),
        findsOneWidget,
      );
    });

    testWidgets('without the PIN the screen does not open', (tester) async {
      await setPin(tester);
      await pump(tester, const CardStockScreen());
      await tester.tap(find.byKey(const ValueKey('stock-lookup')));
      await animated(tester);
      await tester.tap(find.text('Cancel'));
      await animated(tester);
      expect(find.byKey(const ValueKey('lookup-field')), findsNothing);
    });
  });

  group('expired codes', () {
    testWidgets('listed apart, and voided when the owner decides',
        (tester) async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      await load(tester, [codeA, codeB], lastDay: yesterday);
      await load(tester, ['9999000011112222']);
      await setPin(tester);
      await pump(tester, const ExpiredCodesScreen());

      expect(find.byKey(ValueKey('expired-product-$cardId')), findsOneWidget);
      expect(find.text('2 cards'), findsOneWidget);
      expect(find.textContaining('Expired ·'), findsNWidgets(2));
      expectNotOnScreen(tester, codeA);

      await tester.tap(find.byKey(ValueKey('expired-void-$cardId')));
      await animated(tester);
      expect(
        find.text('2 expired codes of "Card 5000" will be voided.'),
        findsOneWidget,
      );
      await tester.enterText(
          find.byKey(const ValueKey('reason-field')), 'written off');
      await tester.tap(find.byKey(const ValueKey('reason-confirm')));
      await animated(tester);
      await enterPin(tester, pin);
      await until(
          tester, () => find.text('2 codes voided').evaluate().isNotEmpty);

      final codes = await rows(tester, 'voucher_codes');
      expect([for (final c in codes) c['status']],
          ['VOID', 'VOID', 'AVAILABLE']);
      await animated(tester);
      expect(find.byKey(const ValueKey('expired-empty')), findsOneWidget);
    });
  });

  group('PIN in the settings', () {
    final tile = find.byKey(const ValueKey('setting-pin'));

    Future<void> openSettings(WidgetTester tester) async {
      await pump(tester, const SettingsScreen());
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester, 4);
    }

    testWidgets('choose a PIN: 4 to 6 digits, typed twice', (tester) async {
      await openSettings(tester);
      expect(find.text('No PIN set'), findsOneWidget);
      await tester.tap(tile);
      await animated(tester);

      final newField = find.byKey(const ValueKey('pin-new-field'));
      final again = find.byKey(const ValueKey('pin-again-field'));
      final save = find.byKey(const ValueKey('pin-set-save'));

      await tester.enterText(newField, '12');
      await tester.tap(save);
      await settle(tester);
      expect(find.text('The PIN must be 4 to 6 digits'), findsOneWidget);

      await tester.enterText(newField, '2580');
      await tester.enterText(again, '2581');
      await tester.tap(save);
      await settle(tester);
      expect(find.text('The two PINs are not the same'), findsOneWidget);

      // Letters cannot even be typed.
      await tester.enterText(newField, '25a8b0');
      expect(
        tester
            .widget<EditableText>(find.descendant(
                of: newField, matching: find.byType(EditableText)))
            .controller
            .text,
        '2580',
      );

      await tester.enterText(again, '2580');
      await tester.tap(save);
      await until(tester, () => pinSetDialog.evaluate().isEmpty);
      await animated(tester);
      expect(find.text('A PIN is set'), findsOneWidget);
      expect(find.text('PIN saved'), findsOneWidget);
      expect(
        await db(tester,
            () => PinRepository(SettingsRepository(database.db)).verify(pin)),
        isA<PinCorrect>(),
      );
    });

    testWidgets('change and remove both ask for the current PIN first',
        (tester) async {
      await setPin(tester);
      await openSettings(tester);

      // Change.
      await tester.tap(tile);
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('pin-option-change')));
      await animated(tester);
      await enterPin(tester, pin);
      await tester.enterText(
          find.byKey(const ValueKey('pin-new-field')), '135790');
      await tester.enterText(
          find.byKey(const ValueKey('pin-again-field')), '135790');
      await tester.tap(find.byKey(const ValueKey('pin-set-save')));
      await until(tester, () => pinSetDialog.evaluate().isEmpty);
      await animated(tester);
      final pins = PinRepository(SettingsRepository(database.db));
      expect(await db(tester, () => pins.verify('135790')), isA<PinCorrect>());

      // Remove: the old PIN no longer opens the dialog.
      await tester.tap(tile);
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('pin-option-remove')));
      await animated(tester);
      await enterPin(tester, '0000');
      await tester.enterText(
          find.byKey(const ValueKey('pin-entry-field')), '135790');
      await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
      await until(tester, () => pinDialog.evaluate().isEmpty);
      await animated(tester);
      expect(find.byKey(const ValueKey('pin-remove-dialog')), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove PIN'));
      await until(tester, () => find.text('No PIN set').evaluate().isNotEmpty);

      expect(await db(tester, pins.isSet), isFalse);
      expect(
        [for (final l in await audit(tester)) l['action']],
        ['PIN_CHANGE', 'PIN_REMOVE'],
      );
    });

    testWidgets('five wrong PINs lock the dialog', (tester) async {
      await setPin(tester);
      await load(tester, [codeA]);
      await pump(tester, const CardStockScreen());
      await tester.tap(find.byKey(const ValueKey('stock-lookup')));
      await animated(tester);
      for (var i = 0; i < 5; i++) {
        await enterPin(tester, '0000');
      }
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
      // Even the right PIN is refused while the lock lasts.
      await tester.enterText(
          find.byKey(const ValueKey('pin-entry-field')), pin);
      await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
      await animated(tester);
      expect(pinDialog, findsOneWidget);
      expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
    });
  });

  group('audit log screen', () {
    testWidgets('opens behind the PIN and lists what was done',
        (tester) async {
      await load(tester, [codeA, codeB]);
      await setPin(tester);
      await sell(tester, customer: 'Ahmad');
      final codeId = (await rows(tester, 'voucher_codes')).first['id']! as int;
      await db(tester, () async {
        await vouchers.reveal(codeId);
        await vouchers.voidCode(codeId, reason: 'defective');
        return true;
      });

      await pump(tester, const SettingsScreen());
      final tile = find.byKey(const ValueKey('setting-audit-log'));
      await tester.scrollUntilVisible(
        tile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(tile);
      await animated(tester);
      await enterPin(tester, pin);

      expect(find.byType(AuditLogScreen), findsOneWidget);
      expect(find.text('Code voided'), findsOneWidget);
      expect(find.text('Code shown on screen'), findsOneWidget);
      expect(find.text('Codes loaded'), findsOneWidget);
      expect(find.textContaining('Reason: defective'), findsOneWidget);
      expect(find.textContaining('Card 5000'), findsNWidgets(3));
      expect(find.textContaining('•••• •••• 4444'), findsNWidgets(2));
      expectNotOnScreen(tester, codeA);

      // Newest first.
      expect(
        tester.getTopLeft(find.text('Code voided')).dy,
        lessThan(tester.getTopLeft(find.text('Codes loaded')).dy),
      );
    });

    testWidgets('filters by date', (tester) async {
      await db(tester, () async {
        await database.db.insert('audit_log', {
          'created_at':
              DateTime(2020, 5, 5).toUtc().millisecondsSinceEpoch,
          'action': 'CODE_EXPORT',
          'product_name': 'Old card',
        });
        await database.db.insert('audit_log', {
          'created_at': DateTime.now().toUtc().millisecondsSinceEpoch,
          'action': 'CODE_VOID',
          'product_name': 'New card',
        });
        return true;
      });
      await pump(tester, const AuditLogScreen());
      expect(find.text('Codes exported'), findsOneWidget);
      expect(find.text('Code voided'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('audit-period-today')));
      await animated(tester);
      expect(find.text('Codes exported'), findsNothing);
      expect(find.text('Code voided'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('audit-period-all')));
      await animated(tester);
      expect(find.text('Codes exported'), findsOneWidget);
    });

    testWidgets('an empty period says so', (tester) async {
      await pump(tester, const AuditLogScreen());
      expect(find.byKey(const ValueKey('audit-empty')), findsOneWidget);
    });
  });

  group('statistics', () {
    testWidgets('cards sold per product, with the profit', (tester) async {
      await load(tester, [codeA, codeB], cost: 4500);
      await sell(tester, qty: 2);
      await pump(tester, const StatsScreen());

      final card = find.byKey(const ValueKey('stats-cards'));
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(
        find.descendant(of: card, matching: find.text('Card 5000')),
        findsOneWidget,
      );
      expect(
        find.descendant(
            of: card, matching: find.textContaining('2 cards · Profit')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('1,000')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.textContaining('10,000')),
        findsOneWidget,
      );
    });

    testWidgets('nothing sold: no cards section', (tester) async {
      await load(tester, [codeA]);
      await pump(tester, const StatsScreen());
      expect(find.byKey(const ValueKey('stats-cards')), findsNothing);
    });
  });
}
