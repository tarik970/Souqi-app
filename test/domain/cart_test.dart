import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/product.dart';

Currency _currency(
  String code, {
  int decimals = 0,
  RateFraction rate = RateFraction.one,
  bool rateSet = true,
}) {
  return Currency(
    code: code,
    nameAr: code,
    nameEn: code,
    decimalPlaces: decimals,
    rate: rate,
    rateUpdatedAt: rateSet ? DateTime.utc(2026, 1, 1) : null,
  );
}

final syp = _currency('SYP');
final usd = _currency('USD', decimals: 2, rate: const RateFraction(13000, 1));
final usdNoRate = _currency('USD',
    decimals: 2, rate: const RateFraction(1, 1), rateSet: false);
final tryLira =
    _currency('TRY', decimals: 2, rate: const RateFraction(400, 1));

CurrencyContext ctxOf(
  List<Currency> currencies, {
  String base = 'SYP',
  List<String> extras = const [],
}) =>
    CurrencyContext.of(currencies, baseCode: base, extraCodes: extras);

CartLine line({
  int? productId = 1,
  String name = 'Sugar',
  int priceMinor = 1500,
  String currency = 'SYP',
  int qty = 1000,
  ProductKind kind = ProductKind.goods,
  int? unitId = 1,
  String? unitName = 'kg',
}) =>
    CartLine(
      productId: productId,
      name: name,
      kind: kind,
      unitId: unitId,
      unitName: unitName,
      unitPriceMinor: priceMinor,
      priceCurrencyCode: currency,
      qtyThousandths: qty,
    );

