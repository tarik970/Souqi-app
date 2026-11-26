import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/config/features.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/licensing/license_codec.dart';
import 'package:souqi/core/licensing/license_service.dart';
import 'package:souqi/core/licensing/license_status.dart';
import 'package:souqi/core/licensing/license_store.dart';
import 'package:souqi/core/security/code_cipher.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/audit_repository.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../core/licensing/license_test_kit.dart';
import 'db_test_utils.dart';

/// OFFLINE LICENSING, as the service does it: activation, the device
/// binding, the trial, the clock that cannot be turned back, the build's
/// signature, and the developer's PIN reset codes.
///
/// The "developer" is a key pair made in memory for this run
/// ([TestDeveloper]); the "phone" is a fake identity, an in-memory Keystore
/// and a real sqlite database.
void main() {
  setUpAll(sqfliteFfiInit);

  late TestDeveloper developer;
  late AppDatabase database;
  late InMemoryKeyStore keys;
  late FakeLicensePlatform phone;
  late TestClock clock;

  final t0 = DateTime.utc(2026, 11, 26, 10);

  setUpAll(() async => developer = await TestDeveloper.create());

  setUp(() async {
    database = await openTestDb();
    keys = InMemoryKeyStore();
    phone = FakeLicensePlatform();
    clock = TestClock(t0);
  });

  tearDown(() async => database.close());

  /// The service as a (new) app start would make it.
  LicenseService service({
    AppDatabase? db,
    InMemoryKeyStore? store,
    FakeLicensePlatform? on,
    TestDeveloper? trusting,
    bool checkSigner = false,
    String expectedSigner = '',
  }) =>
      testLicenseService(
        db: (db ?? database).db,
        keys: store ?? keys,
        platform: on ?? phone,
        clock: clock,
        developer: trusting ?? developer,
        checkSigner: checkSigner,
        expectedSigner: expectedSigner,
      );

  Future<String> licenseFor(
    FakeLicensePlatform device, {
    int id = 1,
    Iterable<Feature>? features,
    DateTime? issuedAt,
    DateTime? expiresAt,
    String shop = 'Al Noor Market',
    TestDeveloper? by,
  }) =>
      (by ?? developer).license(
        device: device.device,
        id: id,
        features: features,
        issuedAt: issuedAt ?? clock.now,
        expiresAt: expiresAt,
        shop: shop,
      );

  /// The same code with one bit of its PAYLOAD changed, signature as it was.
  String withChangedPayload(String code, int byte) {
    final parsed = SignedCode.parse(code)!;
    final payload = Uint8List.fromList(parsed.payload)..[byte] ^= 0x01;
    return SignedCode(payload: payload, signature: parsed.signature).text;
  }

  Future<Matcher> refuses(LicensedAction action) async =>
      throwsA(isA<LicenseRequiredException>()
          .having((e) => e.action, 'action', action));

  group('activation', () {
    test('a valid code activates: licensed, stored twice, shop name, audit',
        () async {
      final licensing = service();
      expect((await licensing.start()).mode, LicenseMode.trial);
      expect(licensing.requestCode, phone.requestCode);

      final expires = t0.add(const Duration(days: 365));
      final code = await licenseFor(
        phone,
        id: 41,
        features: [Feature.debt, Feature.barcode],
        expiresAt: expires,
        shop: 'بقالة النور',
      );
      final result = await licensing.activate(code);
      expect(result.ok, isTrue, reason: '${result.error}');
      expect(result.license!.licenseId, 41);

      final status = licensing.status;
      expect(status.mode, LicenseMode.licensed);
      expect(status.canSell, isTrue);
      expect(status.canPrint, isTrue);
      expect(status.shopName, 'بقالة النور');
      expect(status.license!.expiresAt, expires);
      // "debt" brought customers with it.
      expect(
        status.featureMask,
        FeatureGate.maskOf([Feature.debt, Feature.customers, Feature.barcode]),
      );

      // Stored in the Keystore AND in the settings table.
      final plain = SignedCode.parse(code)!.text;
      final settings = SettingsRepository(database.db);
      expect(await settings.getStringOrNull(SettingsKeys.licenseCode), plain);
      expect(
        (jsonDecode(keys.values[LicenseStore.keyName]!) as Map)['code'],
        plain,
      );
      // The shop name every paper carries is the license's.
      expect(await settings.getString(SettingsKeys.shopName), 'بقالة النور');
      // And the activation is in the audit log.
      final log = await AuditRepository(database.db).list();
      expect(log.single.action, 'LICENSE_ACTIVATE');
      expect(log.single.details['shop'], 'بقالة النور');

      // VERIFIED ON EVERY APP START: a new service reads it back.
      final next = service();
      final again = await next.start();
      expect(again.mode, LicenseMode.licensed);
      expect(again.license!.licenseId, 41);
      await next.ensureCanSell();
      await next.ensureCanPrint();
      await next.ensureCanRecordDebt();
    });

    test('the code is read however it is pasted', () async {
      final licensing = service();
      await licensing.start();
      final code = SignedCode.parse(await licenseFor(phone))!.text;
      final messy = StringBuffer();
      for (var i = 0; i < code.length; i++) {
        messy.write(code[i].toLowerCase());
        if (i % 7 == 6) messy.write(i % 2 == 0 ? ' - ' : '\n');
      }
      expect((await licensing.activate('  $messy \r\n')).ok, isTrue);
      expect(licensing.status.isLicensed, isTrue);
    });

    test("another device's code fails", () async {
      final other = FakeLicensePlatform(androidId: 'ffff0000eeee1111');
      expect(other.requestCode, isNot(phone.requestCode));
      final licensing = service();
      await licensing.start();

      final result = await licensing.activate(await licenseFor(other));
      expect(result.ok, isFalse);
      expect(result.error, ActivationError.wrongDevice);
      expect(licensing.status.mode, LicenseMode.trial, reason: 'unchanged');
      expect(
        await SettingsRepository(database.db)
            .getStringOrNull(SettingsKeys.licenseCode),
        isNull,
        reason: 'a refused code is not stored',
      );
      // The same APK under another package name is another device too.
      final renamed = FakeLicensePlatform(packageName: 'com.pirate.souqi');
      expect(renamed.requestCode, isNot(phone.requestCode));
      expect(
        (await licensing.activate(await licenseFor(renamed))).error,
        ActivationError.wrongDevice,
      );
    });

    test('a tampered payload fails', () async {
      final licensing = service();
      await licensing.start();
      final code = await licenseFor(
        phone,
        features: [Feature.barcode],
        expiresAt: t0.add(const Duration(days: 30)),
      );
      // More features, a later expiry, another shop name: each one bit.
      for (final byte in [16, 19, 24, 27, 30]) {
        final result = await licensing.activate(withChangedPayload(code, byte));
        expect(result.error, ActivationError.badSignature, reason: 'byte $byte');
      }
      // The device bytes rewritten to this phone on a stranger's license.
      final other = FakeLicensePlatform(androidId: 'ffff0000eeee1111');
      final foreign = SignedCode.parse(await licenseFor(other))!;
      final rebound = Uint8List.fromList(foreign.payload)
        ..setRange(2, 12, phone.device);
      expect(
        (await licensing.activate(
          SignedCode(payload: rebound, signature: foreign.signature).text,
        ))
            .error,
        ActivationError.badSignature,
      );
      // A changed signature.
      final parsed = SignedCode.parse(code)!;
      final signature = Uint8List.fromList(parsed.signature)..[5] ^= 0x80;
      expect(
        (await licensing.activate(
          SignedCode(payload: parsed.payload, signature: signature).text,
        ))
            .error,
        ActivationError.badSignature,
      );
      // The untouched code is fine.
      expect((await licensing.activate(code)).ok, isTrue);
    });

    test('a code signed by anyone but the developer fails', () async {
      final stranger = await TestDeveloper.create();
      final licensing = service();
      await licensing.start();
      final result =
          await licensing.activate(await licenseFor(phone, by: stranger));
      expect(result.error, ActivationError.badSignature);
      expect(licensing.status.isLicensed, isFalse);
    });

    test('an expired code fails, and a license that runs out stops selling',
        () async {
      final licensing = service();
      await licensing.start();
      final old = await licenseFor(
        phone,
        issuedAt: t0.subtract(const Duration(days: 400)),
        expiresAt: t0.subtract(const Duration(days: 35)),
      );
      expect((await licensing.activate(old)).error, ActivationError.expired);
      expect(licensing.status.mode, LicenseMode.trial);

      final expires = t0.add(const Duration(days: 10));
      expect(
        (await licensing.activate(await licenseFor(phone, expiresAt: expires)))
            .ok,
        isTrue,
      );
      clock.now = expires.subtract(const Duration(minutes: 1));
      await licensing.ensureCanSell();

      clock.now = expires.add(const Duration(minutes: 1));
      await expectLater(
        licensing.ensureCanSell(),
        await refuses(LicensedAction.sell),
      );
      await expectLater(
        licensing.ensureCanPrint(),
        await refuses(LicensedAction.print),
      );
      await expectLater(
        licensing.ensureCanRecordDebt(),
        await refuses(LicensedAction.recordDebt),
      );
      expect(licensing.status.mode, LicenseMode.unlicensed);
      expect(licensing.status.reason, UnlicensedReason.expired);
      // The next start says the same; the shop name stays known.
      final next = await service().start();
      expect(next.reason, UnlicensedReason.expired);
      expect(next.shopName, 'Al Noor Market');
    });

    test('what is not an activation code is refused with its reason',
        () async {
      final licensing = service();
      await licensing.start();
      expect(
        (await licensing.activate('hello')).error,
        ActivationError.malformed,
      );
      expect(
        (await licensing.activate(phone.requestCode)).error,
        ActivationError.malformed,
      );
      final whole = SignedCode.parse(await licenseFor(phone))!.text;
      expect(
        (await licensing.activate(whole.substring(0, whole.length - 8))).error,
        isIn([ActivationError.malformed, ActivationError.badSignature]),
      );
      final reset = await developer.pinReset(device: phone.device, issuedAt: t0);
      expect(
        (await licensing.activate(reset)).error,
        ActivationError.pinResetCode,
      );
    });

    test('without a public key in the app no code is accepted', () async {
      for (final key in ['', '00' * 32, 'ff' * 32, 'abcd']) {
        final licensing = LicenseService(
          db: database.db,
          keys: InMemoryKeyStore(),
          platform: phone,
          clock: clock.call,
          publicKeyHex: key,
          checkSigner: false,
        );
        await licensing.start();
        expect(licensing.configured, isFalse, reason: key);
        expect(
          (await licensing.activate(await licenseFor(phone))).error,
          ActivationError.notConfigured,
          reason: key,
        );
        // A forged "signature" of zeros is not accepted either.
        final forged = SignedCode(
          payload: SignedCode.parse(await licenseFor(phone))!.payload,
          signature: Uint8List(64),
        );
        expect((await licensing.activate(forged.text)).ok, isFalse);
      }
    });

    test('a newer license replaces an older one, not the other way round',
        () async {
      final licensing = service();
      await licensing.start();
      final first = await licenseFor(
        phone,
        id: 1,
        features: [Feature.barcode],
        issuedAt: t0,
      );
      clock.advance(const Duration(days: 30));
      final second = await licenseFor(phone, id: 2, issuedAt: clock.now);

      expect((await licensing.activate(second)).ok, isTrue);
      expect(licensing.status.license!.licenseId, 2);
      expect(
        (await licensing.activate(first)).error,
        ActivationError.olderThanCurrent,
      );
      expect(licensing.status.license!.licenseId, 2);
    });

    test('the license survives the loss of either copy', () async {
      final licensing = service();
      await licensing.start();
      await licensing.activate(await licenseFor(phone));

      // The Keystore lost its entries (an OS update, a new lock screen).
      keys.values.clear();
      final afterKeystore = service();
      expect((await afterKeystore.start()).isLicensed, isTrue);
      expect(keys.values[LicenseStore.keyName], isNotNull,
          reason: 'written back');

      // The settings row is gone (an older database put back).
      await database.db.delete(
        'settings',
        where: 'key IN (?, ?)',
        whereArgs: [SettingsKeys.licenseCode, SettingsKeys.licenseState],
      );
      final afterDatabase = service();
      expect((await afterDatabase.start()).isLicensed, isTrue);
      expect(
        await SettingsRepository(database.db)
            .getStringOrNull(SettingsKeys.licenseCode),
        isNotNull,
        reason: 'written back',
      );
    });

    test('data moved to another phone is not licensed there', () async {
      final licensing = service();
      await licensing.start();
      await licensing.activate(await licenseFor(phone));

      // The same database (with its copy of the code), another device,
      // an empty Keystore — a phone-to-phone transfer, a cloned image.
      final newPhone = FakeLicensePlatform(androidId: '1234567812345678');
      final moved = service(on: newPhone, store: InMemoryKeyStore());
      final status = await moved.start();
      expect(status.isLicensed, isFalse);
      expect(status.storedCodeForOtherDevice, isTrue);
      expect(moved.requestCode, newPhone.requestCode);

      clock.advance(const Duration(days: 8));
      final later = await moved.refresh();
      expect(later.mode, LicenseMode.unlicensed);
      expect(later.reason, UnlicensedReason.wrongDevice);
      await expectLater(
        moved.ensureCanSell(),
        await refuses(LicensedAction.sell),
      );
      // Its own code makes it whole again.
      expect((await moved.activate(await licenseFor(newPhone, id: 2))).ok,
          isTrue);
      expect(moved.status.isLicensed, isTrue);
    });

    test('a phone that cannot say who it is has no request code and takes '
        'no license', () async {
      phone.broken = true;
      final licensing = service();
      final status = await licensing.start();
      expect(licensing.requestCode, isNull);
      expect(status.mode, LicenseMode.trial, reason: 'the trial still runs');
      phone.broken = false;
      final code = await licenseFor(phone);
      phone.broken = true;
      expect(
        (await licensing.activate(code)).error,
        ActivationError.deviceUnknown,
      );
    });

    test('a phone without an ANDROID_ID gets an id of its own that lasts',
        () async {
      phone.androidId = '';
      final first = service();
      await first.start();
      final request = first.requestCode;
      expect(request, isNotNull);
      expect(keys.values[LicenseStore.installIdName], isNotNull);
      final second = service();
      await second.start();
      expect(second.requestCode, request);
    });
  });

  group('the trial', () {
    test('by days: seven, then selling and printing stop', () async {
      final licensing = service();
      final first = await licensing.start();
      expect(first.mode, LicenseMode.trial);
      expect(first.featureMask, allLicenseFeatures, reason: 'all features on');
      expect(first.trialEndsAt, t0.add(const Duration(days: 7)));
      expect(first.trialInvoicesLeft, 30);

      clock.now = t0.add(const Duration(days: 6, hours: 23));
      await licensing.ensureCanSell();
      await licensing.ensureCanPrint();
      await licensing.ensureCanRecordDebt();
      expect(licensing.status.trialDaysLeft(licensing.now), 1);

      clock.now = t0.add(const Duration(days: 7, minutes: 1));
      await expectLater(
        licensing.ensureCanSell(),
        await refuses(LicensedAction.sell),
      );
      await expectLater(
        licensing.ensureCanPrint(),
        await refuses(LicensedAction.print),
      );
      await expectLater(
        licensing.ensureCanRecordDebt(),
        await refuses(LicensedAction.recordDebt),
      );
      expect(licensing.status.reason, UnlicensedReason.trialDaysOver);
      // What the shop made stays readable: nothing is hidden.
      expect(licensing.status.featureMask, allLicenseFeatures);
    });

    test('by invoices: thirty, whichever comes first', () async {
      final licensing = service();
      await licensing.start();
      await setInvoiceCounter(database.db, 29);
      await licensing.ensureCanSell();
      expect(licensing.status.trialInvoicesLeft, 1);

      await setInvoiceCounter(database.db, 30);
      await licensing.saleSaved();
      expect(licensing.status.mode, LicenseMode.unlicensed);
      expect(licensing.status.reason, UnlicensedReason.trialInvoicesOver);
      await expectLater(
        licensing.ensureCanSell(),
        await refuses(LicensedAction.sell),
      );
      // The thirtieth invoice can still be handed to its customer.
      await licensing.ensureCanPrint();
      // Until the seven days are over too.
      clock.advance(const Duration(days: 8));
      await expectLater(
        licensing.ensureCanPrint(),
        await refuses(LicensedAction.print),
      );
    });

    test('deleting invoices does not give the trial back', () async {
      final licensing = service();
      await licensing.start();
      await setInvoiceCounter(database.db, 30);
      // The archive is emptied; the counter of invoices ever made is not.
      await database.db.delete('invoices');
      expect((await licensing.refresh()).reason,
          UnlicensedReason.trialInvoicesOver);
    });

    test('a shop that already had invoices gets thirty more', () async {
      await setInvoiceCounter(database.db, 500);
      final licensing = service();
      expect((await licensing.start()).trialInvoicesLeft, 30);
      await setInvoiceCounter(database.db, 529);
      expect((await licensing.refresh()).trialInvoicesLeft, 1);
      await setInvoiceCounter(database.db, 530);
      expect((await licensing.refresh()).isUnlicensed, isTrue);
    });

    test('closing the app, clearing the Keystore or putting an older '
        'database back does not start the trial again', () async {
      await service().start();
      clock.advance(const Duration(days: 5));

      final nextStart = await service().start();
      expect(nextStart.trialEndsAt, t0.add(const Duration(days: 7)));

      keys.values.clear();
      expect((await service().start()).trialEndsAt,
          t0.add(const Duration(days: 7)));

      await database.db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [SettingsKeys.licenseState],
      );
      expect((await service().start()).trialEndsAt,
          t0.add(const Duration(days: 7)));

      clock.advance(const Duration(days: 3));
      expect((await service().start()).reason, UnlicensedReason.trialDaysOver);
    });

    test('a license ends the trial for good', () async {
      final licensing = service();
      await licensing.start();
      await licensing.activate(
        await licenseFor(phone, expiresAt: t0.add(const Duration(days: 2))),
      );
      // Day 3: the license is over, and the 7-day trial is not an answer.
      clock.advance(const Duration(days: 3));
      final status = await licensing.refresh();
      expect(status.mode, LicenseMode.unlicensed);
      expect(status.reason, UnlicensedReason.expired);
    });
  });

  group('the clock', () {
    test('rollback is detected, said, and does not lengthen the trial',
        () async {
      final licensing = service();
      await licensing.start();
      clock.now = t0.add(const Duration(days: 5));
      expect((await licensing.refresh()).clockWentBack, isFalse);

      // The date is set back a month.
      clock.now = t0.subtract(const Duration(days: 25));
      final rolled = await licensing.refresh();
      expect(rolled.clockWentBack, isTrue);
      expect(rolled.mode, LicenseMode.trial);
      // Two days left, as before the rollback — not thirty-two.
      expect(rolled.trialDaysLeft(licensing.now), 2);

      // Three days of use on the wrong date: the trial is over.
      for (var day = 0; day < 3; day++) {
        clock.advance(const Duration(days: 1));
        await licensing.refresh();
      }
      expect(licensing.status.mode, LicenseMode.unlicensed);
      expect(licensing.status.reason, UnlicensedReason.trialDaysOver);
      expect(licensing.status.clockWentBack, isTrue);
    });

    test('rollback does not bring an expired license back', () async {
      final licensing = service();
      await licensing.start();
      final expires = t0.add(const Duration(days: 10));
      final code = await licenseFor(phone, expiresAt: expires);
      await licensing.activate(code);
      clock.now = expires.add(const Duration(days: 1));
      expect((await licensing.refresh()).reason, UnlicensedReason.expired);

      // Back to before the expiry.
      clock.now = t0.add(const Duration(days: 1));
      final status = await licensing.refresh();
      expect(status.mode, LicenseMode.unlicensed);
      expect(status.reason, UnlicensedReason.expired);
      expect(status.clockWentBack, isTrue);
      await expectLater(
        licensing.ensureCanSell(),
        await refuses(LicensedAction.sell),
      );
      // Entering the same code again changes nothing.
      expect((await licensing.activate(code)).error, ActivationError.expired);
      expect(licensing.status.reason, UnlicensedReason.expired);
    });

    test('the latest time seen is kept in the Keystore and in the database',
        () async {
      final licensing = service();
      await licensing.start();
      clock.now = t0.add(const Duration(days: 4));
      await licensing.refresh();
      final mark = clock.now.millisecondsSinceEpoch;

      Map<String, Object?> secure() =>
          (jsonDecode(keys.values[LicenseStore.keyName]!) as Map)
              .cast<String, Object?>();
      Future<Map<String, Object?>> stored() async => (jsonDecode(
            (await SettingsRepository(database.db)
                .getStringOrNull(SettingsKeys.licenseState))!,
          ) as Map)
              .cast<String, Object?>();
      expect(secure()['latest'], mark);
      expect((await stored())['latest'], mark);

      // The clock goes back, the app is closed, and either copy is wiped:
      // the next start still knows.
      clock.now = t0.subtract(const Duration(days: 60));
      keys.values.clear();
      expect((await service().start()).clockWentBack, isTrue);

      await database.db.delete(
        'settings',
        where: 'key = ?',
        whereArgs: [SettingsKeys.licenseState],
      );
      expect((await service().start()).clockWentBack, isTrue);
    });

    test('a clock corrected by a few hours is not tampering', () async {
      final licensing = service();
      await licensing.start();
      clock.now = t0.add(const Duration(days: 2));
      await licensing.refresh();
      clock.now = t0.add(const Duration(days: 1));
      final status = await licensing.refresh();
      expect(status.clockWentBack, isFalse);
      expect(status.mode, LicenseMode.trial);
    });

    test('a NEW license from the developer lets go of a date that was once '
        'wrong', () async {
      final licensing = service();
      await licensing.start();
      await licensing.activate(
        await licenseFor(phone, expiresAt: t0.add(const Duration(days: 365))),
      );
      // The phone showed 2062 for a day, then the right date again.
      clock.now = DateTime.utc(2062);
      await licensing.refresh();
      clock.now = t0.add(const Duration(days: 20));
      expect((await licensing.refresh()).reason, UnlicensedReason.expired);

      // The same code again: no.
      expect(
        (await licensing.activate(
          await licenseFor(phone,
              issuedAt: t0, expiresAt: t0.add(const Duration(days: 365))),
        ))
            .ok,
        isFalse,
      );
      // A code issued today: yes, and the warning is gone.
      final fresh = await licenseFor(
        phone,
        id: 2,
        issuedAt: clock.now,
        expiresAt: clock.now.add(const Duration(days: 365)),
      );
      expect((await licensing.activate(fresh)).ok, isTrue);
      expect(licensing.status.isLicensed, isTrue);
      expect(licensing.status.clockWentBack, isFalse);
    });
  });

  group("the build's signature", () {
    const developerCert =
        'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:'
        'AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89';
    final developerHex = developerCert.replaceAll(':', '').toLowerCase();

    test('the developer\'s APK sells', () async {
      phone.signers = [developerHex];
      final licensing =
          service(checkSigner: true, expectedSigner: developerCert);
      expect((await licensing.start()).mode, LicenseMode.trial);
      expect((await licensing.activate(await licenseFor(phone))).ok, isTrue);
      await licensing.ensureCanSell();
    });

    test('an APK signed by someone else does not, even with a valid license',
        () async {
      // Licensed while it was the real app.
      phone.signers = [developerHex];
      final real = service(checkSigner: true, expectedSigner: developerCert);
      await real.start();
      await real.activate(await licenseFor(phone));

      // The same data under a re-signed copy.
      phone.signers = ['11' * 32];
      final copy = service(checkSigner: true, expectedSigner: developerCert);
      final status = await copy.start();
      expect(status.mode, LicenseMode.unlicensed);
      expect(status.reason, UnlicensedReason.modifiedApp);
      await expectLater(
        copy.ensureCanSell(),
        await refuses(LicensedAction.sell),
      );
      await expectLater(
        copy.ensureCanPrint(),
        await refuses(LicensedAction.print),
      );
      expect(
        (await copy.activate(await licenseFor(phone, id: 2))).error,
        ActivationError.modifiedApp,
      );
    });

    test('a release build without its fingerprint filled in says so',
        () async {
      phone.signers = [developerHex];
      final unsealed = service(checkSigner: true);
      final status = await unsealed.start();
      expect(status.reason, UnlicensedReason.unsealedBuild);
      expect(status.canSell, isFalse);
      expect(
        (await unsealed.activate(await licenseFor(phone))).error,
        ActivationError.unsealedBuild,
      );
    });

    test('only a debug build skips the check', () async {
      // The tests run in debug mode: the default is "skip".
      final byDefault = LicenseService(
        db: database.db,
        keys: keys,
        platform: phone,
        clock: clock.call,
        publicKeyHex: developer.publicKeyHex,
      );
      expect((await byDefault.start()).mode, LicenseMode.trial);
    });
  });

  group('the developer\'s PIN reset code', () {
    late PinRepository pins;

    setUp(() => pins = PinRepository(SettingsRepository(database.db)));

    test('resets the PIN once, and only once', () async {
      await pins.set('1234');
      final licensing = service();
      await licensing.start();
      final code = await developer.pinReset(device: phone.device, issuedAt: t0);

      expect(await licensing.pinReset.verify(code), isTrue);
      final recovery = await pins.resetWithSignedCode(
        code: code,
        newPin: '5678',
        authority: licensing.pinReset,
      );
      expect(recovery, isNotNull);
      expect(await pins.verify('5678'), isA<PinCorrect>());

      // SINGLE USE: the same code again.
      expect(await licensing.checkPinReset(code), PinResetCheck.alreadyUsed);
      expect(await licensing.pinReset.verify(code), isFalse);
      expect(
        await pins.resetWithSignedCode(
          code: code,
          newPin: '0000',
          authority: licensing.pinReset,
        ),
        isNull,
      );
      expect(await pins.verify('5678'), isA<PinCorrect>(), reason: 'unchanged');

      // Not after the app was closed, and not after either copy was wiped.
      expect(await service().pinReset.verify(code), isFalse);
      keys.values.clear();
      expect(await service().pinReset.verify(code), isFalse);
    });

    test('lives 48 hours', () async {
      final licensing = service();
      await licensing.start();
      final code = await developer.pinReset(device: phone.device, issuedAt: t0);

      clock.now = t0.add(const Duration(hours: 47, minutes: 59));
      expect(await licensing.checkPinReset(code), PinResetCheck.ok);
      clock.now = t0.add(const Duration(hours: 48, minutes: 1));
      expect(await licensing.checkPinReset(code), PinResetCheck.expired);
      expect(await licensing.pinReset.verify(code), isFalse);

      // Setting the date back does not bring it back.
      clock.now = t0.subtract(const Duration(days: 10));
      expect(await licensing.checkPinReset(code), PinResetCheck.expired);
    });

    test('is bound to the device and to the developer', () async {
      final licensing = service();
      await licensing.start();
      final other = FakeLicensePlatform(androidId: 'ffff0000eeee1111');
      expect(
        await licensing.checkPinReset(
          await developer.pinReset(device: other.device, issuedAt: t0),
        ),
        PinResetCheck.wrongDevice,
      );
      final stranger = await TestDeveloper.create();
      expect(
        await licensing.checkPinReset(
          await stranger.pinReset(device: phone.device, issuedAt: t0),
        ),
        PinResetCheck.badSignature,
      );
      // A changed payload (a later expiry).
      final code = await developer.pinReset(device: phone.device, issuedAt: t0);
      expect(
        await licensing.checkPinReset(withChangedPayload(code, 22)),
        PinResetCheck.badSignature,
      );
      // An activation code is not a reset code, nor is a recovery code.
      expect(
        await licensing.checkPinReset(await licenseFor(phone)),
        PinResetCheck.malformed,
      );
      expect(await licensing.pinReset.verify('7K3M-9QXA-2B4D'), isFalse);
      expect(await licensing.pinReset.verify(''), isFalse);
    });

    test('works on a phone that is not licensed: the shop\'s data is its own',
        () async {
      await pins.set('1234');
      final licensing = service();
      await licensing.start();
      clock.advance(const Duration(days: 30));
      expect((await licensing.refresh()).isUnlicensed, isTrue);
      final code =
          await developer.pinReset(device: phone.device, issuedAt: clock.now);
      expect(
        await pins.resetWithSignedCode(
          code: code,
          newPin: '4321',
          authority: licensing.pinReset,
        ),
        isNotNull,
      );
    });

    test('two codes are two uses', () async {
      final licensing = service();
      await licensing.start();
      final first =
          await developer.pinReset(device: phone.device, id: 1, issuedAt: t0);
      final second =
          await developer.pinReset(device: phone.device, id: 2, issuedAt: t0);
      await licensing.consumePinReset(first);
      expect(await licensing.checkPinReset(first), PinResetCheck.alreadyUsed);
      expect(await licensing.checkPinReset(second), PinResetCheck.ok);
    });
  });
}
