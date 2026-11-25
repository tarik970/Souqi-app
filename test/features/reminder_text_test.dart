import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/features/customers/reminder_text.dart';

void main() {
  final hit = CustomerHit(
    customer: const Customer(id: 1, name: 'Ahmad', phone: '0944 123 456'),
    account: CustomerAccount(
      id: 2,
      customerId: 1,
      accountNumber: '0011-2233',
      provider: 'MTN',
      nextDueAt: DateTime(2026, 12, 1),
    ),
    packageName: 'ADSL 4 Mbps',
  );

  group('the default reminder', () {
    test('exists in English and in Arabic, with its placeholders', () {
      final en = defaultReminderTemplate('en');
      final ar = defaultReminderTemplate('ar');
      expect(en, isNot(ar));
      for (final template in [en, ar]) {
        expect(template, contains('[name]'));
        expect(template, contains('[account]'));
        expect(template, contains('[date]'));
      }
      expect(en, startsWith('Hello'));
      expect(ar, contains('مرحباً'));
    });

    test('an unknown language falls back to Arabic, the app default', () {
      expect(defaultReminderTemplate('fr'), defaultReminderTemplate('ar'));
    });

    test('an empty stored text means the default for the language', () {
      expect(
        buildReminderText(template: '', hit: hit, language: 'en'),
        'Hello Ahmad, this is a reminder that your subscription (0011-2233) '
        'is due for renewal on 2026/12/01.',
      );
      expect(
        buildReminderText(template: '   ', hit: hit, language: 'ar'),
        contains('Ahmad'),
      );
    });

    test('the Arabic one carries the same date and number', () {
      final text = buildReminderText(template: '', hit: hit, language: 'ar');
      // intl's plain 'ar' locale writes Latin digits, like the rest of the
      // app's Arabic screens and invoices.
      expect(text, contains('2026/12/01'));
      expect(text, contains('0011-2233'), reason: 'the number as stored');
    });
  });

  group('a custom reminder', () {
    test('every placeholder is filled in', () {
      final text = buildReminderText(
        template: '[shop]: [name], [provider] [account] ([package]) '
            'is due [date]',
        hit: hit,
        language: 'en',
        shopName: 'Souqi Net',
      );
      expect(
        text,
        'Souqi Net: Ahmad, MTN 0011-2233 (ADSL 4 Mbps) is due 2026/12/01',
      );
    });

    test('a placeholder used twice is filled twice', () {
      expect(
        buildReminderText(
          template: '[name] [name]',
          hit: hit,
          language: 'en',
        ),
        'Ahmad Ahmad',
      );
    });

    test('placeholders with nothing to say leave no hole behind', () {
      const bare = CustomerHit(
        customer: Customer(id: 1, name: 'Ahmad'),
        account: CustomerAccount(id: 2, customerId: 1, accountNumber: '77'),
      );
      expect(
        buildReminderText(
          template: 'Hi [name] , your [provider] line ([package]) '
              'is due [date] .',
          hit: bare,
          language: 'en',
        ),
        'Hi Ahmad, your line is due.',
      );
    });

    test('text without placeholders is sent as it is', () {
      expect(
        buildReminderText(
          template: 'Please renew your subscription.',
          hit: hit,
          language: 'ar',
        ),
        'Please renew your subscription.',
      );
    });
  });

  test('formatReminderDate is numeric in both languages', () {
    final day = DateTime(2026, 3, 5);
    expect(formatReminderDate(day, language: 'en'), '2026/03/05');
    expect(formatReminderDate(day, language: 'ar'), '2026/03/05');
  });
}
