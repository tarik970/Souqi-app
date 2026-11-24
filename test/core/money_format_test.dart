import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/money_format.dart';

void main() {
  group('formatMinor', () {
    test('English: grouping, decimals, symbol', () {
      expect(
        formatMinor(123456, decimals: 2, locale: 'en', symbol: r'$'),
        r'1,234.56 $',
      );
    });

    test('English: zero decimals', () {
      expect(formatMinor(52000, decimals: 0, locale: 'en'), '52,000');
    });

    test('pads the fraction with zeros', () {
      expect(formatMinor(1205, decimals: 2, locale: 'en'), '12.05');
    });

    test('negative amounts carry the locale minus sign', () {
      expect(formatMinor(-5, decimals: 2, locale: 'en'), '-0.05');
    });

    test('Arabic-Indic digit locales localize the fraction digits too', () {
      // intl's plain 'ar' data uses Latin digits; ar_EG uses Arabic-Indic,
      // which exercises the fraction-digit localization path.
      final text = formatMinor(123456, decimals: 2, locale: 'ar_EG');
      expect(text.contains(RegExp('[0-9]')), isFalse,
          reason: 'no ASCII digits in $text');
      expect(text, contains('٫'));
      expect(text, endsWith('٥٦'), reason: 'fraction digits localized: $text');
    });

    test('plain ar locale formats without error', () {
      expect(formatMinor(123456, decimals: 2, locale: 'ar'), isNotEmpty);
    });
  });

  group('minorToPlainText', () {
    test('two decimals', () => expect(minorToPlainText(250, decimals: 2), '2.50'));
    test('zero decimals', () => expect(minorToPlainText(1500, decimals: 0), '1500'));
    test('negative', () => expect(minorToPlainText(-5, decimals: 2), '-0.05'));
  });

  group('parseAmountMinor', () {
    test('plain integer', () => expect(parseAmountMinor('1500', decimals: 0), 1500));
    test('decimal', () => expect(parseAmountMinor('2.50', decimals: 2), 250));
    test('short fraction is padded', () => expect(parseAmountMinor('2.5', decimals: 2), 250));
    test('leading dot', () => expect(parseAmountMinor('.5', decimals: 2), 50));
    test('Arabic digits and separator', () => expect(parseAmountMinor('٢٫٥', decimals: 2), 250));
    test('comma separator', () => expect(parseAmountMinor('2,5', decimals: 2), 250));
    test('too many fraction digits', () => expect(parseAmountMinor('1.234', decimals: 2), isNull));
    test('fraction rejected for 0-decimal currency', () => expect(parseAmountMinor('2.5', decimals: 0), isNull));
    test('garbage', () {
      expect(parseAmountMinor('abc', decimals: 2), isNull);
      expect(parseAmountMinor('', decimals: 2), isNull);
      expect(parseAmountMinor('-5', decimals: 2), isNull);
      expect(parseAmountMinor('1.2.3', decimals: 2), isNull);
    });
  });
}
