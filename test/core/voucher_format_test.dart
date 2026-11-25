import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/normalize.dart';
import 'package:souqi/core/utils/voucher_format.dart';

void main() {
  group('grouping in fours', () {
    test('a 16-digit code prints as four groups', () {
      expect(groupCode('1234567890123456'), '1234 5678 9012 3456');
      expect(codeGroups('1234567890123456'), ['1234', '5678', '9012', '3456']);
    });

    test('the last group takes what is left', () {
      expect(groupCode('12345678901234'), '1234 5678 9012 34');
      expect(groupCode('123'), '123');
      expect(codeGroups(''), isEmpty);
    });

    test('the dashes and spaces a code was typed with are regrouped', () {
      expect(groupCode('1234-5678-9012-3456'), '1234 5678 9012 3456');
      expect(groupCode(' 12345 67890 12345 6 '), '1234 5678 9012 3456');
    });

    test('Arabic-Indic digits print as 0-9, letters keep their case', () {
      expect(groupCode('١٢٣٤٥٦٧٨'), '1234 5678');
      expect(groupCode('AbCd-EfGh-12'), 'AbCd EfGh 12');
    });
  });

  group('masking', () {
    test('only the last four characters are shown', () {
      expect(maskCode('1234567890123456'), '•••• •••• 3456');
      expect(maskCode('1234-5678-9012-3456'), '•••• •••• 3456');
    });

    test('the mask does not give the length away', () {
      expect(maskCode('123456789012'), '•••• •••• 9012');
      expect(maskCode('12345678901234567890'), '•••• •••• 7890');
    });

    test('a short code shows less, a very short one nothing', () {
      // Four of eight characters would be half the secret.
      expect(maskCode('12345678'), '•••• •••• 78');
      expect(maskCode('12345'), '•••• •••• 45');
      expect(maskCode('1234'), '•••• ••••');
      expect(maskCode(''), '•••• ••••');
    });

    test('no digit of the hidden part survives masking', () {
      const code = '9876543210123456';
      final masked = maskCode(code);
      expect(masked.contains('9876'), isFalse);
      expect(masked.replaceAll(RegExp('[• ]'), ''), '3456');
    });

    test('the tail is taken from the printed form', () {
      expect(codeTail('1234 5678 9012 34-56'), '3456');
      expect(codeTail('١٢٣٤٥٦٧٨٩٠'), '7890');
    });
  });

  group('the two forms of a code', () {
    test('the printed form keeps case, the lookup form does not', () {
      expect(stripCodeSeparators(' ab-12 cd '), 'ab12cd');
      expect(normalizeCode(' ab-12 cd '), 'AB12CD');
    });
  });
}
