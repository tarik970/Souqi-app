import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/constants/settings_keys.dart';
import 'package:souqi/core/security/pin_hash.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/pin_repository.dart';
import 'package:souqi/data/repositories/settings_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('PBKDF2-HMAC-SHA256', () {
    // The published test vectors for password "password", salt "salt".
    test('1 iteration', () {
      expect(
        _hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 1)),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('2 iterations', () {
      expect(
        _hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 2)),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('4096 iterations', () {
      expect(
        _hex(pbkdf2Sha256(utf8.encode('password'), utf8.encode('salt'), 4096)),
        'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a',
      );
    });
  });

  group('a valid PIN', () {
    test('is 4 to 6 digits', () {
      expect(isValidPin('1234'), isTrue);
      expect(isValidPin('123456'), isTrue);
      expect(isValidPin('123'), isFalse);
      expect(isValidPin('1234567'), isFalse);
      expect(isValidPin('12a4'), isFalse);
      expect(isValidPin('12 34'), isFalse);
      expect(isValidPin(''), isFalse);
    });

    test('Arabic-Indic digits are the same PIN', () {
      expect(isValidPin('١٢٣٤'), isTrue);
      final salt = newPinSalt();
      expect(verifyPin('١٢٣٤', salt, hashPin('1234', salt)), isTrue);
    });
  });

  group('the stored hash', () {
    test('verifies the PIN it was made from and no other', () {
      final salt = newPinSalt();
      final stored = hashPin('2580', salt);
      expect(verifyPin('2580', salt, stored), isTrue);
      expect(verifyPin('2581', salt, stored), isFalse);
      expect(verifyPin('02580', salt, stored), isFalse);
    });

    test('does not contain the PIN and records its iterations', () {
      final stored = hashPin('2580', newPinSalt());
      expect(stored.startsWith('pbkdf2-sha256\$$pinIterations\$'), isTrue);
      expect(stored.contains('2580'), isFalse);
    });

    test('the salt makes two shops with one PIN differ', () {
      expect(hashPin('1234', newPinSalt()), isNot(hashPin('1234', newPinSalt())));
    });

    test('garbage in the settings table never verifies', () {
      final salt = newPinSalt();
      expect(verifyPin('1234', salt, ''), isFalse);
      expect(verifyPin('1234', salt, 'plain\$1234'), isFalse);
      expect(verifyPin('1234', salt, 'pbkdf2-sha256\$x\$AAAA'), isFalse);
      expect(verifyPin('1234', salt, 'pbkdf2-sha256\$10\$!!!'), isFalse);
    });
  });

  group('PinRepository', () {
    sqfliteFfiInit();

    late AppDatabase database;
    late SettingsRepository settings;
    late DateTime now;
    late PinRepository pins;

    setUp(() async {
      database = await openTestDb();
      settings = SettingsRepository(database.db);
      now = DateTime(2026, 11, 25, 10);
      pins = PinRepository(settings, clock: () => now);
    });

    tearDown(() async => database.close());

    test('no PIN until one is set; the PIN itself is never stored', () async {
      expect(await pins.isSet(), isFalse);
      await pins.set('2580');
      expect(await pins.isSet(), isTrue);
      final rows = await database.db.query('settings');
      for (final row in rows) {
        expect('${row['value']}'.contains('2580'), isFalse,
            reason: '${row['key']}');
      }
    });

    test('rejects a PIN that is not 4–6 digits', () async {
      expect(() => pins.set('12'), throwsArgumentError);
      expect(() => pins.set('abcd'), throwsArgumentError);
      expect(await pins.isSet(), isFalse);
    });

    test('right and wrong attempts', () async {
      await pins.set('2580');
      expect(await pins.verify('2580'), isA<PinCorrect>());
      final wrong = await pins.verify('0000');
      expect(wrong, isA<PinWrong>());
      expect((wrong as PinWrong).attemptsLeft, 4);
    });

    test('a correct PIN clears the count of wrong ones', () async {
      await pins.set('2580');
      for (var i = 0; i < 3; i++) {
        await pins.verify('0000');
      }
      expect(await pins.verify('2580'), isA<PinCorrect>());
      expect(
        ((await pins.verify('0000')) as PinWrong).attemptsLeft,
        PinRepository.freeAttempts - 1,
      );
    });

    test('five wrong attempts lock it, even for the right PIN', () async {
      await pins.set('2580');
      PinCheck? last;
      for (var i = 0; i < PinRepository.freeAttempts; i++) {
        last = await pins.verify('0000');
      }
      expect(last, isA<PinLocked>());
      expect((last! as PinLocked).until,
          now.add(PinRepository.firstLock));
      expect(await pins.verify('2580'), isA<PinLocked>());

      // The lock is in the database: a new repository (the app restarted)
      // is still locked.
      final restarted = PinRepository(settings, clock: () => now);
      expect(await restarted.verify('2580'), isA<PinLocked>());

      now = now.add(PinRepository.firstLock + const Duration(seconds: 1));
      expect(await pins.verify('2580'), isA<PinCorrect>());
    });

    test('every further wrong attempt doubles the lock, up to a cap',
        () async {
      expect(PinRepository.lockFor(5), const Duration(seconds: 30));
      expect(PinRepository.lockFor(6), const Duration(seconds: 60));
      expect(PinRepository.lockFor(7), const Duration(minutes: 2));
      expect(PinRepository.lockFor(40), PinRepository.maxLock);

      await pins.set('2580');
      for (var i = 0; i < PinRepository.freeAttempts; i++) {
        await pins.verify('0000');
      }
      now = now.add(const Duration(seconds: 31));
      final again = await pins.verify('0000');
      expect((again as PinLocked).until, now.add(const Duration(seconds: 60)));
    });

    test('changing the PIN replaces it; removing it leaves none', () async {
      await pins.set('2580');
      final oldSalt = await settings.getString(SettingsKeys.pinSalt);
      await pins.set('135790');
      expect(await settings.getString(SettingsKeys.pinSalt), isNot(oldSalt));
      expect(await pins.verify('2580'), isA<PinWrong>());
      expect(await pins.verify('135790'), isA<PinCorrect>());

      await pins.clear();
      expect(await pins.isSet(), isFalse);
      expect(await pins.verify('135790'), isA<PinWrong>());
    });
  });
}
