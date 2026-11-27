import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/qr_bitmap.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:souqi/domain/models/invoice_extras.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/domain/models/voucher.dart';
import 'package:souqi/features/invoice/contact_numbers_settings.dart';
import 'package:souqi/features/invoice/invoice_providers.dart';
import 'package:souqi/features/invoice/invoice_settings_screen.dart';
import 'package:souqi/features/invoice/payment_qr_reader.dart';
import 'package:souqi/features/invoice/payment_qr_settings.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/qr_grid_decoder.dart';
import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// Invoice settings → payment QR and contact numbers, driven like the
/// owner drives them: the PIN and the audit log around every change of the
/// code, the picture that reads and the one that does not, the lines above
/// and under the code, the contact list — and all of it on a 360×640 phone
/// at a large system font.
///
/// The photo picker and ML Kit only exist on a phone: the picker is a fake
/// that hands over a PNG, and the code reader is the test decoder reading
/// that PNG (test/core/qr_grid_decoder.dart).
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  late AppDatabase database;

  /// The picture the fake picker hands over next, and every one it did.
  late Uint8List nextPicture;
  late Map<String, Uint8List> picked;
  late List<QrImageSource> sources;

  setUp(() async {
    database = await openTestDb();
    nextPicture = Uint8List(0);
    picked = {};
    sources = [];
  });
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

  /// Pumps frames, letting real async work run, until [done] holds.
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

  /// A sheet or dialog sliding in or out.
  Future<void> animated(WidgetTester tester) => settle(tester, 28);

  Future<T> db<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  Uint8List pngOf(RgbaImage image) => encodePngRgb(
        width: image.width,
        height: image.height,
        rgb: flattenToRgb(image),
      );

  Future<Map<String, String>> stored(WidgetTester tester) =>
      db(tester, () => SettingsRepository(database.db).getAll());

  Future<List<Map<String, Object?>>> audit(WidgetTester tester) => db(
        tester,
        () => database.db.query('audit_log', orderBy: 'id'),
      );

  Future<void> seed(WidgetTester tester, Map<String, String> values) =>
      tester.runAsync(() => SettingsRepository(database.db).setMany(values));

  Future<void> pumpScreen(
    WidgetTester tester, {
    Size size = const Size(600, 1300),
    double textScale = 1,
    Locale locale = const Locale('en'),
  }) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          databaseProvider.overrideWithValue(database),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(locale)),
          nativeBridgeProvider.overrideWithValue(FakeNativeBridge()),
          qrImagePickerProvider.overrideWithValue((source) async {
            sources.add(source);
            final path = 'picked-${picked.length}.png';
            picked[path] = nextPicture;
            return PickedQrImage(path: path, bytes: nextPicture);
          }),
          qrImageDecoderProvider.overrideWithValue((path) async {
            final png = decodePngRgb(picked[path]!);
            if (png == null) return null;
            return decodeQrGrid(
              width: png.width,
              height: png.height,
              isBlack: (x, y) => png.rgb[(y * png.width + x) * 3] < 128,
            );
          }),
        ],
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const InvoiceSettingsScreen(),
        ),
      ),
    );
    await settle(tester);
    expect(tester.takeException(), isNull);
  }

  /// The settings form (the preview above it scrolls too).
  Finder form() => find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  Future<void> reach(WidgetTester tester, Finder target) async {
    await tester.scrollUntilVisible(target, 150, scrollable: form());
    await settle(tester, 4);
  }

  Future<void> tapIn(WidgetTester tester, Key key) async {
    final target = find.byKey(key);
    await reach(tester, target);
    await tester.tap(target);
    await animated(tester);
  }

  Future<void> enterPin(WidgetTester tester, String pin) async {
    expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('pin-entry-field')), pin);
    await tester.tap(find.byKey(const ValueKey('pin-entry-ok')));
    await animated(tester);
  }

  final preview = find.descendant(
    of: find.byKey(const ValueKey('invoice-preview')),
    matching: find.byKey(const ValueKey('paper-payment-qr-symbol')),
  );

  group('the payment QR', () {
    testWidgets('PIN, read the picture, confirm, saved and logged; removed '
        'and logged', (tester) async {
      await tester.runAsync(
        () => PinRepository(SettingsRepository(database.db)).set('2580'),
      );
      nextPicture = pngOf(qrPhoto(emv, dark: 60, light: 190));
      await pumpScreen(tester);
      expect(preview, findsNothing);

      await tapIn(tester, const ValueKey('payment-qr-switch'));
      await enterPin(tester, '2580');
      expect(find.byKey(const ValueKey('payment-qr-source-sheet')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-qr-source-gallery')));
      await until(
        tester,
        () => find.byKey(const ValueKey('payment-qr-confirm')).evaluate().isNotEmpty,
      );
      expect(sources, [QrImageSource.gallery]);
      // What the code says, for the owner to check.
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('payment-qr-confirm-text')))
            .data,
        '${emv.substring(0, 119)}…',
      );
      await tester.tap(find.byKey(const ValueKey('payment-qr-confirm-use')));
      await until(tester, () => preview.evaluate().isNotEmpty);

      var rows = await stored(tester);
      expect(rows[SettingsKeys.paymentQrEnabled], '1');
      expect(rows[SettingsKeys.paymentQrText], emv, reason: 'the TEXT, not the photo');
      expect(rows[SettingsKeys.paymentQrImageBase64] ?? '', '');
      var log = await audit(tester);
      expect(log.map((r) => r['action']), ['PAYMENT_QR_SET']);
      expect(
        jsonDecode(log.single['details']! as String),
        {'qr': '${emv.substring(0, 59)}…'},
      );
      // The live preview shows it; the summary says it was read.
      expect(find.byKey(const ValueKey('payment-qr-kind')), findsOneWidget);
      expect(find.text('Read from the image: printed as a clean, sharp code'),
          findsOneWidget);

      await tapIn(tester, const ValueKey('payment-qr-remove'));
      await enterPin(tester, '2580');
      await until(tester, () => preview.evaluate().isEmpty);
      rows = await stored(tester);
      expect(rows[SettingsKeys.paymentQrEnabled], '0');
      expect(rows[SettingsKeys.paymentQrText], '');
      log = await audit(tester);
      expect(log.map((r) => r['action']), ['PAYMENT_QR_SET', 'PAYMENT_QR_REMOVE']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a wrong PIN changes nothing and logs nothing', (tester) async {
      await tester.runAsync(
        () => PinRepository(SettingsRepository(database.db)).set('2580'),
      );
      await seed(tester, {
        SettingsKeys.paymentQrEnabled: '1',
        SettingsKeys.paymentQrText: upi,
      });
      await pumpScreen(tester);
      expect(preview, findsOneWidget);

      await tapIn(tester, const ValueKey('payment-qr-switch'));
      await enterPin(tester, '1111');
      // Still asking: the wrong PIN opened nothing.
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('pin-entry-dialog')),
        matching: find.text('Cancel'),
      ));
      await animated(tester);
      expect((await stored(tester))[SettingsKeys.paymentQrEnabled], '1');
      expect(
        (await audit(tester)).where(
          (r) => (r['action']! as String).startsWith('PAYMENT_QR'),
        ),
        isEmpty,
      );

      // The right one turns it off — logged with what it was.
      await tapIn(tester, const ValueKey('payment-qr-switch'));
      await enterPin(tester, '2580');
      await until(tester, () => preview.evaluate().isEmpty);
      expect((await stored(tester))[SettingsKeys.paymentQrEnabled], '0');
      expect((await stored(tester))[SettingsKeys.paymentQrText], upi,
          reason: 'off keeps the code for later');
      final log = (await audit(tester)).last;
      expect(log['action'], 'PAYMENT_QR_OFF');
      expect(jsonDecode(log['details']! as String), {'qr': upi});
    });

    testWidgets('a picture that does not read: "use the image as is"',
        (tester) async {
      // A code with one module damaged: no reader takes it.
      final photo = qrPhoto(upi, left: 20, top: 20);
      for (var y = 20 + 25 * 7; y < 20 + 26 * 7; y++) {
        for (var x = 20 + 25 * 7; x < 20 + 26 * 7; x++) {
          final i = (y * photo.width + x) * 4;
          final v = photo.rgba[i] < 128 ? 205 : 45;
          photo.rgba[i] = photo.rgba[i + 1] = photo.rgba[i + 2] = v;
        }
      }
      nextPicture = pngOf(photo);
      await pumpScreen(tester);

      await tapIn(tester, const ValueKey('payment-qr-switch'));
      // No PIN set: nothing is asked.
      await tester.tap(find.byKey(const ValueKey('payment-qr-source-file')));
      await until(
        tester,
        () => find.byKey(const ValueKey('payment-qr-unread')).evaluate().isNotEmpty,
      );
      expect(find.text('No QR code could be read'), findsOneWidget);
      expect(find.byKey(const ValueKey('payment-qr-unread-warning')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('payment-qr-unread-use')));
      await until(tester, () => preview.evaluate().isNotEmpty);

      final rows = await stored(tester);
      expect(rows[SettingsKeys.paymentQrEnabled], '1');
      expect(rows[SettingsKeys.paymentQrText] ?? '', '');
      final picture =
          QrPicture.fromPng(base64Decode(rows[SettingsKeys.paymentQrImageBase64]!))!;
      // Cropped to the code and pure black and white.
      expect(picture.bitmap.side, lessThanOrEqualTo(maxQrBitmapSide));
      expect(picture.bitmap.bits.toSet(), {0, 1});
      final log = await audit(tester);
      expect(log.single['action'], 'PAYMENT_QR_SET');
      expect(jsonDecode(log.single['details']! as String), {'qr_image': 1});
      expect(find.text('The image as it is: it may not scan'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('"choose another" goes back to the picker; a file that is '
        'not a picture says so', (tester) async {
      nextPicture = Uint8List.fromList(utf8.encode('this is not a picture'));
      await pumpScreen(tester);
      await tapIn(tester, const ValueKey('payment-qr-switch'));
      await tester.tap(find.byKey(const ValueKey('payment-qr-source-gallery')));
      await until(
        tester,
        () => find.text('This file is not an image.').evaluate().isNotEmpty,
      );
      expect((await stored(tester))[SettingsKeys.paymentQrEnabled] ?? '0', '0');

      // A blank picture: nothing to keep, only "choose another".
      nextPicture = pngOf(RgbaImage(
        width: 30,
        height: 30,
        rgba: Uint8List.fromList(List.filled(30 * 30 * 4, 255)),
      ));
      await tapIn(tester, const ValueKey('payment-qr-switch'));
      await tester.tap(find.byKey(const ValueKey('payment-qr-source-camera')));
      await until(
        tester,
        () => find.byKey(const ValueKey('payment-qr-unread')).evaluate().isNotEmpty,
      );
      expect(find.byKey(const ValueKey('payment-qr-unread-use')), findsNothing);
      nextPicture = pngOf(qrPhoto(upi));
      await tester.tap(find.byKey(const ValueKey('payment-qr-unread-another')));
      await animated(tester);
      await tester.tap(find.byKey(const ValueKey('payment-qr-source-gallery')));
      await until(
        tester,
        () => find.byKey(const ValueKey('payment-qr-confirm')).evaluate().isNotEmpty,
      );
      await tester.tap(find.byKey(const ValueKey('payment-qr-confirm-use')));
      await until(tester, () => preview.evaluate().isNotEmpty);
      expect(sources, [
        QrImageSource.gallery,
        QrImageSource.camera,
        QrImageSource.gallery,
      ]);
      expect((await stored(tester))[SettingsKeys.paymentQrText], upi);
    });

    testWidgets('the lines above and under the code: PIN, saved, logged, '
        'on the paper', (tester) async {
      await tester.runAsync(
        () => PinRepository(SettingsRepository(database.db)).set('2580'),
      );
      await seed(tester, {
        SettingsKeys.paymentQrEnabled: '1',
        SettingsKeys.paymentQrText: upi,
      });
      await pumpScreen(tester);
      final caption = find.descendant(
        of: find.byKey(const ValueKey('invoice-preview')),
        matching: find.byKey(const ValueKey('paper-payment-qr-caption')),
      );
      // The default line, in the INVOICE language (Arabic by default).
      expect(tester.widget<Text>(caption).data, 'امسح للدفع');

      await tapIn(tester, const ValueKey('payment-qr-note'));
      await enterPin(tester, '2580');
      await tester.enterText(
        find.byKey(const ValueKey('payment-qr-text-field')),
        '  Bank of Syria — Abu Ahmad ',
      );
      await tester.tap(find.byKey(const ValueKey('payment-qr-text-save')));
      await until(
        tester,
        () => find
            .descendant(
              of: find.byKey(const ValueKey('invoice-preview')),
              matching: find.text('Bank of Syria — Abu Ahmad'),
            )
            .evaluate()
            .isNotEmpty,
      );

      await tapIn(tester, const ValueKey('payment-qr-caption'));
      await enterPin(tester, '2580');
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('payment-qr-text-field')))
            .controller!
            .text,
        'امسح للدفع',
      );
      await tester.enterText(find.byKey(const ValueKey('payment-qr-text-field')), '');
      await tester.tap(find.byKey(const ValueKey('payment-qr-text-save')));
      await until(tester, () => caption.evaluate().isEmpty);

      final rows = await stored(tester);
      expect(rows[SettingsKeys.paymentQrNote], 'Bank of Syria — Abu Ahmad');
      expect(rows[SettingsKeys.paymentQrCaption], '');
      final log = await audit(tester);
      expect(log.map((r) => r['action']), ['PAYMENT_QR_TEXT', 'PAYMENT_QR_TEXT']);
      expect(jsonDecode(log.first['details']! as String),
          {'field': 'note', 'text': 'Bank of Syria — Abu Ahmad'});
      expect(jsonDecode(log.last['details']! as String),
          {'field': 'caption', 'text': ''});
    });

    testWidgets('where it appears: no PIN, saved at once', (tester) async {
      await tester.runAsync(
        () => PinRepository(SettingsRepository(database.db)).set('2580'),
      );
      await seed(tester, {
        SettingsKeys.paymentQrEnabled: '1',
        SettingsKeys.paymentQrText: upi,
      });
      await pumpScreen(tester);
      // The sample invoice of the preview is partly paid: it keeps the code.
      await tapIn(tester, const ValueKey('payment-qr-when-unpaid'));
      await tapIn(tester, const ValueKey('payment-qr-receipts'));
      await tapIn(tester, const ValueKey('payment-qr-statements'));
      expect(find.byKey(const ValueKey('pin-entry-dialog')), findsNothing);
      await until(tester, () => true);
      final rows = await stored(tester);
      expect(rows[SettingsKeys.paymentQrWhen], 'UNPAID');
      expect(rows[SettingsKeys.paymentQrOnReceipts], '1');
      expect(rows[SettingsKeys.paymentQrOnStatements], '0');
      expect(await audit(tester), isEmpty);
    });
  });

  group('contact numbers', () {
    testWidgets('add, edit, reorder, delete; three at most', (tester) async {
      await pumpScreen(tester);
      await tapIn(tester, const ValueKey('contacts-switch'));

      Future<void> add(String name, String phone) async {
        await tapIn(tester, const ValueKey('contact-add'));
        await tester.enterText(find.byKey(const ValueKey('contact-name-field')), name);
        await tester.enterText(find.byKey(const ValueKey('contact-phone-field')), phone);
        await tester.tap(find.byKey(const ValueKey('contact-save')));
        await animated(tester);
      }

      // A phone is required.
      await tapIn(tester, const ValueKey('contact-add'));
      await tester.enterText(find.byKey(const ValueKey('contact-name-field')), 'x');
      await tester.tap(find.byKey(const ValueKey('contact-save')));
      await animated(tester);
      expect(find.text('Enter a phone number'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('contact-cancel')));
      await animated(tester);

      await add('أبو أحمد', '٠٩٤٤ ١٢٣ ٤٥٦');
      await add('', '+963 11 222 3333');
      await add('Shop', '0933-765-432');
      // Three: no more "add".
      expect(find.byKey(const ValueKey('contact-add'), skipOffstage: false), findsNothing);
      expect(find.text('3 numbers at most.', skipOffstage: false), findsOneWidget);

      // Move the first one down, edit the last, delete the middle.
      await tapIn(tester, const ValueKey('contact-menu-0'));
      await tester.tap(find.byKey(const ValueKey('contact-down-0')));
      await animated(tester);
      await tapIn(tester, const ValueKey('contact-2'));
      await tester.enterText(find.byKey(const ValueKey('contact-name-field')), 'Shop 2');
      await tester.tap(find.byKey(const ValueKey('contact-save')));
      await animated(tester);
      await tapIn(tester, const ValueKey('contact-menu-1'));
      await tester.tap(find.byKey(const ValueKey('contact-delete-1')));
      await animated(tester);
      await tapIn(tester, const ValueKey('contacts-position-footer'));
      await until(tester, () => true);

      final rows = await stored(tester);
      expect(rows[SettingsKeys.contactsEnabled], '1');
      expect(rows[SettingsKeys.contactsPosition], 'FOOTER');
      expect(InvoiceContact.listFromJson(rows[SettingsKeys.contacts]!), const [
        InvoiceContact(phone: '+963 11 222 3333'),
        InvoiceContact(name: 'Shop 2', phone: '0933-765-432'),
      ]);
      // The phone as typed is kept; the preview prints it normalised.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('invoice-preview')),
          matching: find.text('0933-765-432'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('Arabic-Indic digits are kept as typed', (tester) async {
      await pumpScreen(tester);
      await tapIn(tester, const ValueKey('contacts-switch'));
      await tapIn(tester, const ValueKey('contact-add'));
      await tester.enterText(find.byKey(const ValueKey('contact-phone-field')), '٠٩٣٣ ٥٥٥ ٧٧٧');
      await tester.tap(find.byKey(const ValueKey('contact-save')));
      await animated(tester);
      await until(tester, () => true);
      final rows = await stored(tester);
      expect(InvoiceContact.listFromJson(rows[SettingsKeys.contacts]!).single.phone,
          '٠٩٣٣ ٥٥٥ ٧٧٧');
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('invoice-preview')),
          matching: find.text('0933 555 777'),
        ),
        findsOneWidget,
      );
    });
  });

  group('a 360×640 phone at font scale 1.3', () {
    const phone = Size(360, 640);

    Future<void> seedEverything(WidgetTester tester) => seed(tester, {
          SettingsKeys.paymentQrEnabled: '1',
          SettingsKeys.paymentQrText: emv,
          SettingsKeys.paymentQrNote: 'بنك سورية الدولي — حساب ٠١٢٣ ٤٥٦٧ ٨٩ — أبو أحمد',
          SettingsKeys.contactsEnabled: '1',
          SettingsKeys.contacts: InvoiceContact.listToJson(const [
            InvoiceContact(name: 'عبد الرحمن محمد الأحمد الحسن', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
            InvoiceContact(name: 'Abu Ahmad the grocer', phone: '+963 944 123 456'),
            InvoiceContact(phone: '011 222 3333'),
          ]),
        });

    for (final locale in [const Locale('en'), const Locale('ar')]) {
      testWidgets('the new settings fit (${locale.languageCode})',
          (tester) async {
        await seedEverything(tester);
        await pumpScreen(tester, size: phone, textScale: 1.3, locale: locale);
        for (final key in [
          'contacts-switch',
          'contact-0',
          'contact-2',
          'contacts-position-footer',
          'payment-qr-switch',
          'payment-qr-kind',
          'payment-qr-remove',
          'payment-qr-caption',
          'payment-qr-note',
          'payment-qr-when-unpaid',
          'payment-qr-receipts',
          'payment-qr-statements',
        ]) {
          await reach(tester, find.byKey(ValueKey(key)));
          expect(tester.takeException(), isNull, reason: key);
        }
        // The preview's paper with both blocks on it.
        expect(preview, findsOneWidget);
      });

      testWidgets('the dialogs fit with the keyboard up (${locale.languageCode})',
          (tester) async {
        tester.view.devicePixelRatio = 2;
        tester.view.physicalSize = phone * 2;
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final dialogs = <Widget>[
          const PaymentQrConfirmDialog(text: emv, settings: InvoiceSettings()),
          PaymentQrUnreadDialog(
            picture: QrPicture.fromBitmap(qrBitmapFromImage(qrPhoto(upi))!),
          ),
          const PaymentQrTextDialog(
            title: 'Line under the code',
            initial: 'بنك سورية الدولي — أبو أحمد',
            hint: 'For example the bank name or the account holder',
          ),
          const ContactEditDialog(
            initial: InvoiceContact(
              name: 'عبد الرحمن محمد الأحمد الحسن',
              phone: '٠٩٤٤ ١٢٣ ٤٥٦',
            ),
          ),
        ];
        for (final dialog in dialogs) {
          await tester.pumpWidget(
            MaterialApp(
              key: UniqueKey(),
              locale: locale,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () =>
                        showDialog<void>(context: context, builder: (_) => dialog),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await animated(tester);
          expect(tester.takeException(), isNull, reason: '${dialog.runtimeType}');
          tester.view.viewInsets = const FakeViewPadding(bottom: 600);
          await settle(tester, 4);
          expect(tester.takeException(), isNull, reason: '${dialog.runtimeType} + keyboard');
          tester.view.resetViewInsets();
        }
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => const QrSourceSheet(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
            locale: locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        );
        await tester.tap(find.text('open'));
        await animated(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('the settings notifier rolls back a change it could not save', () async {
    // Covered through the screen above for the happy path; here the write
    // fails (the database is closed) and the state goes back.
    final local = await openTestDb();
    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(local)],
    );
    addTearDown(container.dispose);
    final before = await container.read(invoiceSettingsProvider.future);
    await local.close();
    await expectLater(
      container.read(invoiceSettingsProvider.notifier).changeAudited(
            (s) => s.copyWith(paymentQrEnabled: true, paymentQrText: upi),
            action: AuditAction.paymentQrSet,
          ),
      throwsA(anything),
    );
    expect(container.read(invoiceSettingsProvider).value!.paymentQrText,
        before.paymentQrText);
  });
}
