import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/core/money/quantity.dart';
import 'package:souqi/core/money/rounding.dart';

void main() {
  group('divRoundHalfUp', () {
    int div(int n, int d) => divRoundHalfUp(BigInt.from(n), BigInt.from(d));

    test('exact division', () => expect(div(100, 4), 25));
    test('rounds down below half', () => expect(div(104, 10), 10));
    test('rounds half up', () => expect(div(105, 10), 11));
    test('rounds half up at 2.5', () => expect(div(25, 10), 3));
    test('rounds up above half', () => expect(div(106, 10), 11));
    test('negative half rounds away from zero', () => expect(div(-105, 10), -11));
    test('negative below half', () => expect(div(-104, 10), -10));
    test('rejects non-positive denominator', () {
      expect(() => div(1, 0), throwsArgumentError);
      expect(() => div(1, -5), throwsArgumentError);
    });
    test('handles huge intermediates via BigInt', () {
      final n = BigInt.parse('92233720368547758070'); // > 2^63
      expect(divRoundHalfUp(n, BigInt.from(10)), 9223372036854775807);
    });
  });

  group('lineTotalMinor', () {
    test('0.5 kg at 1000/kg = 500', () {
      expect(lineTotalMinor(unitPriceMinor: 1000, qtyThousandths: 500), 500);
    });
    test('quantity 1 piece', () {
      expect(lineTotalMinor(unitPriceMinor: 750, qtyThousandths: 1000), 750);
    });
    test('rounds half up: 0.335 * 100 = 33.5 -> 34', () {
      expect(lineTotalMinor(unitPriceMinor: 100, qtyThousandths: 335), 34);
    });
    test('rounds down: 0.333 * 100 = 33.3 -> 33', () {
      expect(lineTotalMinor(unitPriceMinor: 100, qtyThousandths: 333), 33);
    });
    test('rejects negative quantity', () {
      expect(() => lineTotalMinor(unitPriceMinor: 100, qtyThousandths: -1),
          throwsArgumentError);
    });
  });

  group('percentDiscountMinor', () {
    test('10.00% of 52000 = 5200', () {
      expect(percentDiscountMinor(subtotalMinor: 52000, basisPoints: 1000), 5200);
    });
    test('rounds half up: 2.5% of 1230 = 30.75 -> 31', () {
      expect(percentDiscountMinor(subtotalMinor: 1230, basisPoints: 250), 31);
    });
    test('rejects > 100%', () {
      expect(() => percentDiscountMinor(subtotalMinor: 100, basisPoints: 10001),
          throwsArgumentError);
    });
  });

  group('convertMinor', () {
    // Base: SYP, 0 decimals. USD: 2 decimals, 1 USD = 13000 SYP.
    const usdRate = RateFraction(13000, 1);
    const sypDecimals = 0;
    const usdDecimals = 2;

    test('USD -> SYP: \$4.00 = 52000 SYP', () {
      expect(
        convertMinor(
          amountMinor: 400,
          fromDecimals: usdDecimals,
          fromRate: usdRate,
          toDecimals: sypDecimals,
          toRate: RateFraction.one,
        ),
        52000,
      );
    });

    test('SYP -> USD: 52000 SYP = \$4.00', () {
      expect(
        convertMinor(
          amountMinor: 52000,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        400,
      );
    });

    test('SYP -> USD rounding: 100 SYP = 0.769 cents -> 1 cent', () {
      expect(
        convertMinor(
          amountMinor: 100,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        1,
      );
    });

    test('cross conversion USD -> TRY through base', () {
      // 1 TRY = 325 SYP; $2.00 = 26000 SYP = 80.00 TRY
      const tryRate = RateFraction(325, 1);
      expect(
        convertMinor(
          amountMinor: 200,
          fromDecimals: usdDecimals,
          fromRate: usdRate,
          toDecimals: 2,
          toRate: tryRate,
        ),
        8000,
      );
    });

    test('toBaseMinor convenience', () {
      expect(
        toBaseMinor(
          amountMinor: 150,
          fromDecimals: usdDecimals,
          fromRate: usdRate,
          baseDecimals: sypDecimals,
        ),
        19500,
      );
    });

    test('fractional rate entered as decimal stays exact', () {
      // "1 SYP = 0.0000769 USD" entered on a USD-base setup:
      final rate = parseRateFraction('0.0000769');
      // 13000 SYP -> USD cents: 13000 * 769/10^7 * 100 = 99.97 -> 100
      expect(
        convertMinor(
          amountMinor: 13000,
          fromDecimals: 0,
          fromRate: rate,
          toDecimals: 2,
          toRate: RateFraction.one,
        ),
        100,
      );
    });

    test('convertLineTotalMinor rounds once, not per unit', () {
      // 5000 SYP × 10 on a USD invoice at 13000 SYP/USD.
      // Correct: 50000 SYP / 13000 = 3.846… -> 3.85 USD.
      // Rounding the unit price first would give 10 × 0.38 = 3.80 USD.
      expect(
        convertLineTotalMinor(
          unitPriceMinor: 5000,
          qtyThousandths: 10000,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        385,
      );
      expect(
        convertMinor(
          amountMinor: 5000,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        38, // the display-only unit price
      );
    });

    test('convertLineTotalMinor rounds once for fractional quantities', () {
      // 1365 SYP is exactly 10.5 cents; half of it is 5.25 -> 5 cents.
      // Rounding the unit price first gives 11 cents × 0.5 = 5.5 -> 6.
      expect(
        convertLineTotalMinor(
          unitPriceMinor: 1365,
          qtyThousandths: 500,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        5,
      );
      expect(
        convertMinor(
          amountMinor: 1365,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        11,
      );
    });

    test('convertLineTotalMinor matches lineTotalMinor in one currency', () {
      for (final (price, qty) in [
        (1500, 333),
        (100, 335),
        (750, 1000),
        (2000, 500),
        (7, 1),
      ]) {
        expect(
          convertLineTotalMinor(
            unitPriceMinor: price,
            qtyThousandths: qty,
            fromDecimals: usdDecimals,
            fromRate: usdRate,
            toDecimals: usdDecimals,
            toRate: usdRate,
          ),
          lineTotalMinor(unitPriceMinor: price, qtyThousandths: qty),
          reason: 'price $price × qty $qty',
        );
      }
    });

    test('convertLineTotalMinor rejects a negative quantity', () {
      expect(
        () => convertLineTotalMinor(
          unitPriceMinor: 100,
          qtyThousandths: -1,
          fromDecimals: sypDecimals,
          fromRate: RateFraction.one,
          toDecimals: usdDecimals,
          toRate: usdRate,
        ),
        throwsArgumentError,
      );
    });

    test('no double anywhere: huge amounts stay exact', () {
      // 9 billion SYP -> USD cents at 13000: 9e9/13000*100 = 69230769.23 -> 69230769
      expect(
        convertMinor(
          amountMinor: 9000000000,
          fromDecimals: 0,
          fromRate: RateFraction.one,
          toDecimals: 2,
          toRate: usdRate,
        ),
        69230769,
      );
    });
  });

  group('parseRateFraction', () {
    test('integer rate', () {
      expect(parseRateFraction('13000'), const RateFraction(13000, 1));
    });
    test('decimal rate reduced', () {
      expect(parseRateFraction('0.50'), const RateFraction(1, 2));
    });
    test('small decimal rate', () {
      expect(parseRateFraction('0.0000769'), const RateFraction(769, 10000000));
    });
    test('Arabic-Indic digits and Arabic decimal separator', () {
      expect(parseRateFraction('١٣٠٠٠'), const RateFraction(13000, 1));
      expect(parseRateFraction('٠٫٥'), const RateFraction(1, 2));
    });
    test('comma as decimal separator', () {
      expect(parseRateFraction('1,5'), const RateFraction(3, 2));
    });
    test('rejects zero', () {
      expect(() => parseRateFraction('0'), throwsFormatException);
      expect(() => parseRateFraction('0.000'), throwsFormatException);
    });
    test('rejects garbage', () {
      expect(() => parseRateFraction('abc'), throwsFormatException);
      expect(() => parseRateFraction('1.2.3'), throwsFormatException);
      expect(() => parseRateFraction('-5'), throwsFormatException);
      expect(() => parseRateFraction(''), throwsFormatException);
    });
    test('rejects too many digits', () {
      expect(() => parseRateFraction('1234567890123456'), throwsFormatException);
      expect(() => parseRateFraction('0.0000000000001'), throwsFormatException);
    });
  });
}
