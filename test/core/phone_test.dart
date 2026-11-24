import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/normalize.dart';

void main() {
  group('toInternationalPhone', () {
    test('a local number: the trunk zero becomes the country code', () {
      expect(toInternationalPhone('0944123456'), '963944123456');
      expect(toInternationalPhone('0944 123 456'), '963944123456');
      expect(toInternationalPhone('0944-123-456'), '963944123456');
      expect(toInternationalPhone('(0944) 123456'), '963944123456');
    });

    test('+963 is already international', () {
      expect(toInternationalPhone('+963944123456'), '963944123456');
      expect(toInternationalPhone('+963 944 123 456'), '963944123456');
    });

    test('00963 is already international', () {
      expect(toInternationalPhone('00963944123456'), '963944123456');
      expect(toInternationalPhone('00 963 944 123 456'), '963944123456');
    });

    test('Arabic-Indic and Persian digits are converted', () {
      expect(toInternationalPhone('٠٩٤٤١٢٣٤٥٦'), '963944123456');
      expect(toInternationalPhone('+٩٦٣ ٩٤٤ ١٢٣ ٤٥٦'), '963944123456');
      expect(toInternationalPhone('۰۹۴۴۱۲۳۴۵۶'), '963944123456');
    });

    test('the country code without + or 00 is recognised', () {
      expect(toInternationalPhone('963944123456'), '963944123456');
    });

    test('a number typed without its trunk zero still gets the code', () {
      expect(toInternationalPhone('944123456'), '963944123456');
    });

    test('a trunk zero typed after the country code is dropped', () {
      expect(toInternationalPhone('+963 0944 123 456'), '963944123456');
      expect(toInternationalPhone('+963 (0) 944 123456'), '963944123456');
      expect(toInternationalPhone('009630944123456'), '963944123456');
    });

    test('a foreign international number is left alone', () {
      expect(toInternationalPhone('+90 532 123 45 67'), '905321234567');
      expect(toInternationalPhone('0090 532 123 45 67'), '905321234567');
    });

    test('the default country code is a setting', () {
      expect(
        toInternationalPhone('0532 123 45 67', defaultCountryCode: '90'),
        '905321234567',
      );
      // Tolerates "+90" or "0090" typed into the setting.
      expect(
        toInternationalPhone('0532 123 45 67', defaultCountryCode: '+90'),
        '905321234567',
      );
      expect(
        toInternationalPhone('0532 123 45 67', defaultCountryCode: '0090'),
        '905321234567',
      );
    });

    test('things that are not phone numbers give null', () {
      expect(toInternationalPhone(''), isNull);
      expect(toInternationalPhone('   '), isNull);
      expect(toInternationalPhone('abc'), isNull);
      expect(toInternationalPhone('123'), isNull);
      expect(toInternationalPhone('+1234567890123456'), isNull); // 16 digits
    });
  });

  group('maskAllButLast4', () {
    test('keeps only the last four characters', () {
      expect(maskAllButLast4('0011223344'), '******3344');
    });

    test('keeps spaces and dashes so the grouping stays readable', () {
      expect(maskAllButLast4('0011-2233-4455'), '****-****-4455');
      expect(maskAllButLast4('AB 12 CD 34'), '** ** CD 34');
    });

    test('four characters or fewer are not masked', () {
      expect(maskAllButLast4('1234'), '1234');
      expect(maskAllButLast4('12'), '12');
      expect(maskAllButLast4(''), '');
    });
  });
}
