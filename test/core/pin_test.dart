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

  group('the recovery code', () {
    test('is 12 characters of Crockford base32, different every time', () {
      final codes = {for (var i = 0; i < 200; i++) generateRecoveryCode()};
      expect(codes, hasLength(200));
      for (final code in codes) {
        expect(code, hasLength(recoveryCodeLength));
        expect(code.split('').every(crockfordAlphabet.contains), isTrue);
        // No letter that reads as a digit, and no U.
        expect(code.contains(RegExp('[ILOU]')), isFalse);
      }
      expect(crockfordAlphabet, hasLength(32));
    });

    test('is shown in three groups of four', () {
      expect(formatRecoveryCode('7K3M9QXA2B4D'), '7K3M-9QXA-2B4D');
      expect(formatRecoveryCode('7k3m 9qxa-2b4d'), '7K3M-9QXA-2B4D');
    });

    test('is read the way people type it', () {
      const code = '7K3M9QXA2B4D';
      for (final typed in [
        '7K3M-9QXA-2B4D',
        '7k3m9qxa2b4d',
        ' 7K3M 9QXA 2B4D ',
        '٧K٣M-٩QXA-٢B٤D', // Arabic-Indic digits
      ]) {
        expect(normalizeRecoveryCode(typed), code, reason: typed);
      }
      // The letters the alphabet leaves out are the digits they look like.
      expect(normalizeRecoveryCode('O0I1L1'), '001111');
      expect(normalizeRecoveryCode('oil'), '011');
    });

    test('shape: twelve characters of the alphabet, nothing else', () {
      expect(isRecoveryCodeShaped('7K3M-9QXA-2B4D'), isTrue);
      expect(isRecoveryCodeShaped('OOOO-IIII-LLLL'), isTrue,
          reason: 'read as 0000-1111-1111');
      expect(isRecoveryCodeShaped('7K3M-9QXA-2B4'), isFalse);
      expect(isRecoveryCodeShaped('7K3M-9QXA-2B4DD'), isFalse);
      expect(isRecoveryCodeShaped('7K3M-9QXA-2B4U'), isFalse);
      expect(isRecoveryCodeShaped(''), isFalse);
    });

    test('its hash verifies that code and no other, and does not hold it',
        () {
      final salt = newPinSalt();
      final stored = hashRecoveryCode('7K3M9QXA2B4D', salt);
      expect(verifyRecoveryCode('7k3m-9qxa-2b4d', salt, stored), isTrue);
      expect(verifyRecoveryCode('7K3M9QXA2B4E', salt, stored), isFalse);
      expect(verifyRecoveryCode('', salt, stored), isFalse);
      expect(stored.contains('7K3M'), isFalse);
      // Another salt, another hash.
      expect(hashRecoveryCode('7K3M9QXA2B4D', newPinSalt()), isNot(stored));
    });
  });

  group('PinRepository: the recovery code', () {
    sqfliteFfiInit();

    late AppDatabase database;
    late SettingsRepository settings;
    late DateTime now;
    late PinRepository pins;

    setUp(() async {
      database = await openTestDb();
      settings = SettingsRepository(database.db);
      now = DateTime(2026, 11, 26, 10);
      pins = PinRepository(settings, clock: () => now);
    });

    tearDown(() async => database.close());

    /// A code that is certainly not [code]: its last character changed.
    String wrong(String code) =>
        code.substring(0, 11) + (code.endsWith('0') ? '1' : '0');

    test('setting a PIN gives a recovery code and stores only its hash',
        () async {
      expect(await pins.hasRecoveryCode(), isFalse);
      final code = await pins.set('2580');
      expect(code, hasLength(recoveryCodeLength));
      expect(isRecoveryCodeShaped(code), isTrue);
      expect(await pins.hasRecoveryCode(), isTrue);

      for (final row in await database.db.query('settings')) {
        final value = '${row['value']}';
        expect(value.contains(code), isFalse, reason: '${row['key']}');
        expect(value.contains(formatRecoveryCode(code)), isFalse,
            reason: '${row['key']}');
      }
      final stored = await settings.getString(SettingsKeys.pinRecoveryHash);
      expect(stored.startsWith('pbkdf2-sha256\$'), isTrue);
      // Its own salt, not the PIN's.
      expect(await settings.getString(SettingsKeys.pinRecoverySalt),
          isNot(await settings.getString(SettingsKeys.pinSalt)));
    });

    test('the code is accepted however it is typed', () async {
      final code = await pins.set('2580');
      expect(await pins.checkRecovery(formatRecoveryCode(code)),
          isA<PinCorrect>());
      expect(await pins.checkRecovery(' ${code.toLowerCase()} '),
          isA<PinCorrect>());
    });

    test('checking the code does not use it up', () async {
      final code = await pins.set('2580');
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
      // And the PIN is still the PIN.
      expect(await pins.verify('2580'), isA<PinCorrect>());
    });

    test('forgot PIN: the code sets a new PIN and a new code; the old code '
        'stops working', () async {
      final oldCode = await pins.set('2580');
      final newCode =
          await pins.resetWithRecovery(code: oldCode, newPin: '135790');

      expect(newCode, isNotNull);
      expect(newCode, isNot(oldCode));
      expect(await pins.verify('135790'), isA<PinCorrect>());
      expect(await pins.verify('2580'), isA<PinWrong>());

      expect(await pins.checkRecovery(oldCode), isA<PinWrong>());
      expect(await pins.checkRecovery(newCode!), isA<PinCorrect>());
      // The old code cannot be used a second time.
      expect(
        await pins.resetWithRecovery(code: oldCode, newPin: '1111'),
        isNull,
      );
      expect(await pins.verify('135790'), isA<PinCorrect>());
    });

    test('a wrong recovery code changes nothing', () async {
      final code = await pins.set('2580');
      expect(
        await pins.resetWithRecovery(code: wrong(code), newPin: '135790'),
        isNull,
      );
      expect(await pins.verify('2580'), isA<PinCorrect>());
      expect(await pins.verify('135790'), isA<PinWrong>());
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
    });

    test('a new PIN that is not 4–6 digits is refused before anything',
        () async {
      final code = await pins.set('2580');
      expect(
        () => pins.resetWithRecovery(code: code, newPin: '12'),
        throwsArgumentError,
      );
      expect(await pins.verify('2580'), isA<PinCorrect>());
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
    });

    test('changing the PIN rotates the recovery code', () async {
      final first = await pins.set('2580');
      final second = await pins.set('2580'); // even to the same PIN
      expect(second, isNot(first));
      expect(await pins.checkRecovery(first), isA<PinWrong>());
      expect(await pins.checkRecovery(second), isA<PinCorrect>());
    });

    test('wrong recovery attempts count down and then lock, like the PIN',
        () async {
      final code = await pins.set('2580');
      final bad = wrong(code);

      for (var left = PinRepository.freeAttempts - 1; left >= 1; left--) {
        final check = await pins.checkRecovery(bad);
        expect((check as PinWrong).attemptsLeft, left);
      }
      final locked = await pins.checkRecovery(bad);
      expect((locked as PinLocked).until, now.add(PinRepository.firstLock));

      // Locked: even the right code is not looked at — by checkRecovery and
      // by resetWithRecovery alike.
      expect(await pins.checkRecovery(code), isA<PinLocked>());
      expect(
        await pins.resetWithRecovery(code: code, newPin: '135790'),
        isNull,
      );
      expect(await pins.recoveryLockedUntil(), now.add(PinRepository.firstLock));

      // The lock is in the database: restarting the app does not lift it.
      final restarted = PinRepository(settings, clock: () => now);
      expect(await restarted.checkRecovery(code), isA<PinLocked>());

      now = now.add(PinRepository.firstLock + const Duration(seconds: 1));
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
    });

    test('every further wrong recovery attempt doubles the lock', () async {
      final code = await pins.set('2580');
      final bad = wrong(code);
      for (var i = 0; i < PinRepository.freeAttempts; i++) {
        await pins.checkRecovery(bad);
      }
      now = now.add(const Duration(seconds: 31));
      final again = await pins.checkRecovery(bad);
      expect((again as PinLocked).until, now.add(const Duration(seconds: 60)));
      now = now.add(const Duration(seconds: 61));
      final third = await pins.checkRecovery(bad);
      expect((third as PinLocked).until, now.add(const Duration(minutes: 2)));
    });

    test('a correct recovery code clears the count of wrong ones', () async {
      final code = await pins.set('2580');
      for (var i = 0; i < 3; i++) {
        await pins.checkRecovery(wrong(code));
      }
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
      expect(
        ((await pins.checkRecovery(wrong(code))) as PinWrong).attemptsLeft,
        PinRepository.freeAttempts - 1,
      );
    });

    test('the two counters are separate', () async {
      final code = await pins.set('2580');
      // Four wrong PINs: one attempt left on the PIN…
      for (var i = 0; i < 4; i++) {
        await pins.verify('0000');
      }
      // …and still a full set on the recovery code.
      expect(
        ((await pins.checkRecovery(wrong(code))) as PinWrong).attemptsLeft,
        PinRepository.freeAttempts - 1,
      );
      // Locking the recovery code does not lock the PIN.
      for (var i = 0; i < PinRepository.freeAttempts; i++) {
        await pins.checkRecovery(wrong(code));
      }
      expect(await pins.checkRecovery(code), isA<PinLocked>());
      expect(await pins.verify('2580'), isA<PinCorrect>());
    });

    test('a locked-out PIN can still be recovered, which lifts the lock',
        () async {
      final code = await pins.set('2580');
      for (var i = 0; i < PinRepository.freeAttempts; i++) {
        await pins.verify('0000');
      }
      expect(await pins.verify('2580'), isA<PinLocked>());

      final newCode =
          await pins.resetWithRecovery(code: code, newPin: '4321');
      expect(newCode, isNotNull);
      expect(await pins.lockedUntil(), isNull);
      expect(await pins.verify('4321'), isA<PinCorrect>());
    });

    test('removing the PIN removes its recovery code', () async {
      final code = await pins.set('2580');
      await pins.clear();
      expect(await pins.hasRecoveryCode(), isFalse);
      expect(await pins.checkRecovery(code), isA<PinWrong>());
      expect(
        await pins.resetWithRecovery(code: code, newPin: '1111'),
        isNull,
      );
      expect(await pins.isSet(), isFalse);
    });

    test('a PIN chosen before recovery codes existed has none', () async {
      // As phase 4c wrote it: the PIN's hash and salt, nothing else.
      final salt = newPinSalt();
      await settings.setMany({
        SettingsKeys.pinSalt: base64Encode(salt),
        SettingsKeys.pinHash: hashPin('2580', salt),
      });
      expect(await pins.isSet(), isTrue);
      expect(await pins.hasRecoveryCode(), isFalse);
      expect(await pins.checkRecovery('7K3M9QXA2B4D'), isA<PinWrong>());
      // Changing the PIN (which needs the PIN) creates one.
      final code = await pins.set('2580');
      expect(await pins.checkRecovery(code), isA<PinCorrect>());
    });

    group('a PIN without a recovery code (chosen on an older build)', () {
      /// As phase 4c wrote it: the PIN's hash and salt, nothing else.
      Future<void> legacyPin() async {
        final salt = newPinSalt();
        await settings.setMany({
          SettingsKeys.pinSalt: base64Encode(salt),
          SettingsKeys.pinHash: hashPin('2580', salt),
        });
      }

      test('is reported as lacking one; a PIN with a code is not', () async {
        expect(await pins.lacksRecoveryCode(), isFalse, reason: 'no PIN');
        await legacyPin();
        expect(await pins.lacksRecoveryCode(), isTrue);
        await pins.set('2580');
        expect(await pins.lacksRecoveryCode(), isFalse);
      });

      test('the PIN creates a code for itself, and stays the same PIN',
          () async {
        await legacyPin();
        final code = await pins.issueRecoveryCode('2580');
        expect(code, isNotNull);
        expect(isRecoveryCodeShaped(code!), isTrue);
        expect(await pins.lacksRecoveryCode(), isFalse);
        expect(await pins.verify('2580'), isA<PinCorrect>());
        expect(await pins.checkRecovery(code), isA<PinCorrect>());
        // Only its hash is stored.
        for (final row in await database.db.query('settings')) {
          expect('${row['value']}'.contains(code), isFalse);
        }
        // And it does what a recovery code does.
        expect(
          await pins.resetWithRecovery(code: code, newPin: '4321'),
          isNotNull,
        );
        expect(await pins.verify('4321'), isA<PinCorrect>());
      });

      test('nobody gets a code without the PIN', () async {
        await legacyPin();
        expect(await pins.issueRecoveryCode('0000'), isNull);
        expect(await pins.lacksRecoveryCode(), isTrue);
        // The wrong PIN counted as an attempt.
        expect(
          ((await pins.verify('1111')) as PinWrong).attemptsLeft,
          PinRepository.freeAttempts - 2,
        );
        // Locked out: not even the right PIN creates one.
        for (var i = 0; i < PinRepository.freeAttempts; i++) {
          await pins.verify('0000');
        }
        expect(await pins.issueRecoveryCode('2580'), isNull);
        expect(await pins.lacksRecoveryCode(), isTrue);
      });

      test('creating a code again replaces the earlier one', () async {
        final first = await pins.set('2580');
        final second = await pins.issueRecoveryCode('2580');
        expect(second, isNot(first));
        expect(await pins.checkRecovery(first), isA<PinWrong>());
        expect(await pins.checkRecovery(second!), isA<PinCorrect>());
      });

      test('the offer on a PIN prompt is made exactly once', () async {
        expect(await pins.takeRecoveryOffer(), isFalse, reason: 'no PIN');
        await legacyPin();
        expect(await pins.takeRecoveryOffer(), isTrue);
        expect(await pins.takeRecoveryOffer(), isFalse);
        // Also for the app restarted: it is in the database.
        expect(
          await PinRepository(settings, clock: () => now).takeRecoveryOffer(),
          isFalse,
        );
        // The settings banner does not depend on it.
        expect(await pins.lacksRecoveryCode(), isTrue);
      });

      test('a PIN that has a code is never offered one', () async {
        await pins.set('2580');
        expect(await pins.takeRecoveryOffer(), isFalse);
      });

      test('removing the PIN lets a later one be offered again', () async {
        await legacyPin();
        expect(await pins.takeRecoveryOffer(), isTrue);
        await pins.clear();
        await legacyPin();
        expect(await pins.takeRecoveryOffer(), isTrue);
      });
    });

    group('phase 5b hook: a developer-signed reset code', () {
      test('an accepted code sets the new PIN, is used up, and rotates the '
          'recovery code', () async {
        final oldCode = await pins.set('2580');
        final authority = _FakeSignedReset(valid: {'SIGNED-RESET-1'});

        final newCode = await pins.resetWithSignedCode(
          code: 'SIGNED-RESET-1',
          newPin: '135790',
          authority: authority,
        );
        expect(newCode, isNotNull);
        expect(await pins.verify('135790'), isA<PinCorrect>());
        expect(await pins.checkRecovery(oldCode), isA<PinWrong>());
        expect(await pins.checkRecovery(newCode!), isA<PinCorrect>());
        expect(authority.consumed, ['SIGNED-RESET-1']);

        // Single use: the authority no longer accepts it.
        expect(
          await pins.resetWithSignedCode(
            code: 'SIGNED-RESET-1',
            newPin: '1111',
            authority: authority,
          ),
          isNull,
        );
        expect(await pins.verify('135790'), isA<PinCorrect>());
      });

      test('a refused code changes nothing', () async {
        final code = await pins.set('2580');
        final authority = _FakeSignedReset(valid: {});
        expect(
          await pins.resetWithSignedCode(
            code: 'FORGED',
            newPin: '135790',
            authority: authority,
          ),
          isNull,
        );
        expect(authority.consumed, isEmpty);
        expect(await pins.verify('2580'), isA<PinCorrect>());
        expect(await pins.checkRecovery(code), isA<PinCorrect>());
      });
    });
  });
}

/// Stands in for phase 5b's signature check: accepts the codes in [valid],
/// each once.
class _FakeSignedReset implements SignedPinReset {
  _FakeSignedReset({required this.valid});

  final Set<String> valid;
  final List<String> consumed = [];

  @override
  Future<bool> verify(String code) async => valid.contains(code);

  @override
  Future<void> consume(String code) async {
    valid.remove(code);
    consumed.add(code);
  }
}
