import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/domain/models/cart.dart';
import 'package:souqi/domain/models/invoice.dart';
import 'package:souqi/domain/models/invoice_settings.dart';
import 'package:souqi/domain/models/product.dart';
import 'package:souqi/features/invoice/invoice_view.dart';

import 'invoice_test_utils.dart';

/// The customer lines of the printed / shared invoice: the name, phone,
/// account number and provider SNAPSHOTS, each shown or hidden by its
/// invoice-settings toggle, and the "mask all but the last 4" option.
void main() {
  Invoice renewal({
    String? customerName = 'Ahmad Hasan',
    String? customerPhone = '0944 123 456',
    String? accountNumber = '0011-2233-4455',
    String? accountProvider = 'MTN',
  }) {
    final ctx = CurrencyContext.of([syp, usd], baseCode: 'SYP');
    return Invoice.fromCart(
      cart: const Cart().add(const CartLine(
        name: 'ADSL 4 Mbps',
        kind: ProductKind.service,
        unitPriceMinor: 35000,
        priceCurrencyCode: 'SYP',
        qtyThousandths: 1000,
      )),
      ctx: ctx,
      createdAt: DateTime(2026, 11, 25, 10),
      customerId: customerName == null ? null : 1,
      customerName: customerName,
      customerPhone: customerPhone,
      accountId: accountNumber == null ? null : 1,
      accountNumber: accountNumber,
      accountProvider: accountProvider,
    ).copyWith(invoiceNo: 5);
  }

  Future<void> pump(
    WidgetTester tester,
    InvoiceSettings settings, {
    Invoice? invoice,
  }) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: settings.printableDots.toDouble(),
            child: InvoiceView(
              invoice: invoice ?? renewal(),
              settings: settings,
              currencies: testCurrencies,
            ),
          ),
        ),
      ),
    );
  }

  const english = InvoiceSettings(language: 'en');

  testWidgets('by default the name, phone, provider and number are printed',
      (tester) async {
    await pump(tester, english);
    expect(find.text('Customer:'), findsOneWidget);
    expect(find.text('Ahmad Hasan'), findsOneWidget);
    expect(find.text('0944 123 456'), findsOneWidget);
    expect(find.text('Account no.:'), findsOneWidget);
    expect(find.text('MTN'), findsOneWidget);
    expect(find.text('0011-2233-4455'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the customer-name toggle hides the name only', (tester) async {
    await pump(tester, english.copyWith(showCustomerName: false));
    expect(find.text('Ahmad Hasan'), findsNothing);
    expect(find.text('Customer:'), findsNothing);
    expect(find.text('0944 123 456'), findsOneWidget);
    expect(find.text('0011-2233-4455'), findsOneWidget);
    expect(find.text('MTN'), findsOneWidget);
  });

  testWidgets('the phone toggle hides the phone only', (tester) async {
    await pump(tester, english.copyWith(showCustomerPhone: false));
    expect(find.text('0944 123 456'), findsNothing);
    expect(find.text('Ahmad Hasan'), findsOneWidget);
    expect(find.text('0011-2233-4455'), findsOneWidget);
  });

  testWidgets('the account toggle hides the number and its provider',
      (tester) async {
    await pump(tester, english.copyWith(showAccountNumber: false));
    expect(find.text('0011-2233-4455'), findsNothing);
    expect(find.text('MTN'), findsNothing);
    expect(find.text('Account no.:'), findsNothing);
    expect(find.text('Ahmad Hasan'), findsOneWidget);
    expect(find.text('0944 123 456'), findsOneWidget);
  });

  testWidgets('masking prints all but the last 4, keeping the grouping',
      (tester) async {
    await pump(tester, english.copyWith(maskAccountNumber: true));
    expect(find.text('****-****-4455'), findsOneWidget);
    expect(find.text('0011-2233-4455'), findsNothing);
    // The provider is not a secret.
    expect(find.text('MTN'), findsOneWidget);
    // And the phone is not what the mask is about.
    expect(find.text('0944 123 456'), findsOneWidget);
  });

  testWidgets('masking with the account hidden prints no account at all',
      (tester) async {
    await pump(
      tester,
      english.copyWith(showAccountNumber: false, maskAccountNumber: true),
    );
    expect(find.textContaining('4455'), findsNothing);
  });

  testWidgets('a number of four characters or fewer is not masked',
      (tester) async {
    await pump(
      tester,
      english.copyWith(maskAccountNumber: true),
      invoice: renewal(accountNumber: 'A-12'),
    );
    expect(find.text('A-12'), findsOneWidget);
  });

  testWidgets('letters in an account number are printed as they are',
      (tester) async {
    await pump(tester, english, invoice: renewal(accountNumber: 'ab-0077'));
    expect(find.text('ab-0077'), findsOneWidget);
  });

  testWidgets('an account with no provider prints the number alone',
      (tester) async {
    await pump(tester, english, invoice: renewal(accountProvider: null));
    expect(find.text('0011-2233-4455'), findsOneWidget);
    expect(find.text('Account no.:'), findsOneWidget);
  });

  testWidgets('a customer with no phone and no account prints the name only',
      (tester) async {
    await pump(
      tester,
      english,
      invoice: renewal(
        customerPhone: null,
        accountNumber: null,
        accountProvider: null,
      ),
    );
    expect(find.text('Ahmad Hasan'), findsOneWidget);
    expect(find.text('Phone:'), findsNothing);
    expect(find.text('Account no.:'), findsNothing);
  });

  testWidgets('a sale with no customer prints none of these lines',
      (tester) async {
    await pump(
      tester,
      english,
      invoice: renewal(
        customerName: null,
        customerPhone: null,
        accountNumber: null,
        accountProvider: null,
      ),
    );
    expect(find.text('Customer:'), findsNothing);
    expect(find.text('Phone:'), findsNothing);
    expect(find.text('Account no.:'), findsNothing);
  });

  testWidgets('the labels follow the INVOICE language', (tester) async {
    await pump(tester, const InvoiceSettings(language: 'ar'));
    expect(find.text('Customer:'), findsNothing);
    expect(find.text('Ahmad Hasan'), findsOneWidget);
    // The number keeps its left-to-right order on a right-to-left invoice.
    final number = tester.widget<Text>(find.text('0011-2233-4455'));
    expect(number.textDirection, TextDirection.ltr);
    final phone = tester.widget<Text>(find.text('0944 123 456'));
    expect(phone.textDirection, TextDirection.ltr);
  });

  testWidgets('a long provider and number fit 58 mm paper', (tester) async {
    for (final language in ['ar', 'en']) {
      await pump(
        tester,
        InvoiceSettings(
          language: language,
          paperWidthMm: 58,
          sideMarginMm: 5,
        ),
        invoice: renewal(
          customerName: 'عبد الرحمن محمد الأحمد الحسن',
          customerPhone: '+963 944 123 456',
          accountNumber: '0011-2233-4455-6677-8899',
          accountProvider: 'السورية للاتصالات والإنترنت',
        ),
      );
      expect(tester.takeException(), isNull, reason: language);
      expect(find.text('0011-2233-4455-6677-8899'), findsOneWidget);
    }
  });
}
