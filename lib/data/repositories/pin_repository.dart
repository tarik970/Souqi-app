import 'dart:convert';

import '../../core/constants/settings_keys.dart';
import '../../core/security/pin_hash.dart';
import 'settings_repository.dart';

/// The answer to one PIN attempt.
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

/// The PIN that guards the sensitive actions: a salted hash in the settings
/// table, and a lock-out that survives closing the app.
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

  Future<bool> isSet() async =>
      (await _settings.getStringOrNull(SettingsKeys.pinHash) ?? '').isNotEmpty;

  /// Sets or replaces the PIN. [pin] must already be valid (see
  /// [isValidPin]); the lock-out counters start over.
  Future<void> set(String pin) async {
    if (!isValidPin(pin)) {
      throw ArgumentError('a PIN is $pinMinLength to $pinMaxLength digits');
    }
    final salt = newPinSalt();
    await _settings.setMany({
      SettingsKeys.pinSalt: base64Encode(salt),
      SettingsKeys.pinHash: hashPin(pin, salt),
      SettingsKeys.pinFailedAttempts: '0',
      SettingsKeys.pinLockedUntil: '0',
    });
  }

  Future<void> clear() async {
    await _settings.setMany({
      SettingsKeys.pinSalt: '',
      SettingsKeys.pinHash: '',
      SettingsKeys.pinFailedAttempts: '0',
      SettingsKeys.pinLockedUntil: '0',
    });
  }

  /// When the lock ends, or null while attempts are allowed.
  Future<DateTime?> lockedUntil() async {
    final until = await _settings.getInt(SettingsKeys.pinLockedUntil);
    if (until <= _now().millisecondsSinceEpoch) return null;
    return DateTime.fromMillisecondsSinceEpoch(until);
  }

  /// Checks one attempt and keeps the count of wrong ones.
  Future<PinCheck> verify(String pin) async {
    final locked = await lockedUntil();
    if (locked != null) return PinLocked(locked);

    final stored = await _settings.getStringOrNull(SettingsKeys.pinHash) ?? '';
    final saltText =
        await _settings.getStringOrNull(SettingsKeys.pinSalt) ?? '';
    var ok = false;
    if (stored.isNotEmpty && saltText.isNotEmpty) {
      try {
        ok = verifyPin(pin, base64Decode(saltText), stored);
      } on FormatException {
        ok = false;
      }
    }
    if (ok) {
      await _settings.setMany({
        SettingsKeys.pinFailedAttempts: '0',
        SettingsKeys.pinLockedUntil: '0',
      });
      return const PinCorrect();
    }

    final failed = await _settings.getInt(SettingsKeys.pinFailedAttempts) + 1;
    if (failed < freeAttempts) {
      await _settings.setInt(SettingsKeys.pinFailedAttempts, failed);
      return PinWrong(freeAttempts - failed);
    }
    final until = _now().add(lockFor(failed));
    await _settings.setMany({
      SettingsKeys.pinFailedAttempts: '$failed',
      SettingsKeys.pinLockedUntil: '${until.millisecondsSinceEpoch}',
    });
    return PinLocked(until);
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
