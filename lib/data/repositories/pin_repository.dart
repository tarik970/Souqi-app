import 'dart:convert';

import '../../core/constants/settings_keys.dart';
import '../../core/security/pin_hash.dart';
import 'settings_repository.dart';

/// The answer to one PIN (or recovery code) attempt.
sealed class PinCheck {
  const PinCheck();
}

class PinCorrect extends PinCheck {
  const PinCorrect();
}

class PinWrong extends PinCheck {
  const PinWrong(this.attemptsLeft);

  /// Attempts left before the lock; 0 means this one caused it.
  final int attemptsLeft;
}

/// Too many wrong attempts: nothing is checked until [until].
class PinLocked extends PinCheck {
  const PinLocked(this.until);

  final DateTime until;
}

/// PHASE 5b HOOK — a PIN reset authorised by the developer.
///
/// For the shop that lost both its PIN and its recovery code: the developer
/// issues a "PIN reset" code, signed with the licensing PRIVATE key and bound
/// to this device; the app checks it with the licensing PUBLIC key. Phase 5b
/// implements this interface (signature, device binding, single use, expiry)
/// and overrides `signedPinResetProvider`; until then there is no
/// implementation and the app offers the recovery code only.
///
/// Everything else is already in place: the "Forgot PIN?" dialog hands any
/// text that is not shaped like a recovery code to [verify], and
/// [PinRepository.resetWithSignedCode] sets the new PIN.
abstract class SignedPinReset {
  /// Whether [code] is a valid, unused reset code for THIS device.
  Future<bool> verify(String code);

  /// Called once the new PIN is saved, so the code cannot be used again.
  Future<void> consume(String code);
}

