import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/due_dates.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/data/repositories/product_repository.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'db_test_utils.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase appDb;
  late Database db;
  late CustomerRepository customers;

  setUp(() async {
    appDb = await openTestDb();
    db = appDb.db;
    customers = CustomerRepository(db);
  });

  tearDown(() => appDb.close());

  Future<int> addCustomer(String name, {String? phone, String? notes}) =>
      customers.insert(Customer(name: name, phone: phone, notes: notes));

  Future<int> addAccount(
    int customerId,
    String number, {
    String? provider,
    String? label,
    int? packageId,
    int? renewalDays,
    DateTime? lastRenewalAt,
    DateTime? nextDueAt,
    bool isActive = true,
  }) =>
      customers.insertAccount(CustomerAccount(
        customerId: customerId,
        accountNumber: number,
        provider: provider,
        label: label,
        defaultProductId: packageId,
        renewalDays: renewalDays,
        lastRenewalAt: lastRenewalAt,
        nextDueAt: nextDueAt,
        isActive: isActive,
      ));

  /// "customer name / account number" for each hit, in order.
  List<String> describe(List<CustomerHit> hits) => [
        for (final hit in hits)
          hit.account == null
              ? hit.customer.name
              : '${hit.customer.name} / ${hit.account!.accountNumber}',
      ];

  group('customers', () {
    test('are stored as typed, with normalized search columns beside them',
        () async {
      final id = await addCustomer(
        '  أحمد الحَسَن ',
        phone: ' ٠٩٤٤ ١٢٣ ٤٥٦ ',
        notes: ' pays monthly ',
      );
      final row =
          (await db.query('customers', where: 'id = ?', whereArgs: [id]))
              .single;
      expect(row['name'], 'أحمد الحَسَن');
      expect(row['name_norm'], 'احمد حسن');
      expect(row['phone'], '٠٩٤٤ ١٢٣ ٤٥٦', reason: 'exactly as entered');
      expect(row['phone_norm'], '0944123456');
      expect(row['notes'], 'pays monthly');
      expect(row['is_active'], 1);
      expect(row['created_at'], isNotNull);
    });

    test('the phone is optional', () async {
      final id = await addCustomer('Samer', phone: '   ');
      final row =
          (await db.query('customers', where: 'id = ?', whereArgs: [id]))
              .single;
      expect(row['phone'], isNull);
      expect(row['phone_norm'], isNull);
      final customer = await customers.getById(id);
      expect(customer!.hasPhone, isFalse);
    });

    test('an edit rewrites the search columns too', () async {
      final id = await addCustomer('Ahmad', phone: '0944 111 111');
      final customer = (await customers.getById(id))!;
      await customers.update(customer.copyWith(
        name: 'السيد أحمد',
        phone: () => '+963 955 222 333',
      ));
      final row =
          (await db.query('customers', where: 'id = ?', whereArgs: [id]))
              .single;
      expect(row['name_norm'], 'سيد احمد');
      expect(row['phone_norm'], '963955222333');
    });

    test('are deactivated, never deleted', () async {
      final id = await addCustomer('Ahmad');
      await customers.setActive(id, false);
      expect((await customers.getById(id))!.isActive, isFalse);
      expect(await db.query('customers'), hasLength(1));
      await customers.setActive(id, true);
      expect((await customers.getById(id))!.isActive, isTrue);
    });

    test('the schema itself refuses to delete one that has accounts',
        () async {
      final id = await addCustomer('Ahmad');
      await addAccount(id, '0011');
      expect(
        () => db.delete('customers', where: 'id = ?', whereArgs: [id]),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('a customer and their first account are created together', () async {
      final (customerId, accountId) = await customers.insertWithAccount(
        const Customer(name: 'Ahmad', phone: '0944 123 456'),
        account: const CustomerAccount(
          customerId: 0,
          accountNumber: '0011-2233',
          provider: 'MTN',
        ),
      );
      expect(accountId, isNotNull);
      final account = (await customers.getAccount(accountId!))!;
      expect(account.customerId, customerId);
      expect(account.accountNumber, '0011-2233');
      expect(account.provider, 'MTN');
    });

    test('without an account only the customer is created', () async {
      final (customerId, accountId) =
          await customers.insertWithAccount(const Customer(name: 'Ahmad'));
      expect(accountId, isNull);
      expect(await customers.getById(customerId), isNotNull);
      expect(await db.query('customer_accounts'), isEmpty);
    });
  });

  group('the customers list', () {
    setUp(() async {
      await addCustomer('Samer', phone: '0933 555 111');
      await addCustomer('أحمد', phone: '0944 123 456');
      await addCustomer('Bassel');
    });

    test('is by name, with the number of active accounts', () async {
      final samer = (await customers.list(query: 'samer')).single;
      await addAccount(samer.customer.id!, '1');
      await addAccount(samer.customer.id!, '2');
      await addAccount(samer.customer.id!, '3', isActive: false);

      final all = await customers.list();
      expect(all.map((e) => e.customer.name), ['Bassel', 'Samer', 'أحمد']);
      expect(all.map((e) => e.accountCount), [0, 2, 0]);
    });

    test('searches by name, through the shared normalization', () async {
      expect(
        (await customers.list(query: 'احمد')).map((e) => e.customer.name),
        ['أحمد'],
      );
      expect(
        (await customers.list(query: 'SAM')).map((e) => e.customer.name),
        ['Samer'],
      );
    });

    test('searches by phone, however it is typed', () async {
      for (final typed in ['0944', '944 123', '٠٩٤٤١٢٣', '+963 944 123 456']) {
        expect(
          (await customers.list(query: typed)).map((e) => e.customer.name),
          ['أحمد'],
          reason: typed,
        );
      }
    });

    test('hides deactivated customers unless asked', () async {
      final bassel = (await customers.list(query: 'bassel')).single;
      await customers.setActive(bassel.customer.id!, false);
      expect((await customers.list()).map((e) => e.customer.name),
          ['Samer', 'أحمد']);
      expect(
        (await customers.list(includeInactive: true))
            .map((e) => e.customer.name),
        ['Bassel', 'Samer', 'أحمد'],
      );
    });

    test('pages by name without skipping or repeating anyone', () async {
      // Two customers with the very same name sit on a page boundary.
      await addCustomer('Samer');
      final seen = <int>[];
      CustomerListEntry? after;
      while (true) {
        final page = await customers.list(after: after, limit: 2);
        if (page.isEmpty) break;
        seen.addAll(page.map((e) => e.customer.id!));
        after = page.last;
      }
      expect(seen, hasLength(4));
      expect(seen.toSet(), hasLength(4));
    });

    test('text that normalizes to nothing matches nobody', () async {
      expect(await customers.list(query: 'ـــ'), isEmpty);
    });
  });

  group('accounts', () {
    late int customerId;

    setUp(() async => customerId = await addCustomer('Ahmad'));

    test('keep the number as typed: leading zeros, dashes and letters',
        () async {
      final id = await addAccount(customerId, ' 0011-2233 ab ');
      final row = (await db
              .query('customer_accounts', where: 'id = ?', whereArgs: [id]))
          .single;
      expect(row['account_number'], '0011-2233 ab');
      expect(row['account_number_norm'], '00112233AB');
    });

    test('round-trip every field', () async {
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final lastRenewal = DateTime(2026, 11, 1, 9, 30);
      final id = await customers.insertAccount(CustomerAccount(
        customerId: customerId,
        accountNumber: '0011',
        label: 'ADSL line',
        provider: 'Syrian Telecom',
        defaultProductId: packageId,
        renewalDays: 30,
        lastRenewalAt: lastRenewal,
        nextDueAt: nextDueAfter(lastRenewal, 30),
        notes: 'second floor',
      ));
      final account = (await customers.getAccount(id))!;
      expect(account.label, 'ADSL line');
      expect(account.provider, 'Syrian Telecom');
      expect(account.defaultProductId, packageId);
      expect(account.renewalDays, 30);
      expect(account.lastRenewalAt!.toLocal(), lastRenewal);
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 12, 1));
      expect(account.notes, 'second floor');
      expect(account.isActive, isTrue);
    });

    test('a customer can have several, listed with their package', () async {
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      await addAccount(customerId, '0011',
          packageId: packageId, nextDueAt: DateTime(2026, 12, 5));
      await addAccount(customerId, '0022', nextDueAt: DateTime(2026, 12, 1));
      await addAccount(customerId, '0033');
      await addAccount(customerId, '0044', isActive: false);

      final accounts = await customers.accountsOf(customerId);
      // Active first, the soonest due on top, no due date last.
      expect(accounts.map((h) => h.account!.accountNumber),
          ['0022', '0011', '0033', '0044']);
      expect(accounts[1].packageName, 'ADSL');
      expect(accounts[0].packageName, isNull);
      expect(accounts.every((h) => h.customer.name == 'Ahmad'), isTrue);
    });

    test('the renewal period must be positive (schema check)', () async {
      expect(
        () => addAccount(customerId, '0011', renewalDays: 0),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('an edit rewrites the normalized number', () async {
      final id = await addAccount(customerId, '0011');
      final account = (await customers.getAccount(id))!;
      await customers.updateAccount(account.copyWith(accountNumber: 'zz-99'));
      final row = (await db
              .query('customer_accounts', where: 'id = ?', whereArgs: [id]))
          .single;
      expect(row['account_number_norm'], 'ZZ99');
    });

    test('the default package can be set and cleared', () async {
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final id = await addAccount(customerId, '0011');
      await customers.setDefaultPackage(id, packageId);
      expect((await customers.getAccount(id))!.defaultProductId, packageId);
      await customers.setDefaultPackage(id, null);
      expect((await customers.getAccount(id))!.defaultProductId, isNull);
    });
  });

  group('the duplicate-number warning', () {
    late int ahmad;
    late int samer;

    setUp(() async {
      ahmad = await addCustomer('Ahmad');
      samer = await addCustomer('Samer');
      await addAccount(ahmad, '0011-2233', provider: 'MTN');
    });

    test('the same number for the same provider is reported, with its owner',
        () async {
      final found =
          await customers.findDuplicateAccounts('0011-2233', provider: 'MTN');
      expect(found, hasLength(1));
      expect(found.single.customerName, 'Ahmad');
      expect(found.single.account.accountNumber, '0011-2233');
    });

    test('compares normalized numbers: spaces, dashes, Arabic digits, case',
        () async {
      await addAccount(samer, 'ab-77', provider: 'MTN');
      for (final typed in ['00112233', '0011 2233', '٠٠١١-٢٢٣٣', ' 0011—2233 ']) {
        expect(
          await customers.findDuplicateAccounts(typed, provider: 'MTN'),
          hasLength(1),
          reason: typed,
        );
      }
      expect(await customers.findDuplicateAccounts('AB 77', provider: 'MTN'),
          hasLength(1));
    });

    test('compares normalized providers', () async {
      for (final provider in ['mtn', ' MTN ', 'Mtn']) {
        expect(
          await customers.findDuplicateAccounts('0011-2233',
              provider: provider),
          hasLength(1),
          reason: provider,
        );
      }
    });

    test('the same number under another provider is another account',
        () async {
      expect(
        await customers.findDuplicateAccounts('0011-2233',
            provider: 'Syriatel'),
        isEmpty,
      );
      expect(await customers.findDuplicateAccounts('0011-2233'), isEmpty,
          reason: 'no provider is not MTN');
    });

    test('two accounts with no provider at all count as the same provider',
        () async {
      await addAccount(samer, '5555');
      expect(await customers.findDuplicateAccounts('55 55'), hasLength(1));
      expect(await customers.findDuplicateAccounts('5555', provider: '  '),
          hasLength(1));
    });

    test('a different number is no duplicate', () async {
      expect(
        await customers.findDuplicateAccounts('0011-2234', provider: 'MTN'),
        isEmpty,
      );
      // Leading zeros are part of the number.
      expect(
        await customers.findDuplicateAccounts('112233', provider: 'MTN'),
        isEmpty,
      );
    });

    test('an account is not its own duplicate when edited', () async {
      final id = await addAccount(samer, '9999', provider: 'MTN');
      expect(
        await customers.findDuplicateAccounts('9999',
            provider: 'MTN', excludeId: id),
        isEmpty,
      );
      expect(
        await customers.findDuplicateAccounts('0011-2233',
            provider: 'MTN', excludeId: id),
        hasLength(1),
      );
    });

    test('it is only a warning: the duplicate can still be saved', () async {
      await addAccount(samer, '0011 2233', provider: 'mtn');
      final found =
          await customers.findDuplicateAccounts('00112233', provider: 'MTN');
      expect(found.map((d) => d.customerName), ['Ahmad', 'Samer']);
    });

    test('an empty number has no duplicates', () async {
      expect(await customers.findDuplicateAccounts(' - '), isEmpty);
    });
  });

  group('provider suggestions', () {
    test('are the providers typed before, the most used first', () async {
      final id = await addCustomer('Ahmad');
      await addAccount(id, '1', provider: 'Syriatel');
      await addAccount(id, '2', provider: 'MTN');
      await addAccount(id, '3', provider: 'MTN');
      await addAccount(id, '4');
      await addAccount(id, '5', provider: '  ');
      expect(await customers.providerSuggestions(), ['MTN', 'Syriatel']);
    });

    test('spellings of one provider are offered once', () async {
      final id = await addCustomer('Ahmad');
      await addAccount(id, '1', provider: 'MTN');
      await addAccount(id, '2', provider: 'MTN');
      await addAccount(id, '3', provider: 'mtn');
      await addAccount(id, '4', provider: 'السورية للاتصالات');
      await addAccount(id, '5', provider: 'سورية للإتصالات');
      final suggestions = await customers.providerSuggestions();
      expect(suggestions, hasLength(2));
      expect(suggestions, contains('MTN'));
    });
  });

  group('quick search', () {
    late int ahmad;
    late int samer;
    late int packageId;

    setUp(() async {
      packageId = await insertProduct(db, name: 'ADSL 4 Mbps', kind: 'SERVICE');
      ahmad = await addCustomer('أحمد الحسن', phone: '0944 123 456');
      samer = await addCustomer('Samer Haddad', phone: '+963 933 555 111');
      await addCustomer('Bassel', phone: '0955 444 666');
      await addAccount(
        ahmad,
        '0011-2233',
        provider: 'MTN',
        packageId: packageId,
        renewalDays: 30,
        lastRenewalAt: DateTime(2026, 11, 1),
        nextDueAt: DateTime(2026, 12, 1),
      );
      await addAccount(ahmad, 'AB-7700', provider: 'Syriatel');
      await addAccount(samer, '0099 8877');
    });

    Future<List<String>> find(String query) async =>
        describe(await customers.quickSearch(query));

    test('finds a customer by part of the name, in either script', () async {
      expect(await find('حسن'), ['أحمد الحسن / 0011-2233', 'أحمد الحسن / AB-7700']);
      expect(await find('احمد'), hasLength(2));
      expect(await find('الحسن'), hasLength(2), reason: 'leading "ال"');
      expect(await find('hadd'), ['Samer Haddad / 0099 8877']);
      expect(await find('SAMER'), ['Samer Haddad / 0099 8877']);
    });

    test('a customer with no accounts is one row', () async {
      expect(await find('bassel'), ['Bassel']);
    });

    test('finds a customer by phone, ignoring spaces and dashes', () async {
      for (final typed in ['0944123456', '0944 123 456', '0944-123-456', '4412', '0944']) {
        expect(await find(typed), hasLength(2), reason: typed);
      }
    });

    test('finds a phone typed in Arabic-Indic digits', () async {
      expect(await find('٠٩٤٤١٢٣٤٥٦'), hasLength(2));
      expect(await find('٠٩٤٤ ١٢٣'), hasLength(2));
    });

    test('finds a phone whichever way the country code was written',
        () async {
      // Stored "0944 123 456", typed internationally.
      expect(await find('+963 944 123 456'), hasLength(2));
      expect(await find('00963944123456'), hasLength(2));
      // Stored "+963 933 555 111", typed with the trunk zero.
      expect(await find('0933 555 111'), ['Samer Haddad / 0099 8877']);
      expect(await find('0933555'), ['Samer Haddad / 0099 8877']);
    });

    test('finds an account by part of its number', () async {
      expect(await find('0011'), ['أحمد الحسن / 0011-2233']);
      expect(await find('2233'), ['أحمد الحسن / 0011-2233']);
      expect(await find('8877'), ['Samer Haddad / 0099 8877']);
    });

    test('ignores spaces and dashes in an account number', () async {
      for (final typed in ['00112233', '0011 2233', '0011-22', '00 11 22 33']) {
        expect(await find(typed), ['أحمد الحسن / 0011-2233'], reason: typed);
      }
      expect(await find('00998877'), ['Samer Haddad / 0099 8877']);
      expect(await find('0099-8877'), ['Samer Haddad / 0099 8877']);
    });

    test('finds an account number typed in Arabic-Indic digits', () async {
      expect(await find('٠٠١١٢٢٣٣'), ['أحمد الحسن / 0011-2233']);
      expect(await find('٠٠١١-٢٢'), ['أحمد الحسن / 0011-2233']);
    });

    test('keeps the letters of an account number, in any case', () async {
      expect(await find('AB-7700'), ['أحمد الحسن / AB-7700']);
      expect(await find('ab7700'), ['أحمد الحسن / AB-7700']);
      expect(await find('b-77'), ['أحمد الحسن / AB-7700']);
      // The digits alone still find it; other letters do not.
      expect(await find('7700'), ['أحمد الحسن / AB-7700']);
      expect(await find('XY7700'), isEmpty);
    });

    test('letters in the query never match a phone by their digits',
        () async {
      // "ZZ-0955" has the digits of Bassel's phone in it, but it is not a
      // phone number.
      expect(await find('ZZ-0955'), isEmpty);
    });

    test('a row carries everything the result shows', () async {
      final hit = (await customers.quickSearch('00112233')).single;
      expect(hit.customer.name, 'أحمد الحسن');
      expect(hit.customer.phone, '0944 123 456');
      expect(hit.account!.accountNumber, '0011-2233');
      expect(hit.account!.provider, 'MTN');
      expect(hit.packageName, 'ADSL 4 Mbps');
      expect(hit.packageActive, isTrue);
      expect(hit.account!.lastRenewalAt!.toLocal(), DateTime(2026, 11, 1));
      expect(hit.account!.nextDueAt!.toLocal(), DateTime(2026, 12, 1));
      expect(
        hit.account!.dueStatus(now: DateTime(2026, 11, 30, 9), soonDays: 3),
        const DueStatus(DueBucket.soon, 1),
      );
    });

    test('says when the default package has been deactivated', () async {
      await ProductRepository(db).setActive(packageId, false);
      final hit = (await customers.quickSearch('00112233')).single;
      expect(hit.packageName, 'ADSL 4 Mbps');
      expect(hit.packageActive, isFalse);
    });

    test('the best match comes first', () async {
      final exact = await addCustomer('Zed');
      await addAccount(exact, '2233');
      // "2233" is Zed's whole number and only the tail of Ahmad's.
      expect(await find('2233'), ['Zed / 2233', 'أحمد الحسن / 0011-2233']);

      await addCustomer('Sam');
      // An exact name, then names starting with the text.
      expect((await find('sam')).first, 'Sam');
    });

    test('leaves out deactivated customers and deactivated accounts',
        () async {
      await customers.setActive(samer, false);
      expect(await find('samer'), isEmpty);
      expect(await find('8877'), isEmpty);

      final accounts = await customers.accountsOf(ahmad);
      await customers.setAccountActive(accounts.first.account!.id!, false);
      // The customer is still found by name, with the account that is left.
      expect(await find('احمد'), ['أحمد الحسن / AB-7700']);
      expect(await find('00112233'), isEmpty);
    });

    test('a customer whose only account is deactivated is still found',
        () async {
      final accounts = await customers.accountsOf(samer);
      await customers.setAccountActive(accounts.single.account!.id!, false);
      expect(await find('samer'), ['Samer Haddad']);
    });

    test('an empty query finds nothing', () async {
      expect(await find(''), isEmpty);
      expect(await find('   '), isEmpty);
      expect(customers.quickSearchQuery(' '), isNull);
    });

    test('LIKE wildcards typed by the user match themselves', () async {
      expect(await find('%'), isEmpty);
      expect(await find('_'), isEmpty);
      final id = await addCustomer('100% Net');
      await addAccount(id, 'A_1');
      expect(await find('100%'), ['100% Net / A_1']);
      expect(await find('a_1'), ['100% Net / A_1']);
    });

    test('is bounded', () async {
      for (var i = 0; i < 12; i++) {
        await addCustomer('Many $i');
      }
      expect(await customers.quickSearch('many', limit: 5), hasLength(5));
    });

    test('without the accounts feature only customers are searched',
        () async {
      final byNumber =
          await customers.quickSearch('00112233', includeAccounts: false);
      expect(byNumber, isEmpty);
      final byName =
          await customers.quickSearch('احمد', includeAccounts: false);
      expect(describe(byName), ['أحمد الحسن']);
    });
  });

  group('the due list', () {
    late int ahmad;
    final now = DateTime(2026, 12, 1, 10);

    setUp(() async {
      ahmad = await addCustomer('Ahmad', phone: '0944 123 456');
      await addAccount(ahmad, 'overdue-5', nextDueAt: DateTime(2026, 11, 26));
      await addAccount(ahmad, 'overdue-1', nextDueAt: DateTime(2026, 11, 30));
      await addAccount(ahmad, 'today', nextDueAt: DateTime(2026, 12, 1));
      await addAccount(ahmad, 'in-1', nextDueAt: DateTime(2026, 12, 2));
      await addAccount(ahmad, 'in-3', nextDueAt: DateTime(2026, 12, 4));
      await addAccount(ahmad, 'in-4', nextDueAt: DateTime(2026, 12, 5));
      await addAccount(ahmad, 'no-date');
    });

    Future<List<String>> due({required DateTime at, int soonDays = 3}) async =>
        [
          for (final hit
              in await customers.dueList(now: at, soonDays: soonDays))
            '${hit.account!.accountNumber}:'
                '${hit.account!.dueStatus(now: at, soonDays: soonDays)!.bucket.name}',
        ];

    test('is overdue, today and the next N days, the longest overdue first',
        () async {
      expect(await due(at: now), [
        'overdue-5:overdue',
        'overdue-1:overdue',
        'today:today',
        'in-1:soon',
        'in-3:soon',
      ]);
    });

    test('counts each bucket', () async {
      final counts = await customers.dueCounts(now: now, soonDays: 3);
      expect(counts.overdue, 2);
      expect(counts.today, 1);
      expect(counts.soon, 2);
      expect(counts.total, 5);
    });

    test('the window follows the setting', () async {
      expect(await due(at: now, soonDays: 4), hasLength(6));
      expect(await due(at: now, soonDays: 0), hasLength(3));
      expect((await customers.dueCounts(now: now, soonDays: 0)).soon, 0);
    });

    test('one minute before midnight "today" is still due today', () async {
      final late = DateTime(2026, 12, 1, 23, 59);
      expect(await due(at: late), [
        'overdue-5:overdue',
        'overdue-1:overdue',
        'today:today',
        'in-1:soon',
        'in-3:soon',
      ]);
      final counts = await customers.dueCounts(now: late, soonDays: 3);
      expect([counts.overdue, counts.today, counts.soon], [2, 1, 2]);
    });

    test('at midnight every bucket moves on by a day', () async {
      final midnight = DateTime(2026, 12, 2);
      expect(await due(at: midnight), [
        'overdue-5:overdue',
        'overdue-1:overdue',
        'today:overdue',
        'in-1:today',
        'in-3:soon',
        'in-4:soon',
      ]);
      final counts = await customers.dueCounts(now: midnight, soonDays: 3);
      expect([counts.overdue, counts.today, counts.soon], [3, 1, 2]);
    });

    test('the list and the counts agree on both sides of midnight', () async {
      for (final at in [
        DateTime(2026, 11, 30, 23, 59, 59),
        DateTime(2026, 12, 1),
        DateTime(2026, 12, 1, 0, 0, 1),
        DateTime(2026, 12, 4, 23, 59),
        DateTime(2026, 12, 5),
      ]) {
        final rows = await due(at: at);
        final counts = await customers.dueCounts(now: at, soonDays: 3);
        expect(rows.where((r) => r.endsWith(':overdue')).length,
            counts.overdue,
            reason: '$at overdue');
        expect(rows.where((r) => r.endsWith(':today')).length, counts.today,
            reason: '$at today');
        expect(rows.where((r) => r.endsWith(':soon')).length, counts.soon,
            reason: '$at soon');
        expect(rows.any((r) => r.endsWith(':later')), isFalse, reason: '$at');
      }
    });

    test('leaves out deactivated accounts and deactivated customers',
        () async {
      final accounts = await customers.accountsOf(ahmad);
      final today =
          accounts.firstWhere((h) => h.account!.accountNumber == 'today');
      await customers.setAccountActive(today.account!.id!, false);
      expect(await due(at: now), hasLength(4));
      expect((await customers.dueCounts(now: now, soonDays: 3)).today, 0);

      await customers.setActive(ahmad, false);
      expect(await due(at: now), isEmpty);
      expect((await customers.dueCounts(now: now, soonDays: 3)).total, 0);
    });

    test('is bounded, and the counts still cover everything', () async {
      final rows = await customers.dueList(now: now, soonDays: 3, limit: 2);
      expect(rows.map((h) => h.account!.accountNumber),
          ['overdue-5', 'overdue-1']);
      expect((await customers.dueCounts(now: now, soonDays: 3)).total, 5);
    });

    test('a row carries the customer, the phone and the package', () async {
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final samer = await addCustomer('Samer', phone: '0933 555 111');
      await addAccount(samer, 'S-1',
          provider: 'MTN',
          packageId: packageId,
          nextDueAt: DateTime(2026, 11, 1));
      final first = (await customers.dueList(now: now, soonDays: 3)).first;
      expect(first.customer.name, 'Samer');
      expect(first.customer.phone, '0933 555 111');
      expect(first.account!.provider, 'MTN');
      expect(first.packageName, 'ADSL');
    });
  });

  group('recordRenewal', () {
    late int customerId;

    setUp(() async => customerId = await addCustomer('Ahmad'));

    test('sets the last renewal and the next due day from the period',
        () async {
      final id = await addAccount(customerId, '0011', renewalDays: 30);
      final renewedAt = DateTime(2026, 11, 25, 23, 50);
      await customers.recordRenewal(id, renewedAt);
      final account = (await customers.getAccount(id))!;
      expect(account.lastRenewalAt!.toLocal(), renewedAt);
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 12, 25));
    });

    test('next due is last renewal + period, not old due + period', () async {
      final id = await addAccount(
        customerId,
        '0011',
        renewalDays: 30,
        lastRenewalAt: DateTime(2026, 10, 1),
        nextDueAt: DateTime(2026, 10, 31),
      );
      // Renewed three weeks late.
      await customers.recordRenewal(id, DateTime(2026, 11, 21, 12));
      final account = (await customers.getAccount(id))!;
      expect(account.nextDueAt!.toLocal(), DateTime(2026, 12, 21));
    });

    test('an account with no period keeps no due date', () async {
      final id = await addAccount(customerId, '0011',
          nextDueAt: DateTime(2026, 11, 20));
      await customers.recordRenewal(id, DateTime(2026, 11, 25, 9));
      final account = (await customers.getAccount(id))!;
      expect(account.lastRenewalAt!.toLocal(), DateTime(2026, 11, 25, 9));
      expect(account.nextDueAt, isNull);
    });

    test('an unknown account is ignored', () async {
      await customers.recordRenewal(404, DateTime(2026, 11, 25));
    });
  });

  group('history and totals', () {
    late int ahmad;

    Future<int> sale(
      int invoiceNo, {
      required int? customerId,
      required DateTime at,
      int total = 1000,
      List<String> items = const ['ADSL'],
      String? accountNumber,
    }) async {
      final id = await insertInvoice(
        db,
        invoiceNo: invoiceNo,
        createdAt: at,
        subtotalMinor: total,
        customerName: 'Ahmad',
        accountNumber: accountNumber,
      );
      await db.update('invoices', {'customer_id': customerId},
          where: 'id = ?', whereArgs: [id]);
      for (var i = 0; i < items.length; i++) {
        await insertInvoiceItem(db,
            invoiceId: id, name: items[i], sortOrder: i);
      }
      return id;
    }

    setUp(() async {
      ahmad = await addCustomer('Ahmad');
      final other = await addCustomer('Samer');
      await sale(1, customerId: ahmad, at: DateTime(2026, 11, 1), total: 5000);
      await sale(
        2,
        customerId: ahmad,
        at: DateTime(2026, 11, 20),
        total: 7000,
        items: ['ADSL 4 Mbps', 'Sugar', 'Tea'],
        accountNumber: '0011-2233',
      );
      await sale(3, customerId: other, at: DateTime(2026, 11, 21));
      await sale(4, customerId: null, at: DateTime(2026, 11, 22));
    });

    test('lists only that customer\'s invoices, newest first', () async {
      final history = await customers.history(ahmad);
      expect(history.map((i) => i.invoiceNo), [2, 1]);
      expect(history.first.totalMinor, 7000);
      expect(history.first.itemCount, 3);
      expect(history.first.firstItemName, 'ADSL 4 Mbps');
      expect(history.first.accountNumber, '0011-2233');
      expect(history.last.accountNumber, isNull);
    });

    test('is bounded', () async {
      expect(await customers.history(ahmad, limit: 1), hasLength(1));
    });

    test('totals are in base currency, from the stored snapshots', () async {
      final totals = await customers.totals(ahmad);
      expect(totals.invoiceCount, 2);
      expect(totals.totalBaseMinor, 12000);
      expect(totals.lastPurchaseAt!.toLocal(), DateTime(2026, 11, 20));
    });

    test('a customer who never bought anything', () async {
      final id = await addCustomer('New');
      final totals = await customers.totals(id);
      expect(totals.invoiceCount, 0);
      expect(totals.totalBaseMinor, 0);
      expect(totals.lastPurchaseAt, isNull);
      expect(await customers.history(id), isEmpty);
    });

    test('a deleted invoice leaves the history (and nothing else)', () async {
      final history = await customers.history(ahmad);
      await db.delete('invoices',
          where: 'id = ?', whereArgs: [history.first.id]);
      expect((await customers.history(ahmad)).map((i) => i.invoiceNo), [1]);
      expect((await customers.totals(ahmad)).totalBaseMinor, 5000);
    });
  });

  group('a product used as a default package', () {
    test('can only be deactivated, not deleted', () async {
      final products = ProductRepository(db);
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final customerId = await addCustomer('Ahmad');
      final accountId =
          await addAccount(customerId, '0011', packageId: packageId);

      expect(await products.delete(packageId), ProductDeleteResult.deactivated);
      final product = (await products.getById(packageId))!;
      expect(product.isActive, isFalse);
      // The account still points at it.
      expect((await customers.getAccount(accountId))!.defaultProductId,
          packageId);
    });

    test('still counts when the account itself is deactivated', () async {
      final products = ProductRepository(db);
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final customerId = await addCustomer('Ahmad');
      await addAccount(customerId, '0011',
          packageId: packageId, isActive: false);
      expect(await products.delete(packageId), ProductDeleteResult.deactivated);
    });

    test('once no account uses it, it can be deleted', () async {
      final products = ProductRepository(db);
      final packageId = await insertProduct(db, name: 'ADSL', kind: 'SERVICE');
      final customerId = await addCustomer('Ahmad');
      final accountId =
          await addAccount(customerId, '0011', packageId: packageId);
      await customers.setDefaultPackage(accountId, null);
      expect(await products.delete(packageId), ProductDeleteResult.deleted);
      expect(await products.getById(packageId), isNull);
    });

    test('a product no account uses is deleted as before', () async {
      final products = ProductRepository(db);
      final id = await insertProduct(db, name: 'Sugar');
      expect(await products.delete(id), ProductDeleteResult.deleted);
    });
  });

  group('the query plans', () {
    /// What sqlite says it will do.
    Future<String> plan(String sql, List<Object?> args) async {
      final rows = await db.rawQuery('EXPLAIN QUERY PLAN $sql', args);
      return rows.map((r) => r['detail']).join(' | ');
    }

    test('the quick search is ONE pass: accounts and packages by index',
        () async {
      for (final query in ['احمد', '0944 123', '0011-2233', 'AB-77']) {
        final (sql, args) = customers.quickSearchQuery(query)!;
        final detail = await plan(sql, args);
        // Each customer's accounts come through the customer index and the
        // package by primary key — never a scan of the accounts or the
        // products inside the loop over customers (5,000 × 10,000).
        expect(detail, contains('idx_accounts_customer'), reason: query);
        expect(detail, isNot(contains('SCAN a')), reason: '$query: $detail');
        expect(detail, isNot(contains('SCAN p')), reason: '$query: $detail');
        expect(detail, contains('PRIMARY KEY'), reason: query);
        expect(sql, contains('LIMIT ?'));
      }
    });

    test('the due list is a range read of the due-date index, in order',
        () async {
      final (sql, args) =
          customers.dueListQuery(now: DateTime(2026, 12, 1), soonDays: 3);
      final detail = await plan(sql, args);
      expect(detail, contains('idx_accounts_due'));
      expect(detail, isNot(contains('SCAN a')), reason: detail);
      expect(detail, isNot(contains('SCAN c')), reason: detail);
      // Already in due-date order: nothing to sort.
      expect(detail, isNot(contains('TEMP B-TREE')), reason: detail);
      expect(sql, contains('LIMIT ?'));
    });

    test('the duplicate check is an index lookup', () async {
      final detail = await plan(
        'SELECT a.id FROM customer_accounts a '
        'WHERE a.account_number_norm = ?',
        ['00112233'],
      );
      expect(detail, contains('idx_accounts_number_norm'));
    });

    test('a customer\'s history goes through the customer index', () async {
      final detail = await plan(
        'SELECT i.id FROM invoices i WHERE i.customer_id = ? '
        'ORDER BY i.created_at DESC, i.id DESC LIMIT 50',
        [1],
      );
      expect(detail, contains('idx_invoices_customer'));
      expect(detail, isNot(contains('SCAN i')));
    });
  });
}
