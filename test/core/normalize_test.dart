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
  });
}
