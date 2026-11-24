import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/normalize.dart';

void main() {
  group('normalizeDigits', () {
    test('converts Arabic-Indic digits', () {
      expect(normalizeDigits('٠١٢٣٤٥٦٧٨٩'), '0123456789');
    });

    test('converts Extended Arabic-Indic digits', () {
      expect(normalizeDigits('۰۱۲۳۴۵۶۷۸۹'), '0123456789');
    });

    test('leaves other characters untouched', () {
      expect(normalizeDigits('abc ع ١٢-34'), 'abc ع 12-34');
    });

    test('returns the same string when nothing changes', () {
      expect(normalizeDigits('hello 123'), 'hello 123');
    });
  });

  group('normalizePhone', () {
    test('keeps digits only', () {
      expect(normalizePhone('+963 (94) 123-456'), '96394123456');
    });

    test('converts Arabic-Indic digits first', () {
      expect(normalizePhone('٠٩٤١ ٢٣٤ ٥٦٧'), '0941234567');
    });

    test('strips letters from phones', () {
      expect(normalizePhone('ext. 12 phone 34'), '1234');
    });
  });

  group('normalizeCode (account numbers, voucher codes)', () {
    test('trims, removes spaces and dashes, uppercases', () {
      expect(normalizeCode('  ab-12 34 cd  '), 'AB1234CD');
    });

    test('never strips letters', () {
      expect(normalizeCode('SY-abc-001'), 'SYABC001');
    });

    test('keeps leading zeros', () {
      expect(normalizeCode('000-123'), '000123');
    });

    test('converts Arabic-Indic digits', () {
      expect(normalizeCode('كرت-١٢٣'), 'كرت123');
    });

    test('removes unicode dashes and NBSP', () {
      expect(normalizeCode('12–34 56'), '123456');
    });
  });

  group('normalizeName', () {
    test('trims, collapses whitespace, lowercases', () {
      expect(normalizeName('  Sugar   Fine '), 'sugar fine');
    });

    test('converts Arabic-Indic digits', () {
      expect(normalizeName('انترنت ١٠٠ غيغا'), 'انترنت 100 غيغا');
    });

    test('Latin letters are case-insensitive', () {
      expect(normalizeName('PEPSI Max'), normalizeName('pepsi max'));
    });

    test('unifies the alef variants أ / إ / آ', () {
      expect(normalizeName('أرز'), 'ارز');
      expect(normalizeName('إبرة'), normalizeName('ابره'));
      expect(normalizeName('آيس كريم'), normalizeName('ايس كريم'));
    });

    test('ة reads as ه and ى as ي', () {
      expect(normalizeName('قهوة'), 'قهوه');
      expect(normalizeName('قهوة'), normalizeName('قهوه'));
      expect(normalizeName('حلوى'), normalizeName('حلوي'));
    });

    test('removes tatweel and diacritics', () {
      expect(normalizeName('ســـكر'), 'سكر');
      expect(normalizeName('سُكَّر'), 'سكر');
    });

    test('removes invisible direction and joiner marks', () {
      final rlm = String.fromCharCode(0x200F);
      final zwnj = String.fromCharCode(0x200C);
      expect(normalizeName('$rlmسكر$zwnj'), 'سكر');
    });

    test('drops a leading "ال" from every word', () {
      expect(normalizeName('السكر'), 'سكر');
      expect(normalizeName('السكر الناعم'), 'سكر ناعم');
      expect(normalizeName('سكر الناعم'), 'سكر ناعم');
      // After the alef is unified: "الأرز" is "أرز".
      expect(normalizeName('الأرز'), normalizeName('أرز'));
    });

    test('keeps short words that merely start with "ال"', () {
      expect(normalizeName('ال'), 'ال');
      expect(normalizeName('ألف ليلة'), 'الف ليله');
    });

    test('every variant of one name normalizes to the same text', () {
      const variants = [
        'سكر ناعم',
        'السكر الناعم',
        '  سكر   ناعم ',
        'سُكَّر ناعِم',
        'ســكر نــاعم',
      ];
      expect(variants.map(normalizeName).toSet(), {'سكر ناعم'});
    });

    test('text made only of marks normalizes to nothing', () {
      expect(normalizeName(' ـــ '), '');
    });
  });
}
