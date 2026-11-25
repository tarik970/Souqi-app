import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/bidi.dart';
import 'package:souqi/core/utils/normalize.dart';

void main() {
  group('looksLikePhone', () {
    test('digits with the punctuation phones are written with', () {
      expect(looksLikePhone('0944123456'), isTrue);
      expect(looksLikePhone('0944 123 456'), isTrue);
      expect(looksLikePhone('0944-123-456'), isTrue);
      expect(looksLikePhone('+963 (944) 123456'), isTrue);
      expect(looksLikePhone('٠٩٤٤ ١٢٣ ٤٥٦'), isTrue);
      expect(looksLikePhone('09'), isTrue);
    });

    test('anything with a letter in it is not a phone', () {
      expect(looksLikePhone('MTN-123'), isFalse);
      expect(looksLikePhone('AB0011'), isFalse);
      expect(looksLikePhone('أحمد 0944'), isFalse);
      expect(looksLikePhone('Ahmad'), isFalse);
    });

    test('punctuation alone is not a phone either', () {
      expect(looksLikePhone(''), isFalse);
      expect(looksLikePhone('+'), isFalse);
      expect(looksLikePhone(' - '), isFalse);
    });
  });

  group('phoneSearchKey', () {
    test('every spelling of a number has the same key', () {
      const spellings = [
        '0944123456',
        '0944 123 456',
        '0944-123-456',
        '+963 944 123 456',
        '00963944123456',
        '963944123456',
        '٠٩٤٤١٢٣٤٥٦',
        '+963 (0) 944 123456',
      ];
      for (final spelling in spellings) {
        expect(phoneSearchKey(spelling), '944123456', reason: spelling);
      }
    });

    test('the key is found inside every stored spelling', () {
      final key = phoneSearchKey('0944 123 456');
      for (final stored in ['0944 123 456', '+963944123456', '00963 944 123456']) {
        expect(normalizePhone(stored), contains(key), reason: stored);
      }
    });

    test('a few typed digits are searched as they are', () {
      expect(phoneSearchKey('09'), '09');
      expect(phoneSearchKey('0944'), '0944');
      expect(phoneSearchKey('1234'), '1234');
      // From seven digits on, the trunk zero is dropped so that a number
      // stored with the country code is found too.
      expect(phoneSearchKey('094412'), '094412');
      expect(phoneSearchKey('0944123'), '944123');
    });

    test('a card number starting with zeros is not taken for a prefix', () {
      // The same box searches card numbers: "00" is an international prefix
      // only when the country code follows it.
      expect(phoneSearchKey('0011'), '0011');
      expect(phoneSearchKey('0011-22'), '001122');
      expect(phoneSearchKey('000123'), '000123');
      expect(phoneSearchKey('00963'), '');
    });

    test('follows the default country code setting', () {
      expect(phoneSearchKey('+90 532 123 45 67', countryCode: '90'),
          '5321234567');
      expect(phoneSearchKey('0532 123 45 67', countryCode: '90'), '5321234567');
      // Another country's code is left alone.
      expect(phoneSearchKey('+90 532 123 45 67'), '905321234567');
    });

    test('text that is not a phone has no key', () {
      expect(phoneSearchKey('MTN-123'), '');
      expect(phoneSearchKey('Ahmad'), '');
      expect(phoneSearchKey(''), '');
    });
  });

  group('ltrIsolate', () {
    test('wraps the text in invisible isolate marks', () {
      final wrapped = ltrIsolate('0944 123 456');
      expect(wrapped.length, '0944 123 456'.length + 2);
      expect(wrapped.codeUnitAt(0), 0x2066);
      expect(wrapped.codeUnitAt(wrapped.length - 1), 0x2069);
      expect(wrapped.substring(1, wrapped.length - 1), '0944 123 456');
    });

    test('leaves an empty string empty', () {
      expect(ltrIsolate(''), '');
    });
  });
}
