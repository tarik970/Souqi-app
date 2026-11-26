import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/domain/models/price_change.dart';

void main() {
  group('the percentage as typed', () {
    test('whole, decimal, signed, Arabic digits and separators', () {
      expect(parsePercentBasisPoints('10'), 1000);
      expect(parsePercentBasisPoints('+10'), 1000);
      expect(parsePercentBasisPoints('-7.5'), -750);
      expect(parsePercentBasisPoints('7,25'), 725);
      expect(parsePercentBasisPoints('١٢٫٥'), 1250);
      expect(parsePercentBasisPoints(' 3 % '), 300);
      expect(parsePercentBasisPoints('−5'), -500, reason: 'the Arabic minus');
    });

    test('nothing, zero, too many decimals, out of range: refused', () {
      for (final bad in ['', '0', '0.0', 'abc', '1.234', '-100', '-120', '1001']) {
        expect(parsePercentBasisPoints(bad), isNull, reason: bad);
      }
      expect(parsePercentBasisPoints('-99.99'), -9999);
      expect(parsePercentBasisPoints('1000'), 100000);
    });

    test('shown back as "+10 %", "−7.5 %"', () {
      expect(formatBasisPoints(1000), '+10 %');
      expect(formatBasisPoints(-750), '−7.5 %');
      expect(formatBasisPoints(1225), '+12.25 %');
    });
  });

  group('the new price', () {
    test('no rounding: one half-up rounding to the minor unit', () {
      expect(bulkNewPrice(1000, 1000, PriceRounding.none), 1100);
      // 1234 × 1.075 = 1326.55 → 1327
      expect(bulkNewPrice(1234, 750, PriceRounding.none), 1327);
      // 999 × 0.9 = 899.1 → 899
      expect(bulkNewPrice(999, -1000, PriceRounding.none), 899);
      // exactly half: 15 × 1.1 = 16.5 → 17 (half up)
      expect(bulkNewPrice(15, 1000, PriceRounding.none), 17);
      // cents: $12.99 + 10 % = 14.289 → 14.29
      expect(bulkNewPrice(1299, 1000, PriceRounding.none), 1429);
    });

    test('to the nearest step, rounded ONCE from the exact value', () {
      // 2600 × 1.1 = 2860 → nearest 50: 2850; nearest 100: 2900;
      // nearest 500: 3000; nearest 1000: 3000.
      expect(bulkNewPrice(2600, 1000, PriceRounding.nearest50), 2850);
      expect(bulkNewPrice(2600, 1000, PriceRounding.nearest100), 2900);
      expect(bulkNewPrice(2600, 1000, PriceRounding.nearest500), 3000);
      expect(bulkNewPrice(2600, 1000, PriceRounding.nearest1000), 3000);
      // 2250 × 1.1 = 2475 → exactly half way to 500: up to 2500.
      expect(bulkNewPrice(2250, 1000, PriceRounding.nearest50), 2500);
      expect(bulkNewPrice(2250, 1000, PriceRounding.nearest100), 2500);
      // 1100 × 1.1 = 1210: nearest 500 → 1000, nearest 1000 → 1000.
      expect(bulkNewPrice(1100, 1000, PriceRounding.nearest500), 1000);
      // Lowering: 13000 − 5 % = 12350 → nearest 500 = 12500.
      expect(bulkNewPrice(13000, -500, PriceRounding.nearest500), 12500);
    });

    test('a single rounding step, not two: 1.4 % of 2225 is not rounded '
        'to a whole pound first', () {
      // 2225 × 1.014 = 2256.15 → nearest 50 = 2250 (one step). Rounding to
      // a pound first (2256) gives the same here; the case that differs:
      // 2235 × 1.01 = 2257.35; both ways → 2250.
      expect(bulkNewPrice(2225, 140, PriceRounding.nearest50), 2250);
      // 2224 × 1.0112 = 2248.9088 → nearest 50: 2250.
      expect(bulkNewPrice(2224, 112, PriceRounding.nearest50), 2250);
    });

    test('a price never rounds down to zero; zero stays zero', () {
      expect(bulkNewPrice(100, 1000, PriceRounding.nearest500), 500);
      expect(bulkNewPrice(20, -5000, PriceRounding.nearest50), 50);
      expect(bulkNewPrice(1, -9999, PriceRounding.none), 1);
      expect(bulkNewPrice(0, 1000, PriceRounding.nearest100), 0);
    });

    test('large prices do not overflow', () {
      // 900 billion pounds + 1000 %.
      expect(bulkNewPrice(900000000000, 100000, PriceRounding.nearest1000),
          9900000000000);
    });
  });

  test('the plan lists every product and marks the ones that change', () {
    final plan = planBulkPriceChange(
      products: [
        (id: 1, name: 'Sugar', currencyCode: 'SYP', priceMinor: 2600),
        (id: 2, name: 'Bread', currencyCode: 'SYP', priceMinor: 1000),
        (id: 3, name: 'Free bag', currencyCode: 'SYP', priceMinor: 0),
      ],
      basisPoints: 100,
      rounding: PriceRounding.nearest500,
      scope: PriceChangeScope.all,
    );
    expect(plan.lines, hasLength(3));
    // 2626 → 2500, 1010 → 1000 (no change), 0 → 0.
    expect(plan.lines.map((l) => l.newPriceMinor), [2500, 1000, 0]);
    expect(plan.changing.map((l) => l.productId), [1]);
  });
}
