import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/money/exchange.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/currency.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/product.dart';

final _syp = Currency(
  code: 'SYP',
  nameAr: 'ليرة سورية',
  nameEn: 'Syrian Pound',
  decimalPlaces: 0,
  rate: RateFraction.one,
  rateUpdatedAt: DateTime.utc(2026),
);

final _ctx = CurrencyContext.of([_syp], baseCode: 'SYP');

const _package = CartLine(
  productId: 7,
  name: 'ADSL 4 Mbps',
  kind: ProductKind.service,
  unitPriceMinor: 35000,
  priceCurrencyCode: 'SYP',
  qtyThousandths: 1000,
  requiresAccount: true,
);

const _sugar = CartLine(
  productId: 3,
  name: 'Sugar',
  unitPriceMinor: 9000,
  priceCurrencyCode: 'SYP',
  qtyThousandths: 2000,
);

Invoice _invoice(
  Cart cart, {
  int? customerId,
  int? accountId,
  String? accountNumber,
}) =>
    Invoice.fromCart(
      cart: cart,
      ctx: _ctx,
      createdAt: DateTime(2026, 11, 25, 10),
      customerId: customerId,
      customerName: customerId == null ? null : 'Ahmad',
      accountId: accountId,
      accountNumber: accountNumber,
    );

void main() {
  group('a product that requires a customer account', () {
    test('the cart reports the lines that need one', () {
      final cart = const Cart().add(_sugar).add(_package);
      expect(cart.linesRequiringAccount.map((l) => l.name), ['ADSL 4 Mbps']);
      expect(const Cart().add(_sugar).linesRequiringAccount, isEmpty);
    });

    test('the flag survives editing the line', () {
      final edited = _package.copyWith(unitPriceMinor: 40000, qtyThousandths: 2000);
      expect(edited.requiresAccount, isTrue);
      final cart = const Cart().add(_package).setQuantity(1, 3000);
      expect(cart.lines.single.requiresAccount, isTrue);
    });

    test('cannot become an invoice without an account', () {
      final cart = const Cart().add(_package);
      expect(
        () => _invoice(cart),
        throwsA(
          isA<AccountRequiredException>()
              .having((e) => e.productName, 'productName', 'ADSL 4 Mbps'),
        ),
      );
      // A customer alone is not enough: it is the ACCOUNT that is required.
      expect(
        () => _invoice(cart, customerId: 1),
        throwsA(isA<AccountRequiredException>()),
      );
    });

    test('becomes an invoice once an account is attached', () {
      final invoice = _invoice(
        const Cart().add(_package),
        customerId: 1,
        accountId: 5,
        accountNumber: '0011-2233',
      );
      expect(invoice.accountId, 5);
      expect(invoice.accountNumber, '0011-2233');
      expect(invoice.customerName, 'Ahmad');
    });

    test('goods sell with no customer at all', () {
      expect(_invoice(const Cart().add(_sugar)).customerId, isNull);
    });
  });

  group('renewsAccount', () {
    test('an account plus a SERVICE/CARD item is a renewal', () {
      final invoice = _invoice(
        const Cart().add(_package),
        customerId: 1,
        accountId: 5,
        accountNumber: '0011',
      );
      expect(invoice.renewsAccount, isTrue);
    });

    test('an account on a goods-only sale is just a snapshot', () {
      final invoice = _invoice(
        const Cart().add(_sugar),
        customerId: 1,
        accountId: 5,
        accountNumber: '0011',
      );
      expect(invoice.renewsAccount, isFalse);
    });

    test('a service sold with no account renews nothing', () {
      const optional = CartLine(
        productId: 7,
        name: 'ADSL 4 Mbps',
        kind: ProductKind.service,
        unitPriceMinor: 35000,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
      );
      expect(_invoice(const Cart().add(optional)).renewsAccount, isFalse);
    });
  });

  group('defaultPackageOfferFor', () {
    const customer = SaleCustomer(
      customerId: 1,
      name: 'Ahmad',
      accountId: 5,
      accountNumber: '0011',
      defaultProductId: 7,
    );

    Invoice renewal(List<CartLine> lines) {
      var cart = const Cart();
      for (final line in lines) {
        cart = cart.add(line);
      }
      return _invoice(cart, customerId: 1, accountId: 5, accountNumber: '0011');
    }

    CartLine package(int id, String name) => CartLine(
          productId: id,
          name: name,
          kind: ProductKind.service,
          unitPriceMinor: 1000,
          priceCurrencyCode: 'SYP',
          qtyThousandths: 1000,
        );

    test('nothing to offer when the default package was sold', () {
      expect(defaultPackageOfferFor(renewal([_package]), customer), isNull);
    });

    test('offers the package that was sold instead', () {
      final offer = defaultPackageOfferFor(
        renewal([package(9, 'ADSL 8 Mbps')]),
        customer,
      );
      expect(offer, isNotNull);
      expect(offer!.accountId, 5);
      expect(offer.productId, 9);
      expect(offer.productName, 'ADSL 8 Mbps');
    });

    test('offers it for an account that had no default package yet', () {
      const fresh = SaleCustomer(customerId: 1, name: 'Ahmad', accountId: 5);
      final offer = defaultPackageOfferFor(renewal([_package]), fresh);
      expect(offer?.productId, 7);
    });

    test('goods beside the package do not get in the way', () {
      final offer = defaultPackageOfferFor(
        renewal([_sugar, package(9, 'ADSL 8 Mbps')]),
        customer,
      );
      expect(offer?.productId, 9);
    });

    test('two different packages: no telling which one is meant', () {
      expect(
        defaultPackageOfferFor(
          renewal([package(9, 'A'), package(10, 'B')]),
          customer,
        ),
        isNull,
      );
    });

    test('nothing without an account, or on a goods-only sale', () {
      const noAccount = SaleCustomer(customerId: 1, name: 'Ahmad');
      expect(defaultPackageOfferFor(renewal([_package]), noAccount), isNull);
      expect(defaultPackageOfferFor(renewal([_package]), null), isNull);
      expect(defaultPackageOfferFor(renewal([_sugar]), customer), isNull);
    });

    test('an item that is not a saved product cannot become the default', () {
      const typed = CartLine(
        name: 'Something typed',
        kind: ProductKind.service,
        unitPriceMinor: 500,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
      );
      expect(defaultPackageOfferFor(renewal([typed]), customer), isNull);
    });
  });

  group('CustomerHit.forSale', () {
    test('carries the customer and the account as the sale will record them',
        () {
      const hit = CustomerHit(
        customer: Customer(id: 4, name: 'سمير', phone: '0944 123 456'),
        account: CustomerAccount(
          id: 11,
          customerId: 4,
          accountNumber: '0011-2233',
          provider: 'MTN',
          defaultProductId: 7,
        ),
      );
      final sale = hit.forSale;
      expect(sale.customerId, 4);
      expect(sale.name, 'سمير');
      expect(sale.phone, '0944 123 456');
      expect(sale.accountId, 11);
      expect(sale.accountNumber, '0011-2233');
      expect(sale.accountProvider, 'MTN');
      expect(sale.defaultProductId, 7);
      expect(sale.hasAccount, isTrue);
    });

    test('a customer with no account attaches without one', () {
      const hit = CustomerHit(customer: Customer(id: 4, name: 'سمير'));
      expect(hit.forSale.hasAccount, isFalse);
      expect(hit.forSale.accountNumber, isNull);
    });
  });
}