void main() {
  final singleCurrency = ctxOf([syp]);
  final twoCurrencies = ctxOf([syp, usd]);

  group('cart line math', () {
    test('line total is round(price * qty / 1000), half-up', () {
      final cart = const Cart().add(line(priceMinor: 1500, qty: 333));
      final totals = computeCartTotals(cart, singleCurrency);
      // 1500 * 333 / 1000 = 499.5 → 500
      expect(totals.lines.single.lineTotalMinor, 500);
      expect(totals.subtotalMinor, 500);
    });

    test('decimal quantities are exact', () {
      final cart = const Cart().add(line(priceMinor: 2000, qty: 500));
      expect(
        computeCartTotals(cart, singleCurrency).subtotalMinor,
        1000,
      );
    });

    test('subtotal sums every line total', () {
      final cart = const Cart()
          .add(line(productId: 1, priceMinor: 1500, qty: 2000))
          .add(line(productId: 2, priceMinor: 700, qty: 1500));
      // 3000 + round(700 * 1.5) = 3000 + 1050
      expect(computeCartTotals(cart, singleCurrency).subtotalMinor, 4050);
    });

    test('zero or negative quantities are rejected', () {
      expect(() => const Cart().add(line(qty: 0)), throwsArgumentError);
      expect(() => const Cart().add(line(qty: -1000)), throwsArgumentError);
    });
  });

  group('merging', () {
    test('same product at the same unit price merges quantities', () {
      final cart = const Cart()
          .add(line(productId: 7, qty: 500))
          .add(line(productId: 7, qty: 1500));
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.qtyThousandths, 2000);
    });

    test('same product at a different price stays a separate line', () {
      final cart = const Cart()
          .add(line(productId: 7, priceMinor: 1500))
          .add(line(productId: 7, priceMinor: 1200));
      expect(cart.lines, hasLength(2));
      expect(
        cart.lines.map((l) => l.unitPriceMinor),
        [1500, 1200],
      );
    });

    test('same product priced in a different currency stays separate', () {
      final cart = const Cart()
          .add(line(productId: 7, priceMinor: 100, currency: 'SYP'))
          .add(line(productId: 7, priceMinor: 100, currency: 'USD'));
      expect(cart.lines, hasLength(2));
    });

    test('same product sold in a different unit stays a separate line', () {
      // The quantity sheet can change the unit per line: 2 bags and 3 kg of
      // the same sugar are two rows, not five of something.
      final cart = const Cart()
          .add(line(productId: 7, unitId: 1, unitName: 'kg'))
          .add(line(productId: 7, unitId: 2, unitName: 'bag'));
      expect(cart.lines, hasLength(2));
      expect(cart.lines.map((l) => l.unitName), ['kg', 'bag']);
    });

    test('unsaved items never merge', () {
      final cart = const Cart()
          .add(line(productId: null, name: 'Bread'))
          .add(line(productId: null, name: 'Bread'));
      expect(cart.lines, hasLength(2));
    });

    test('editing a line into a twin folds the two together', () {
      var cart = const Cart()
          .add(line(productId: 7, priceMinor: 1500, qty: 1000))
          .add(line(productId: 7, priceMinor: 1200, qty: 2000));
      final second = cart.lines[1];
      cart = cart.replace(second.copyWith(unitPriceMinor: 1500));
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.qtyThousandths, 3000);
      expect(cart.lines.single.unitPriceMinor, 1500);
    });
  });

  group('cart editing', () {
    test('setQuantity replaces the quantity', () {
      var cart = const Cart().add(line(qty: 1000));
      cart = cart.setQuantity(cart.lines.single.id, 2500);
      expect(cart.lines.single.qtyThousandths, 2500);
    });

    test('setQuantity to zero removes the line', () {
      var cart = const Cart().add(line());
      cart = cart.setQuantity(cart.lines.single.id, 0);
      expect(cart.isEmpty, isTrue);
    });

    test('remove drops only the named line', () {
      final cart = const Cart()
          .add(line(productId: 1))
          .add(line(productId: 2))
          .add(line(productId: 3));
      final after = cart.remove(cart.lines[1].id);
      expect(after.lines.map((l) => l.productId), [1, 3]);
    });

    test('line ids are never reused after a removal', () {
      var cart = const Cart().add(line(productId: 1));
      final firstId = cart.lines.single.id;
      cart = cart.remove(firstId).add(line(productId: 1));
      expect(cart.lines.single.id, isNot(firstId));
    });

    test('clear empties lines and discount but keeps the currency', () {
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(line())
          .withDiscount(const Discount.percent(1000))
          .clear();
      expect(cart.isEmpty, isTrue);
      expect(cart.discount, isNull);
      expect(cart.invoiceCurrencyCode, 'USD');
    });

    test('replace ignores an unknown line id', () {
      final cart = const Cart().add(line());
      final unchanged = cart.replace(line().copyWith(id: 999));
      expect(unchanged.lines.single.qtyThousandths,
          cart.lines.single.qtyThousandths);
    });
  });

  group('discount math', () {
    test('amount discount subtracts from the subtotal', () {
      final cart = const Cart()
          .add(line(priceMinor: 1000, qty: 10000))
          .withDiscount(const Discount.amount(1500));
      final totals = computeCartTotals(cart, singleCurrency);
      expect(totals.subtotalMinor, 10000);
      expect(totals.discountMinor, 1500);
      expect(totals.totalMinor, 8500);
    });

    test('percent discount is rounded half-up once', () {
      final cart = const Cart()
          .add(line(priceMinor: 1005, qty: 1000))
          .withDiscount(const Discount.percent(1000)); // 10.00%
      final totals = computeCartTotals(cart, singleCurrency);
      // 1005 * 1000 / 10000 = 100.5 → 101
      expect(totals.discountMinor, 101);
      expect(totals.totalMinor, 904);
    });

    test('a discount larger than the subtotal is capped, total never < 0', () {
      final cart = const Cart()
          .add(line(priceMinor: 1000, qty: 1000))
          .withDiscount(const Discount.amount(50000));
      final totals = computeCartTotals(cart, singleCurrency);
      expect(totals.discountMinor, 1000);
      expect(totals.totalMinor, 0);
    });

    test('100% discount zeroes the total', () {
      final cart = const Cart()
          .add(line(priceMinor: 7777, qty: 1000))
          .withDiscount(const Discount.percent(10000));
      expect(computeCartTotals(cart, singleCurrency).totalMinor, 0);
    });

    test('no discount means zero, not null', () {
      final totals =
          computeCartTotals(const Cart().add(line()), singleCurrency);
      expect(totals.discountMinor, 0);
      expect(totals.totalMinor, totals.subtotalMinor);
    });

    test('percent basis points outside 0..100% are rejected', () {
      expect(() => Discount.percent(10001), throwsA(isA<AssertionError>()));
      expect(() => Discount.amount(-1), throwsA(isA<AssertionError>()));
    });
  });

  group('mixed-currency carts', () {
    test('a USD-priced line is converted into an SYP invoice', () {
      final cart =
          const Cart().add(line(priceMinor: 150, currency: 'USD', qty: 2000));
      final totals = computeCartTotals(cart, twoCurrencies);
      // 1.50 USD * 13000 = 19500 SYP per unit, × 2
      expect(totals.lines.single.unitPriceMinor, 19500);
      expect(totals.lines.single.lineTotalMinor, 39000);
      expect(totals.currency.code, 'SYP');
      expect(totals.totalBaseMinor, 39000);
    });

    test('an SYP-priced line is converted into a USD invoice', () {
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(line(priceMinor: 1000, currency: 'SYP', qty: 3000));
      final totals = computeCartTotals(cart, twoCurrencies);
      // The displayed unit price rounds on its own: 0.0769… → 8 cents.
      expect(totals.lines.single.unitPriceMinor, 8);
      // The line total converts 3000 SYP in one step: 0.2307… → 23 cents,
      // NOT the displayed 8 × 3 = 24.
      expect(totals.lines.single.lineTotalMinor, 23);
      expect(totals.totalMinor, 23);
      // and back to the base currency for statistics
      expect(totals.totalBaseMinor, 2990);
    });

    test('the line total rounds once, not once per unit', () {
      // 5000 SYP × 10 on a USD invoice: 3.85 USD, not 10 × 0.38 = 3.80.
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(line(priceMinor: 5000, currency: 'SYP', qty: 10000));
      final totals = computeCartTotals(cart, twoCurrencies);
      expect(totals.lines.single.unitPriceMinor, 38);
      expect(totals.lines.single.lineTotalMinor, 385);
      expect(totals.totalMinor, 385);
    });

    test('a fractional quantity rounds once too', () {
      // 1365 SYP = 10.5 cents exactly; half is 5.25 → 5, not 11 × 0.5 → 6.
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(line(priceMinor: 1365, currency: 'SYP', qty: 500));
      final totals = computeCartTotals(cart, twoCurrencies);
      expect(totals.lines.single.unitPriceMinor, 11);
      expect(totals.lines.single.lineTotalMinor, 5);
    });

    test('a same-currency line total is unaffected by the rate path', () {
      // The one-step conversion must reduce exactly to round(price*qty/1000).
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(line(priceMinor: 1365, currency: 'USD', qty: 500));
      final totals = computeCartTotals(cart, twoCurrencies);
      expect(totals.lines.single.unitPriceMinor, 1365);
      expect(totals.lines.single.lineTotalMinor, 683); // 682.5 → 683
    });

    test('lines keep their own currency and rate snapshot', () {
      final cart = const Cart()
          .add(line(productId: 1, priceMinor: 1000, currency: 'SYP'))
          .add(line(productId: 2, priceMinor: 100, currency: 'USD'));
      final totals = computeCartTotals(cart, twoCurrencies);
      expect(totals.lines[0].origRate, RateFraction.one);
      expect(totals.lines[0].origDecimals, 0);
      expect(totals.lines[1].origRate, const RateFraction(13000, 1));
      expect(totals.lines[1].origDecimals, 2);
      // 1000 SYP + 1.00 USD (13000 SYP)
      expect(totals.subtotalMinor, 14000);
    });

    test('a discount applies in the invoice currency, after conversion', () {
      final cart = const Cart(invoiceCurrencyCode: 'USD')
          .add(line(priceMinor: 130000, currency: 'SYP', qty: 1000))
          .withDiscount(const Discount.amount(100)); // 1.00 USD off
      final totals = computeCartTotals(cart, twoCurrencies);
      expect(totals.subtotalMinor, 1000); // 10.00 USD
      expect(totals.totalMinor, 900);
      expect(totals.totalBaseMinor, 117000);
    });

    test('an extra currency total is shown next to the main total', () {
      final cart = const Cart().add(line(priceMinor: 26000, qty: 1000));
      final totals = computeCartTotals(
        cart,
        ctxOf([syp, usd, tryLira], extras: ['USD', 'TRY']),
      );
      expect(totals.extraTotals.map((e) => e.currency.code), ['USD', 'TRY']);
      expect(totals.extraTotals[0].totalMinor, 200); // 2.00 USD
      expect(totals.extraTotals[1].totalMinor, 6500); // 65.00 TRY
    });

    test('the invoice currency is not repeated as an extra total', () {
      final cart = const Cart().add(line(priceMinor: 13000, qty: 1000));
      final totals =
          computeCartTotals(cart, ctxOf([syp, usd], extras: ['SYP', 'USD']));
      expect(totals.extraTotals.map((e) => e.currency.code), ['USD']);
    });

    test('at most two extra totals are produced', () {
      final cart = const Cart().add(line(priceMinor: 13000, qty: 1000));
      final totals = computeCartTotals(
        cart,
        ctxOf([syp, usd, tryLira], extras: ['USD', 'TRY', 'SYP']),
      );
      expect(totals.extraTotals, hasLength(2));
    });

    test('the default invoice currency follows the base currency', () {
      final cart = const Cart().add(line());
      expect(cart.effectiveCurrencyCode(twoCurrencies), 'SYP');
      expect(
        computeCartTotals(cart, ctxOf([syp, usd], base: 'USD')).currency.code,
        'USD',
      );
    });

    test('an unknown currency code is an error, not a silent zero', () {
      final cart = const Cart().add(line(currency: 'EUR'));
      expect(() => computeCartTotals(cart, twoCurrencies), throwsArgumentError);
    });
  });

  group('rates that were never entered', () {
    test('a line in a currency with no rate is reported', () {
      final cart = const Cart().add(line(priceMinor: 100, currency: 'USD'));
      final totals = computeCartTotals(cart, ctxOf([syp, usdNoRate]));
      expect(totals.currenciesNeedingRate.map((c) => c.code), ['USD']);
    });

    test('an invoice currency with no rate is reported', () {
      final cart = const Cart(invoiceCurrencyCode: 'USD').add(line());
      final totals = computeCartTotals(cart, ctxOf([syp, usdNoRate]));
      expect(totals.currenciesNeedingRate.map((c) => c.code), ['USD']);
    });

    test('the base currency never needs a rate update', () {
      final cart = const Cart().add(line());
      final totals = computeCartTotals(cart, singleCurrency);
      expect(totals.currenciesNeedingRate, isEmpty);
    });

    test('an extra currency with no rate is skipped, not shown as zero', () {
      final cart = const Cart().add(line(priceMinor: 1000, qty: 1000));
      final totals =
          computeCartTotals(cart, ctxOf([syp, usdNoRate], extras: ['USD']));
      expect(totals.extraTotals, isEmpty);
    });
  });

  test('an empty cart computes to zero', () {
    final totals = computeCartTotals(const Cart(), singleCurrency);
    expect(totals.isEmpty, isTrue);
    expect(totals.subtotalMinor, 0);
    expect(totals.totalMinor, 0);
    expect(totals.totalBaseMinor, 0);
  });
}
