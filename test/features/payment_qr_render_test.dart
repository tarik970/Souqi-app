import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/print_geometry.dart';
import 'package:souqi/core/printing/print_job.dart';
import 'package:souqi/core/printing/qr_bitmap.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/core/printing/widget_capture.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/domain/models/debt.dart';
import 'package:souqi/domain/models/invoice_extras.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/features/debts/debt_papers.dart';
import 'package:souqi/features/invoice/contact_lines.dart';
import 'package:souqi/features/invoice/invoice_output.dart';
import 'package:souqi/features/invoice/invoice_view.dart';
import 'package:souqi/features/invoice/payment_qr.dart';
import 'package:souqi/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/qr_grid_decoder.dart';
import '../data/db_test_utils.dart';
import 'invoice_test_utils.dart';

/// The payment QR and the contact numbers ON THE PAPER: the code read from
/// the owner's picture is drawn again sharp and reads back to the same
/// text — on its own, inside the printed invoice at every paper and printer
/// width, in the shared image and the PDF — and it sits after the totals,
/// before the footer; contact lines keep their digits in order inside
/// Arabic.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<T> real<T extends Object>(
    WidgetTester tester,
    Future<T> Function() action,
  ) async {
    final result = await tester.runAsync(action);
    if (result == null) throw StateError('runAsync returned no result');
    return result;
  }

  InvoiceSettings withQr(InvoiceSettings s, [String text = emv]) =>
      s.copyWith(paymentQrEnabled: true, paymentQrText: text);

  /// The paper widths and printer languages the code must survive.
  final papers = <({String name, InvoiceSettings settings})>[
    (name: '80 mm ESC/POS, 512 dots', settings: const InvoiceSettings()),
    (
      name: '80 mm ESC/POS, whole 72 mm head (576 dots)',
      settings: const InvoiceSettings(printableDotsOverride: 576),
    ),
    (
      name: '80 mm TSPL label head (608 dots)',
      settings: const InvoiceSettings(
        printerAddress: 'AA:BB',
        printerLanguages: {'AA:BB': PrinterLanguage.tspl},
        printableDotsOverride: 608,
      ),
    ),
    (
      name: '58 mm ESC/POS (384 dots)',
      settings: InvoiceSettings(
        paperWidthMm: 58,
        sideMarginMm: defaultSideMarginFor(58),
      ),
    ),
    (
      name: '58 mm TSPL (384 dots)',
      settings: InvoiceSettings(
        paperWidthMm: 58,
        sideMarginMm: defaultSideMarginFor(58),
        printerAddress: 'AA:BB',
        printerLanguages: const {'AA:BB': PrinterLanguage.tspl},
      ),
    ),
  ];

  /// Puts [paper] on screen at its true width in dots, so where things sit
  /// can be measured — exactly where the off-screen capture puts them.
  Future<void> pumpPaper(WidgetTester tester, Widget paper, int dots) async {
    tester.view.physicalSize = const Size(1400, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: dots.toDouble(), child: paper),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  }

  /// Reads the code inside [rect] of a picture ([scale] pixels per dot).
  String? readCodeAt(
    Rect rect, {
    required int width,
    required int height,
    required bool Function(int x, int y) isBlack,
    double scale = 1,
  }) {
    // The quiet zone is white: a little more than the box changes nothing.
    final left = (rect.left * scale).round() - 2;
    final top = (rect.top * scale).round() - 2;
    final w = (rect.width * scale).round() + 4;
    final h = (rect.height * scale).round() + 4;
    return decodeQrGrid(
      width: w,
      height: h,
      isBlack: (x, y) {
        final px = left + x;
        final py = top + y;
        if (px < 0 || py < 0 || px >= width || py >= height) return false;
        return isBlack(px, py);
      },
    );
  }

  bool rgbaBlack(RgbaImage image, int x, int y) =>
      image.rgba[(y * image.width + x) * 4] < 128;

  group('decode → clean redraw → decodes back', () {
    for (final paper in [80.0, 58.0]) {
      for (final ratio in [1.0, 2.0]) {
        testWidgets('${paper.round()} mm paper at ${ratio.round()}× '
            '(${ratio == 1 ? 'printer' : 'share'})', (tester) async {
          // The owner's picture — a grey screenshot — read the way ML Kit
          // reads it on the phone.
          final read = decodeRgba(qrPhoto(emv, dark: 60, light: 190));
          expect(read, emv);

          final s = withQr(
            InvoiceSettings(
              paperWidthMm: paper,
              sideMarginMm: defaultSideMarginFor(paper),
            ),
            read!,
          );
          final image = await real(
            tester,
            () => captureWidget(
              ColoredBox(
                color: const Color(0xFFFFFFFF),
                child: PaymentQrSymbol(
                  text: read,
                  picture: null,
                  targetDots: paymentQrTargetDots(s),
                ),
              ),
              logicalWidth: s.printableDots,
              pixelRatio: ratio,
            ),
          );

          // Sharp: every pixel is pure black or pure white — no grey edge
          // for the 1-bit conversion to guess about.
          for (var i = 0; i < image.rgba.length; i += 4) {
            final v = image.rgba[i];
            expect(v == 0 || v == 255, isTrue, reason: 'pixel ${i ~/ 4} is $v');
            expect(image.rgba[i + 1], v);
            expect(image.rgba[i + 2], v);
          }

          var minX = image.width, maxX = -1, minY = image.height, maxY = -1;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              if (!rgbaBlack(image, x, y)) continue;
              if (x < minX) minX = x;
              if (x > maxX) maxX = x;
              if (y < minY) minY = y;
              if (y > maxY) maxY = y;
            }
          }
          final modules = paymentQrMatrix(read)!.moduleCount;
          final span = maxX - minX + 1;
          // Whole pixels per module, the same for every module.
          expect(span % modules, 0, reason: '$span px for $modules modules');
          final dot = span ~/ modules;
          expect(
            dot,
            paymentQrModuleDots(
                  modules: modules,
                  targetDots: paymentQrTargetDots(s),
                  maxWidth: s.printableDots.toDouble(),
                ) *
                ratio,
          );
          for (var r = 0; r < modules; r++) {
            for (var c = 0; c < modules; c++) {
              final first = rgbaBlack(image, minX + c * dot, minY + r * dot);
              for (var y = 0; y < dot; y++) {
                for (var x = 0; x < dot; x++) {
                  expect(
                    rgbaBlack(image, minX + c * dot + x, minY + r * dot + y),
                    first,
                    reason: 'module $r,$c is not one solid square',
                  );
                }
              }
            }
          }
          // The quiet zone: 4 white modules on every side.
          expect(minY, 4 * dot);
          expect(image.height - 1 - maxY, 4 * dot);
          expect(minX, greaterThanOrEqualTo(4 * dot));
          expect(image.width - 1 - maxX, greaterThanOrEqualTo(4 * dot));
          // Centred.
          expect((minX - (image.width - 1 - maxX)).abs(), lessThanOrEqualTo(ratio));
          // About 35–40 mm on 80 mm paper, about 30 mm on 58 mm.
          final mm = dotsToMm((span / ratio).round(), s.printerDpi);
          if (paper == 80) {
            expect(mm, inInclusiveRange(35, 40));
          } else {
            expect(mm, inInclusiveRange(27, 32));
          }

          expect(
            decodeQrGrid(
              width: image.width,
              height: image.height,
              isBlack: (x, y) => rgbaBlack(image, x, y),
            ),
            emv,
          );
        });
      }
    }

    testWidgets('the 1-bit printer image of the code still reads',
        (tester) async {
      final s = withQr(const InvoiceSettings(), upi);
      final image = await real(
        tester,
        () => captureWidget(
          ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: PaymentQrSymbol(
              text: upi,
              picture: null,
              targetDots: paymentQrTargetDots(s),
            ),
          ),
          logicalWidth: s.printableDots,
        ),
      );
      final mono = toMonochrome(image);
      expect(
        decodeQrGrid(width: mono.width, height: mono.height, isBlack: mono.isBlack),
        upi,
      );
    });

    testWidgets('a picture kept "as is" prints by nearest neighbour, '
        'pure black and white', (tester) async {
      final bitmap = qrBitmapFromImage(qrPhoto(upi, dark: 80, light: 175))!;
      final s = const InvoiceSettings().copyWith(
        paymentQrEnabled: true,
        paymentQrPicture: () => QrPicture.fromBitmap(bitmap),
      );
      expect(s.hasPaymentQr, isTrue);
      final image = await real(
        tester,
        () => captureWidget(
          ColoredBox(
            color: const Color(0xFFFFFFFF),
            child: PaymentQrSymbol(
              text: '',
              picture: s.paymentQrPicture,
              targetDots: paymentQrTargetDots(s),
            ),
          ),
          logicalWidth: s.printableDots,
        ),
      );
      for (var i = 0; i < image.rgba.length; i += 4) {
        expect(image.rgba[i] == 0 || image.rgba[i] == 255, isTrue);
      }
      // A clean picture survives the scaling (a real photo may not: the
      // settings say so).
      expect(
        decodeQrGrid(
          width: image.width,
          height: image.height,
          isBlack: (x, y) => rgbaBlack(image, x, y),
        ),
        upi,
      );
    });
  });

  group('on the printed invoice', () {
    for (final paper in papers) {
      for (final language in ['ar', 'en']) {
        testWidgets('${paper.name}, ${language == 'ar' ? 'Arabic' : 'English'}',
            (tester) async {
          final l10n = lookupAppLocalizations(Locale(language));
          final s = withQr(paper.settings).copyWith(
            language: language,
            shopName: language == 'ar' ? 'بقالة البركة' : 'Al-Baraka',
            footerText: language == 'ar' ? 'شكراً لزيارتكم' : 'Thank you',
            paymentQrNote: language == 'ar'
                ? 'بنك سورية الدولي — أبو أحمد'
                : 'Bank of Syria — Abu Ahmad',
          );
          final dots = s.printableDots;
          final invoice = crossCurrencyInvoice(customerName: 'Ahmad');
          Widget paperView() => InvoiceView(
                invoice: invoice,
                settings: s,
                currencies: testCurrencies,
              );
          await pumpPaper(tester, paperView(), dots);

          final symbol = find.byKey(const ValueKey('paper-payment-qr-symbol'));
          expect(symbol, findsOneWidget);
          final rect = tester.getRect(symbol);
          // After the totals, before the footer; the lines above and under.
          final total = tester.getRect(find.text(l10n.totalLabel));
          final footer = tester.getRect(find.text(s.footerText));
          final caption = tester
              .getRect(find.byKey(const ValueKey('paper-payment-qr-caption')));
          final note =
              tester.getRect(find.byKey(const ValueKey('paper-payment-qr-note')));
          expect(total.bottom, lessThanOrEqualTo(caption.top));
          expect(caption.bottom, lessThanOrEqualTo(rect.top));
          expect(rect.bottom, lessThanOrEqualTo(note.top));
          expect(note.bottom, lessThanOrEqualTo(footer.top));
          expect(find.text(l10n.paymentQrDefaultCaption), findsOneWidget);
          // Centred on the paper, and inside it.
          expect((rect.center.dx - dots / 2).abs(), lessThanOrEqualTo(1));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(dots));

          // The very bytes of the print job: the 1-bit image reads back.
          final image = await real(
            tester,
            () => captureWidget(paperView(), logicalWidth: dots),
          );
          expect(image.width, dots);
          final mono = toMonochrome(image);
          expect(
            readCodeAt(
              rect,
              width: mono.width,
              height: mono.height,
              isBlack: mono.isBlack,
            ),
            emv,
          );
          final job = buildPrintJob(mono, format: s.printFormat);
          if (s.printerLanguage == PrinterLanguage.tspl) {
            expect(String.fromCharCodes(job.take(200)), contains('SIZE'));
          } else {
            expect(job.take(2), [0x1B, 0x40]); // ESC @
          }
        });
      }
    }

    testWidgets('a voided invoice asks nobody to pay', (tester) async {
      final s = withQr(const InvoiceSettings(language: 'en'));
      await pumpPaper(
        tester,
        InvoiceView(
          invoice: sypInvoice().copyWith(voidedAt: DateTime(2026, 11, 25)),
          settings: s,
          currencies: testCurrencies,
        ),
        s.printableDots,
      );
      expect(find.byKey(const ValueKey('paper-payment-qr')), findsNothing);
    });
  });

  group('the shared image and the PDF carry it', () {
    late AppDatabase database;
    late ProviderContainer container;

    Future<void> open(WidgetTester tester) async {
      database = await real(tester, openTestDb);
      await tester.runAsync(() async {
        for (final entry in {
          SettingsKeys.paymentQrEnabled: '1',
          SettingsKeys.paymentQrText: upi,
          SettingsKeys.invoiceLanguage: 'ar',
          SettingsKeys.contactsEnabled: '1',
          SettingsKeys.contacts: InvoiceContact.listToJson(const [
            InvoiceContact(name: 'أبو أحمد', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
          ]),
        }.entries) {
          await database.db.insert('settings', {
            'key': entry.key,
            'value': entry.value,
            'updated_at': 0,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(database)],
      );
      addTearDown(() async {
        container.dispose();
        await database.close();
      });
    }

    testWidgets('share PNG (2×) and PDF', (tester) async {
      await open(tester);
      final output = container.read(invoiceOutputProvider);
      final invoice = sypInvoice();
      final settings = InvoiceSettings.fromMap({
        SettingsKeys.paymentQrEnabled: '1',
        SettingsKeys.paymentQrText: upi,
        SettingsKeys.invoiceLanguage: 'ar',
        SettingsKeys.contactsEnabled: '1',
        SettingsKeys.contacts: InvoiceContact.listToJson(const [
          InvoiceContact(name: 'أبو أحمد', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
        ]),
      });
      // Where the share render puts the code.
      await pumpPaper(
        tester,
        InvoiceView(
          invoice: invoice,
          settings: settings,
          currencies: testCurrencies,
          padding: EdgeInsets.all(settings.baseFontSize.toDouble()),
        ),
        settings.shareDots,
      );
      final rect =
          tester.getRect(find.byKey(const ValueKey('paper-payment-qr-symbol')));
      expect(find.text('0944 123 456'), findsOneWidget);

      final png = await real(tester, () => output.sharePng(invoice));
      final decoded = decodePngRgb(png)!;
      expect(decoded.width, 2 * settings.shareDots);
      bool black(int x, int y) => decoded.rgb[(y * decoded.width + x) * 3] < 128;
      expect(
        readCodeAt(
          rect,
          width: decoded.width,
          height: decoded.height,
          isBlack: black,
          scale: sharePixelRatio,
        ),
        upi,
      );

      final pdf = await real(tester, () => output.sharePdf(invoice));
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');

      // And the printer render reads it from the same settings.
      final print = await real(tester, () => output.renderForPrinter(invoice));
      await pumpPaper(
        tester,
        InvoiceView(invoice: invoice, settings: settings, currencies: testCurrencies),
        settings.printableDots,
      );
      final printRect =
          tester.getRect(find.byKey(const ValueKey('paper-payment-qr-symbol')));
      final mono = toMonochrome(print);
      expect(
        readCodeAt(
          printRect,
          width: mono.width,
          height: mono.height,
          isBlack: mono.isBlack,
        ),
        upi,
      );
    });
  });

  group('"only when something is left to pay"', () {
    final paid = sypInvoice();
    final partial = paid.copyWith(paidMinor: paid.totalMinor ~/ 2);
    final credit = paid.copyWith(paidMinor: 0);
    // The rest taken from the customer's credit balance: nothing left.
    final coveredByCredit =
        paid.copyWith(paidMinor: 0, creditUsedMinor: paid.totalMinor);
    final voided = partial.copyWith(voidedAt: DateTime(2026, 11, 25));

    final always = withQr(const InvoiceSettings());
    final unpaid = always.copyWith(paymentQrWhen: PaymentQrWhen.unpaidOnly);

    test('invoices', () {
      expect(paymentQrOnInvoice(always, paid), isTrue);
      expect(paymentQrOnInvoice(always, credit), isTrue);
      expect(paymentQrOnInvoice(unpaid, paid), isFalse);
      expect(paymentQrOnInvoice(unpaid, partial), isTrue);
      expect(paymentQrOnInvoice(unpaid, credit), isTrue);
      expect(paymentQrOnInvoice(unpaid, coveredByCredit), isFalse);
      expect(paymentQrOnInvoice(always, voided), isFalse);
      expect(paymentQrOnInvoice(unpaid, voided), isFalse);
      // Off, or on with nothing chosen: never.
      expect(
        paymentQrOnInvoice(always.copyWith(paymentQrEnabled: false), credit),
        isFalse,
      );
      expect(
        paymentQrOnInvoice(always.copyWith(paymentQrText: ''), credit),
        isFalse,
      );
    });

    test('without the debt ledger every sale is paid: it prints on all', () {
      FeatureGate.applyWithout([Feature.debt]);
      addTearDown(FeatureGate.reset);
      expect(paymentQrOnInvoice(unpaid, paid), isTrue);
      expect(
        paymentQrOnStatement(unpaid, closingBalanceBaseMinor: 5000),
        isFalse,
      );
    });

    test('receipts and statements', () {
      final receipts = unpaid.copyWith(paymentQrOnReceipts: true);
      expect(paymentQrOnReceipt(unpaid, balanceAfterBaseMinor: 500), isFalse,
          reason: 'receipts are off by default');
      expect(paymentQrOnReceipt(receipts, balanceAfterBaseMinor: 500), isTrue);
      expect(paymentQrOnReceipt(receipts, balanceAfterBaseMinor: 0), isFalse);
      expect(
        paymentQrOnReceipt(
          receipts.copyWith(paymentQrWhen: PaymentQrWhen.always),
          balanceAfterBaseMinor: 0,
        ),
        isTrue,
      );
      expect(
        paymentQrOnReceipt(receipts, balanceAfterBaseMinor: 500, reversed: true),
        isFalse,
      );
      expect(paymentQrOnStatement(unpaid, closingBalanceBaseMinor: 1), isTrue);
      expect(paymentQrOnStatement(unpaid, closingBalanceBaseMinor: 0), isFalse);
      expect(paymentQrOnStatement(unpaid, closingBalanceBaseMinor: -300), isFalse);
      expect(
        paymentQrOnStatement(
          unpaid.copyWith(paymentQrOnStatements: false),
          closingBalanceBaseMinor: 100,
        ),
        isFalse,
      );
    });

    testWidgets('the paper follows the rule', (tester) async {
      final s = unpaid.copyWith(language: 'en');
      await pumpPaper(
        tester,
        InvoiceView(invoice: paid, settings: s, currencies: testCurrencies),
        s.printableDots,
      );
      expect(find.byKey(const ValueKey('paper-payment-qr')), findsNothing);
      await pumpPaper(
        tester,
        InvoiceView(invoice: partial, settings: s, currencies: testCurrencies),
        s.printableDots,
      );
      expect(find.byKey(const ValueKey('paper-payment-qr')), findsOneWidget);
    });
  });

  group('contact numbers', () {
    const contacts = [
      InvoiceContact(name: 'أبو أحمد', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
      InvoiceContact(name: 'المحل', phone: '+963 11-222 3333'),
      InvoiceContact(phone: '0933 765 432'),
    ];

    test('printed with the invoice\'s digits, signs where they were typed', () {
      expect(contactPhoneForPaper('٠٩٤٤ ١٢٣ ٤٥٦', 'ar'), '0944 123 456');
      expect(contactPhoneForPaper('۰۹۴۴-۱۲۳', 'en'), '0944-123');
      expect(contactPhoneForPaper(' +963 11 222 ', 'ar'), '+963 11 222');
    });

    /// The x of the left edge of character [index] of the text keyed [key].
    double charX(WidgetTester tester, Key key, int index) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
      );
      return paragraph.localToGlobal(
        paragraph.getOffsetForCaret(TextPosition(offset: index), Rect.zero),
      ).dx;
    }

    for (final language in ['ar', 'en']) {
      for (final position in ContactsPosition.values) {
        testWidgets('$language, ${position.name}: digits keep their order',
            (tester) async {
          final l10n = lookupAppLocalizations(Locale(language));
          final s = InvoiceSettings(
            language: language,
            shopName: language == 'ar' ? 'بقالة البركة' : 'Al-Baraka',
            footerText: language == 'ar' ? 'شكراً لزيارتكم' : 'Thank you',
            showContacts: true,
            contacts: contacts,
            contactsPosition: position,
          );
          await pumpPaper(
            tester,
            InvoiceView(invoice: sypInvoice(), settings: s, currencies: testCurrencies),
            s.printableDots,
          );
          for (var i = 0; i < contacts.length; i++) {
            final key = ValueKey('paper-contact-phone-$i');
            final phone = tester.widget<Text>(find.byKey(key));
            expect(phone.textDirection, TextDirection.ltr);
            // Left to right on the paper: the first digit is left of the
            // last, whatever the language of the line.
            final text = phone.data!;
            expect(charX(tester, key, 0), lessThan(charX(tester, key, text.length - 1)));
          }
          expect(find.text('0944 123 456'), findsOneWidget);
          expect(find.text('+963 11-222 3333'), findsOneWidget);
          expect(find.text('أبو أحمد:'), findsOneWidget);
          // The name sits on the reading side of its number.
          final name = tester.getRect(find.text('أبو أحمد:'));
          final number = tester.getRect(find.text('0944 123 456'));
          if (language == 'ar') {
            expect(name.left, greaterThanOrEqualTo(number.right));
          } else {
            expect(name.right, lessThanOrEqualTo(number.left));
          }

          final lines = tester.getRect(find.byKey(const ValueKey('paper-contacts')));
          final shop = tester.getRect(find.text(s.shopName));
          final footer = tester.getRect(find.text(s.footerText));
          final number0 = tester.getRect(
            find.text(l10n.invoiceNoLabel('7')),
          );
          if (position == ContactsPosition.header) {
            expect(shop.bottom, lessThanOrEqualTo(lines.top));
            expect(lines.bottom, lessThanOrEqualTo(number0.top));
          } else {
            final total = tester.getRect(find.text(l10n.totalLabel));
            expect(total.bottom, lessThanOrEqualTo(lines.top));
            expect(lines.bottom, lessThanOrEqualTo(footer.top));
          }
        });
      }
    }

    testWidgets('58 mm, long names, large font: nothing overflows',
        (tester) async {
      final s = InvoiceSettings(
        language: 'ar',
        paperWidthMm: 58,
        sideMarginMm: defaultSideMarginFor(58),
        baseFontSize: 30,
        showContacts: true,
        contacts: const [
          InvoiceContact(name: 'عبد الرحمن محمد الأحمد الحسن', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
          InvoiceContact(name: 'Abu Ahmad the grocer', phone: '+963 944 123 456'),
          InvoiceContact(phone: '011 222 3333'),
        ],
        paymentQrEnabled: true,
        paymentQrText: emv,
        paymentQrNote: 'بنك سورية الدولي — حساب ٠١٢٣ ٤٥٦٧ ٨٩',
      );
      await pumpPaper(
        tester,
        InvoiceView(invoice: sypInvoice(), settings: s, currencies: testCurrencies),
        s.printableDots,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('paper-payment-qr-symbol')), findsOneWidget);
    });
  });

  group('receipts and statements', () {
    final receiptEntry = DebtEntry(
      id: 9,
      customerId: 1,
      type: DebtEntryType.payment,
      direction: -1,
      amountBaseMinor: 4000,
      paymentMethod: PaymentMethod.cash,
      receiptNo: 37,
      balanceBeforeBaseMinor: 10000,
      createdAt: DateTime(2026, 11, 25, 14, 35),
      recordedAt: DateTime(2026, 11, 25, 14, 35),
    );
    final receipt = ReceiptData(
      payment: receiptEntry,
      customerName: 'Ahmad Hasan',
      baseCurrencyCode: 'SYP',
    );
    final debtEntry = DebtEntry(
      id: 1,
      customerId: 1,
      type: DebtEntryType.debt,
      direction: 1,
      amountBaseMinor: 8000,
      invoiceNo: 152,
      createdAt: DateTime(2026, 11, 5),
      recordedAt: DateTime(2026, 11, 5),
    );
    final statement = StatementData(
      statement: AccountStatement(
        from: DateTime(2026, 11),
        to: DateTime(2026, 12),
        openingBalanceBaseMinor: 15000,
        lines: [LedgerLine(entry: debtEntry, balanceAfterBaseMinor: 23000)],
      ),
      customerName: 'Ahmad Hasan',
      baseCurrencyCode: 'SYP',
      printedAt: DateTime(2026, 11, 25, 16),
    );

    for (final language in ['ar', 'en']) {
      testWidgets('$language: statement yes by default, receipt when asked, '
          'contacts on both', (tester) async {
        final s = withQr(InvoiceSettings(
          language: language,
          footerText: 'footer',
          showContacts: true,
          contacts: const [
            InvoiceContact(name: 'أبو أحمد', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
          ],
          contactsPosition: ContactsPosition.footer,
        ));
        final qr = find.byKey(const ValueKey('paper-payment-qr'));

        await pumpPaper(
          tester,
          StatementView(data: statement, settings: s, currencies: testCurrencies),
          s.printableDots,
        );
        expect(qr, findsOneWidget);
        expect(find.text('0944 123 456'), findsOneWidget);
        // Before the footer, contacts between the code and the footer.
        final code = tester.getRect(qr);
        final lines = tester.getRect(find.byKey(const ValueKey('paper-contacts')));
        final footer = tester.getRect(find.text('footer'));
        expect(code.bottom, lessThanOrEqualTo(lines.top));
        expect(lines.bottom, lessThanOrEqualTo(footer.top));

        await pumpPaper(
          tester,
          ReceiptView(receipt: receipt, settings: s, currencies: testCurrencies),
          s.printableDots,
        );
        expect(qr, findsNothing, reason: 'receipts are off by default');
        expect(find.text('0944 123 456'), findsOneWidget);

        final withReceipts = s.copyWith(paymentQrOnReceipts: true);
        await pumpPaper(
          tester,
          ReceiptView(
            receipt: receipt,
            settings: withReceipts,
            currencies: testCurrencies,
          ),
          s.printableDots,
        );
        expect(qr, findsOneWidget);
        // The code read back from the receipt's own print.
        final rect =
            tester.getRect(find.byKey(const ValueKey('paper-payment-qr-symbol')));
        final image = await real(
          tester,
          () => captureWidget(
            ReceiptView(
              receipt: receipt,
              settings: withReceipts,
              currencies: testCurrencies,
            ),
            logicalWidth: s.printableDots,
          ),
        );
        final mono = toMonochrome(image);
        expect(
          readCodeAt(rect,
              width: mono.width, height: mono.height, isBlack: mono.isBlack),
          emv,
        );
      });
    }
  });
}
