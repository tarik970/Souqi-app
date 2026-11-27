import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/printing/png_encoder.dart';
import 'package:souqi/core/printing/qr_bitmap.dart';
import 'package:souqi/core/printing/raster.dart';
import 'package:souqi/domain/models/invoice_extras.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/features/invoice/payment_qr.dart';

import 'qr_grid_decoder.dart';

void main() {
  group('the test decoder (stands in for ML Kit)', () {
    for (final text in [upi, emv, arabic]) {
      test('reads what the qr package draws: ${text.substring(0, 12)}…', () {
        expect(decodeRgba(qrPhoto(text)), text);
        expect(decodeRgba(qrPhoto(text, scale: 3, left: 5, top: 9)), text);
      });
    }

    test('refuses a code with a single wrong module', () {
      final photo = qrPhoto(upi, left: 0, top: 0);
      // A module in the data area (bottom-right corner region), flipped.
      final qr = QrImage(QrCode.fromData(data: upi, errorCorrectLevel: QrErrorCorrectLevel.M));
      final n = qr.moduleCount;
      for (var y = (n - 3) * 7; y < (n - 2) * 7; y++) {
        for (var x = (n - 3) * 7; x < (n - 2) * 7; x++) {
          final i = (y * photo.width + x) * 4;
          final v = photo.rgba[i] < 128 ? 205 : 45;
          photo.rgba[i] = v;
          photo.rgba[i + 1] = v;
          photo.rgba[i + 2] = v;
        }
      }
      expect(decodeRgba(photo), isNull);
    });
  });

  group('PNG back to pixels', () {
    test('reads the app\'s own PNG exactly', () {
      final rgb = Uint8List.fromList([
        for (var i = 0; i < 5 * 3; i++) ...[i * 7 % 256, i * 13 % 256, i * 29 % 256],
      ]);
      final png = encodePngRgb(width: 5, height: 3, rgb: rgb);
      final back = decodePngRgb(png)!;
      expect((back.width, back.height), (5, 3));
      expect(back.rgb, rgb);
    });

    test('reads every row filter (a PNG written by another encoder)', () {
      final picture = img.Image(width: 23, height: 17);
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 23; x++) {
          picture.setPixelRgb(x, y, (x * 11) % 256, (y * 15) % 256, (x * y) % 256);
        }
      }
      final png = Uint8List.fromList(img.encodePng(picture));
      final back = decodePngRgb(png)!;
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 23; x++) {
          final i = (y * 23 + x) * 3;
          expect(
            [back.rgb[i], back.rgb[i + 1], back.rgb[i + 2]],
            [(x * 11) % 256, (y * 15) % 256, (x * y) % 256],
            reason: 'pixel $x,$y',
          );
        }
      }
    });

    test('says null for what is not a PNG', () {
      expect(decodePngRgb(Uint8List.fromList(List.filled(40, 7))), isNull);
    });
  });

  group('"use the image as is"', () {
    test('Otsu splits a dim, grey picture between its two levels', () {
      final luma = Uint8List.fromList([
        for (var i = 0; i < 300; i++) 60 + i % 7,
        for (var i = 0; i < 700; i++) 150 + i % 9,
      ]);
      final t = otsuThreshold(luma);
      expect(t, greaterThan(66));
      expect(t, lessThanOrEqualTo(150));
    });

    test('crops to the code, pure black and white, and stays readable', () {
      final photo = qrPhoto(emv, dark: 70, light: 170);
      final bitmap = qrBitmapFromImage(photo)!;
      final qr = QrImage(QrCode.fromData(data: emv, errorCorrectLevel: QrErrorCorrectLevel.M));
      // Cropped exactly to the code: the margins are gone.
      expect(bitmap.side, qr.moduleCount * 7);
      expect(bitmap.isBlack(0, 0), isTrue, reason: 'finder corner');
      expect(bitmap.bits.every((b) => b == 0 || b == 1), isTrue);
      expect(decodeBitmap(bitmap), emv);
    });

    test('a big photo is scaled down by nearest neighbour, still readable', () {
      final photo = qrPhoto(upi, scale: 19);
      final bitmap = qrBitmapFromImage(photo)!;
      expect(bitmap.side, maxQrBitmapSide);
      expect(decodeBitmap(bitmap), upi);
    });

    test('a speck of dust does not stretch the crop', () {
      final photo = qrPhoto(upi, right: 140, bottom: 120);
      // One dark pixel far from the code.
      final i = ((photo.height - 3) * photo.width + photo.width - 3) * 4;
      photo.rgba[i] = photo.rgba[i + 1] = photo.rgba[i + 2] = 0;
      final bitmap = qrBitmapFromImage(photo)!;
      expect(decodeBitmap(bitmap), upi);
    });

    test('a picture without contrast is refused', () {
      final flat = RgbaImage(
        width: 40,
        height: 40,
        rgba: Uint8List.fromList([
          for (var i = 0; i < 1600; i++) ...[120 + i % 20, 120, 120, 255],
        ]),
      );
      expect(qrBitmapFromImage(flat), isNull);
    });

    test('the kept bitmap survives the PNG it is stored as', () {
      final bitmap = qrBitmapFromImage(qrPhoto(arabic))!;
      final back = QrPicture.fromPng(QrPicture.fromBitmap(bitmap).png)!;
      expect(back.bitmap.side, bitmap.side);
      expect(back.bitmap.bits, bitmap.bits);
      expect(QrPicture.fromPng(Uint8List.fromList([1, 2, 3])), isNull);
    });
  });

  group('stored with the settings', () {
    test('every new setting goes through the settings table and back', () {
      final picture = QrPicture.fromBitmap(qrBitmapFromImage(qrPhoto(upi))!);
      final s = const InvoiceSettings().copyWith(
        paymentQrEnabled: true,
        paymentQrText: emv,
        paymentQrPicture: () => picture,
        paymentQrCaption: '',
        paymentQrNote: 'بنك سورية الدولي — أبو أحمد',
        paymentQrWhen: PaymentQrWhen.unpaidOnly,
        paymentQrOnReceipts: true,
        paymentQrOnStatements: false,
        showContacts: true,
        contacts: const [
          InvoiceContact(name: 'أبو أحمد', phone: '٠٩٤٤ ١٢٣ ٤٥٦'),
          InvoiceContact(phone: '+963 11 222 3333'),
        ],
        contactsPosition: ContactsPosition.footer,
      );
      final back = InvoiceSettings.fromMap(s.toMap());
      expect(back.paymentQrEnabled, isTrue);
      expect(back.paymentQrText, emv);
      expect(back.paymentQrPicture!.bitmap.bits, picture.bitmap.bits);
      expect(back.paymentQrCaption, '', reason: 'an emptied line stays empty');
      expect(back.paymentQrNote, 'بنك سورية الدولي — أبو أحمد');
      expect(back.paymentQrWhen, PaymentQrWhen.unpaidOnly);
      expect(back.paymentQrOnReceipts, isTrue);
      expect(back.paymentQrOnStatements, isFalse);
      expect(back.showContacts, isTrue);
      expect(back.contacts, s.contacts);
      expect(back.contactsPosition, ContactsPosition.footer);
    });

    test('defaults: off, every invoice, statements yes, receipts no', () {
      final s = InvoiceSettings.fromMap(const {});
      expect(s.paymentQrEnabled, isFalse);
      expect(s.hasPaymentQr, isFalse);
      expect(s.paymentQrCaption, isNull, reason: 'the default line follows the language');
      expect(s.paymentQrWhen, PaymentQrWhen.always);
      expect(s.paymentQrOnReceipts, isFalse);
      expect(s.paymentQrOnStatements, isTrue);
      expect(s.showContacts, isFalse);
      expect(s.contacts, isEmpty);
      expect(s.contactsPosition, ContactsPosition.header);
      // Never written while it was never set.
      expect(s.toMap().containsKey(SettingsKeys.paymentQrCaption), isFalse);
    });

    test('they belong to the shop, so backups carry them', () {
      for (final key in [
        SettingsKeys.paymentQrEnabled,
        SettingsKeys.paymentQrText,
        SettingsKeys.paymentQrImageBase64,
        SettingsKeys.paymentQrCaption,
        SettingsKeys.paymentQrNote,
        SettingsKeys.contacts,
        SettingsKeys.contactsEnabled,
      ]) {
        expect(SettingsKeys.deviceBoundKeys, isNot(contains(key)));
      }
    });

    test('the contact list is at most three and never throws', () {
      expect(InvoiceContact.listFromJson('not json'), isEmpty);
      expect(InvoiceContact.listFromJson('{"a":1}'), isEmpty);
      final four = InvoiceContact.listToJson(const [
        InvoiceContact(phone: '1111'),
        InvoiceContact(phone: '2222'),
        InvoiceContact(phone: '3333'),
        InvoiceContact(phone: '4444'),
      ]);
      expect(InvoiceContact.listFromJson(four).map((c) => c.phone), ['1111', '2222', '3333']);
      expect(
        InvoiceContact.listFromJson('[{"name":"x"},{"phone":" 0944 "}]'),
        const [InvoiceContact(phone: '0944')],
      );
    });
  });

  group('size on paper', () {
    test('about 38 mm on 80 mm paper, about 30 mm on 58 mm', () {
      expect(paymentQrTargetDots(const InvoiceSettings()), 304);
      expect(
        paymentQrTargetDots(const InvoiceSettings(paperWidthMm: 58)),
        240,
      );
    });

    test('whole dots per module, the quiet zone always fits', () {
      // 33 modules (version 4) on 80 mm: 9 dots each = 297 dots ≈ 37 mm.
      expect(paymentQrModuleDots(modules: 33, targetDots: 304, maxWidth: 512), 9);
      // On 58 mm: 7 dots = 231 dots ≈ 29 mm.
      expect(paymentQrModuleDots(modules: 33, targetDots: 240, maxWidth: 384), 7);
      // A narrow box shrinks the module until code + quiet zone fit.
      expect(paymentQrModuleDots(modules: 33, targetDots: 304, maxWidth: 200), 4);
      expect(paymentQrModuleDots(modules: 177, targetDots: 240, maxWidth: 384), 1);
    });
  });
}