/// The PIN that guards the sensitive actions, and the recovery code that
/// replaces a forgotten one: two salted hashes in the settings table, each
/// with a lock-out that survives closing the app.
class PinRepository {
  PinRepository(this._settings, {DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final SettingsRepository _settings;
  final DateTime Function() _now;

  /// Wrong attempts allowed before the first lock.
  static const int freeAttempts = 5;

  /// The first lock; each further wrong attempt doubles it, up to [maxLock].
  static const Duration firstLock = Duration(seconds: 30);
  static const Duration maxLock = Duration(minutes: 15);

  /// The PIN's own attempt counter and lock.
  static const _pinGuard = (
    attempts: SettingsKeys.pinFailedAttempts,
    lockedUntil: SettingsKeys.pinLockedUntil,
  );

  /// The recovery code's: the same rules, counted separately — a PIN that
  /// is locked out must not also lock the way back in, and guessing at one
  /// must not use up attempts at the other.
  static const _recoveryGuard = (
    attempts: SettingsKeys.pinRecoveryFailedAttempts,
    lockedUntil: SettingsKeys.pinRecoveryLockedUntil,
  );

  Future<bool> isSet() async =>
      (await _settings.getStringOrNull(SettingsKeys.pinHash) ?? '').isNotEmpty;

  /// Whether a recovery code exists for the current PIN. (A PIN chosen
  /// before recovery codes existed has none until it is changed.)
  Future<bool> hasRecoveryCode() async =>
      (await _settings.getStringOrNull(SettingsKeys.pinRecoveryHash) ?? '')
          .isNotEmpty;

  /// Sets or replaces the PIN and returns the NEW RECOVERY CODE that goes
  /// with it — the only time that code exists in the clear; only its hash is
  /// stored. Any earlier recovery code stops working, and every lock-out
  /// counter starts over.
  ///
  /// [pin] must already be valid (see [isValidPin]).
  Future<String> set(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('a PIN is $pinMinLength to $pinMaxLength digits');
    }
    final salt = newPinSalt();
    final recovery = generateRecoveryCode();
    final recoverySalt = newPinSalt();
    await _settings.setMany({
      SettingsKeys.pinSalt: base64Encode(salt),
      SettingsKeys.pinHash: hashPin(pin, salt),
      SettingsKeys.pinFailedAttempts: '0',
      SettingsKeys.pinLockedUntil: '0',
      SettingsKeys.pinRecoverySalt: base64Encode(recoverySalt),
      SettingsKeys.pinRecoveryHash: hashRecoveryCode(recovery, recoverySalt),
      SettingsKeys.pinRecoveryFailedAttempts: '0',
      SettingsKeys.pinRecoveryLockedUntil: '0',
    });
    return recovery;
  }

  /// Removes the PIN and its recovery code.
  Future<void> clear() async {
    await _settings.setMany({
      SettingsKeys.pinSalt: '',
      SettingsKeys.pinHash: '',
      SettingsKeys.pinFailedAttempts: '0',
      SettingsKeys.pinLockedUntil: '0',
      SettingsKeys.pinRecoverySalt: '',
      SettingsKeys.pinRecoveryHash: '',
      SettingsKeys.pinRecoveryFailedAttempts: '0',
      SettingsKeys.pinRecoveryLockedUntil: '0',
      SettingsKeys.pinRecoveryOfferShown: '0',
    });
  }

  /// A PIN is set but nothing could replace it if it were forgotten: it was
  /// chosen before recovery codes existed. The settings show a banner for as
  /// long as this is true.
  Future<bool> lacksRecoveryCode() async =>
      await isSet() && !await hasRecoveryCode();

  /// Whether a PIN prompt should offer "create a recovery code now" — true
  /// exactly ONCE for a PIN without a code: asking marks the offer as made,
  /// so the prompts after it stay as short as they were.
  Future<bool> takeRecoveryOffer() async {
    if (!await lacksRecoveryCode()) return false;
    if (await _settings.getBool(SettingsKeys.pinRecoveryOfferShown)) {
      return false;
    }
    await _settings.setBool(SettingsKeys.pinRecoveryOfferShown, true);
    return true;
  }

  /// Makes a recovery code for the CURRENT PIN, which stays as it is, and
  /// returns it — for a PIN that has none, or to replace one that was lost.
  /// Any earlier recovery code stops working.
  ///
  /// The PIN is checked here (a wrong one counts as an attempt): a recovery
  /// code is a way in, so nobody gets one without the PIN. Returns null when
  /// the PIN is wrong or locked out.
  Future<String?> issueRecoveryCode(String pin) async {
    if (await verify(pin) is! PinCorrect) return null;
    final recovery = generateRecoveryCode();
    final salt = newPinSalt();
    await _settings.setMany({
      SettingsKeys.pinRecoverySalt: base64Encode(salt),
      SettingsKeys.pinRecoveryHash: hashRecoveryCode(recovery, salt),
      SettingsKeys.pinRecoveryFailedAttempts: '0',
      SettingsKeys.pinRecoveryLockedUntil: '0',
    });
    return recovery;
  }

  /// When the PIN's lock ends, or null while attempts are allowed.
  Future<DateTime?> lockedUntil() => _lockedUntil(_pinGuard);

  /// The same for the recovery code.
  Future<DateTime?> recoveryLockedUntil() => _lockedUntil(_recoveryGuard);

  Future<DateTime?> _lockedUntil(
    ({String attempts, String lockedUntil}) guard,
  ) async {
    final until = await _settings.getInt(guard.lockedUntil);
    if (until <= _now().millisecondsSinceEpoch) return null;
    return DateTime.fromMillisecondsSinceEpoch(until);
  }

  /// Checks one PIN attempt and keeps the count of wrong ones.
  Future<PinCheck> verify(String pin) => _attempt(
        _pinGuard,
        hashKey: SettingsKeys.pinHash,
        saltKey: SettingsKeys.pinSalt,
        matches: (salt, stored) => verifyPin(pin, salt, stored),
      );

  /// Checks one recovery-code attempt, with its own count of wrong ones and
  /// the same lock-out as the PIN. A correct code is NOT used up by this: it
  /// stops working when the new PIN is set (see [resetWithRecovery]).
  Future<PinCheck> checkRecovery(String code) => _attempt(
        _recoveryGuard,
        hashKey: SettingsKeys.pinRecoveryHash,
        saltKey: SettingsKeys.pinRecoverySalt,
        matches: (salt, stored) => verifyRecoveryCode(code, salt, stored),
      );

  Future<PinCheck> _attempt(
    ({String attempts, String lockedUntil}) guard, {
    required String hashKey,
    required String saltKey,
    required bool Function(List<int> salt, String stored) matches,
  }) async {
    final locked = await _lockedUntil(guard);
    if (locked != null) return PinLocked(locked);

    final stored = await _settings.getStringOrNull(hashKey) ?? '';
    final saltText = await _settings.getStringOrNull(saltKey) ?? '';
    var ok = false;
    if (stored.isNotEmpty && saltText.isNotEmpty) {
      try {
        ok = matches(base64Decode(saltText), stored);
      } on FormatException {
        ok = false;
      }
    }
    if (ok) {
      await _settings.setMany({guard.attempts: '0', guard.lockedUntil: '0'});
      return const PinCorrect();
    }

    final failed = await _settings.getInt(guard.attempts) + 1;
    if (failed < freeAttempts) {
      await _settings.setInt(guard.attempts, failed);
      return PinWrong(freeAttempts - failed);
    }
    final until = _now().add(lockFor(failed));
    await _settings.setMany({
      guard.attempts: '$failed',
      guard.lockedUntil: '${until.millisecondsSinceEpoch}',
    });
    return PinLocked(until);
  }

  /// "Forgot PIN": replaces the PIN with [newPin] on the strength of the
  /// recovery [code], and returns the NEW recovery code. The old code stops
  /// working in the same write.
  ///
  /// The code is checked again here (and a wrong one counts as an attempt),
  /// so no caller can reset the PIN without it. Returns null when the code
  /// is wrong or the recovery is locked out; the PIN is then unchanged.
  Future<String?> resetWithRecovery({
    required String code,
    required String newPin,
  }) async {
    if (!isValidPin(newPin)) {
      throw ArgumentError('a PIN is $pinMinLength to $pinMaxLength digits');
    }
    if (await checkRecovery(code) is! PinCorrect) return null;
    return set(newPin);
  }

  /// PHASE 5b HOOK: replaces the PIN on the strength of a developer-signed
  /// reset [code], verified by [authority]. Returns the new recovery code,
  /// or null when the authority refuses the code.
  Future<String?> resetWithSignedCode({
    required String code,
    required String newPin,
    required SignedPinReset authority,
  }) async {
    if (!isValidPin(newPin)) {
      throw ArgumentError('a PIN is $pinMinLength to $pinMaxLength digits');
    }
    if (!await authority.verify(code)) return null;
    final recovery = await set(newPin);
    await authority.consume(code);
    return recovery;
  }

  /// 30 s after the fifth wrong attempt, then 1, 2, 4 … minutes, capped.
  static Duration lockFor(int failedAttempts) {
    final extra = failedAttempts - freeAttempts;
    if (extra <= 0) return firstLock;
    if (extra >= 10) return maxLock;
    final lock = firstLock * (1 << extra);
    return lock > maxLock ? maxLock : lock;
  }
}
