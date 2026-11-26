import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// THE RULE FOR EVERYTHING THE PIN OPENS AND THEN LEAVES OPEN — the debts
/// (when "PIN to open debts" is on), the audit log, the "was this card
/// sold?" lookup, a card code shown in full:
///
/// 1. it locks again after a few minutes without a touch (the "lock again
///    after" setting: 1, 5 or 15 minutes, 5 unless changed), and
/// 2. it locks AT ONCE when the app goes to the background — the home
///    button, another app, the screen off.
///
/// A phone left on the counter, or handed over to show a photo, is not an
/// open ledger.
///
/// ONE EXCEPTION to rule 2: when it is THE APP that put something in front
/// of itself — the share sheet, WhatsApp, the dialer, a file or photo
/// picker, a system settings page — the seller has two minutes
/// ([PinAutoLock.externalActionGrace]) to come back without the PIN. Sending
/// a receipt and returning for the next customer must not cost a PIN each
/// time. Rule 1 is NOT suspended meanwhile: with "lock again after" at one
/// minute, a minute and a half in WhatsApp still ends at the lock.
///
/// The pieces:
/// - [PinSessionNotifier]: an unlocked-or-not state with the idle timer —
///   for a session shared by several screens (the debts).
/// - [PinGuardedRoute]: for one screen or dialog opened with the PIN; it
///   closes itself.
/// - [PinBackgroundGuard]: decides what a trip to the background means, and
///   is told of every external action BEFORE it starts (by
///   `ExternalActionBridge`, which wraps the app's one doorway to Android).
/// - [PinSessionObserver]: mounted once above the whole app; hands the
///   app's lifecycle to the guard.
abstract final class PinAutoLock {
  static const List<int> choices = [1, 5, 15];
  static const int defaultMinutes = 5;

  /// How long the app may stay in the background WITHOUT locking, when it
  /// went there behind something it opened itself.
  static const Duration externalActionGrace = Duration(minutes: 2);

  /// An announced external action that has not taken the screen within this
  /// time did not happen (WhatsApp refused the intent without saying so):
  /// the announcement is dropped, so that the home button pressed a minute
  /// later is not mistaken for it.
  static const Duration externalActionStart = Duration(seconds: 10);
}

/// A moment, noted on two clocks (see [PinClock]).
class PinStamp {
  const PinStamp(this.wall, this.running);

  final DateTime wall;
  final Duration running;
}

/// The time, for the locks.
///
/// Why not only timers: Android may freeze an app in the background, and a
/// frozen app's timers do not fire — so "has it been too long?" is also
/// ASKED, against a clock, when the app comes back.
///
/// Why two clocks: the wall clock can be set back in the phone's settings
/// (which would make ten minutes away look like one), and the running clock
/// stands still while the phone sleeps. Too long on EITHER is too long; a
/// wall clock that went backwards is too long.
class PinClock {
  PinClock() : _running = Stopwatch()..start();

  final Stopwatch _running;

  DateTime wallNow() => DateTime.now();

  Duration runningNow() => _running.elapsed;

  PinStamp stamp() => PinStamp(wallNow(), runningNow());

  /// Whether at least [length] has passed since [since].
  bool passed(PinStamp since, Duration length) {
    final wall = wallNow().difference(since.wall);
    return wall.isNegative ||
        wall >= length ||
        runningNow() - since.running >= length;
  }
}

/// Replaced in tests.
final pinClockProvider = Provider<PinClock>((ref) => PinClock());

/// The "lock again after" setting, in minutes: one of
/// [PinAutoLock.choices].
final pinAutoLockMinutesProvider = FutureProvider<int>((ref) async {
  final stored = await ref.watch(settingsRepositoryProvider).getInt(
        SettingsKeys.pinAutoLockMinutes,
        fallback: PinAutoLock.defaultMinutes,
      );
  return PinAutoLock.choices.contains(stored)
      ? stored
      : PinAutoLock.defaultMinutes;
});

/// Goes up by one every time everything the PIN opened must lock NOW (the
/// app went to the background). Sessions and guarded routes listen to it.
class PinLockSignal extends Notifier<int> {
  @override
  int build() => 0;

  void lockNow() => state++;
}

final pinLockSignalProvider =
    NotifierProvider<PinLockSignal, int>(PinLockSignal.new);

/// Locks everything the PIN opened, at once.
void lockAllPinSessions(ProviderContainer container) =>
    container.read(pinLockSignalProvider.notifier).lockNow();

/// Goes up by one every time the app comes back to the front WITHOUT
/// having locked. Sessions and guarded routes then check their idle time
/// against the clock: their timers may not have run while the app was away.
class PinResumeSignal extends Notifier<int> {
  @override
  int build() => 0;

  void cameBack() => state++;
}

final pinResumeSignalProvider =
    NotifierProvider<PinResumeSignal, int>(PinResumeSignal.new);

/// Decides what a trip to the background means for what the PIN opened.
///
/// - The user left (home, another app, the screen off): lock now.
/// - The app sent itself there — [externalActionStarting] was called just
///   before: nothing locks for [PinAutoLock.externalActionGrace]. Back in
///   time: as if the app had never been left (the idle time has kept
///   running). Not back in time: locked.
///
/// HOW AN EXTERNAL ACTION IS RECOGNISED. Android does not say why the app
/// lost the screen, so the app says it first: the announcement, and then the
/// app losing the focus (`inactive`) within
/// [PinAutoLock.externalActionStart]. From there the trip belongs to that
/// action until the app is `resumed` — the share sheet is a panel OVER the
/// app, which only goes to the background once a target is picked, however
/// long that takes. One announcement covers one trip: back in the app, the
/// next press of the home button locks at once.
///
/// What this cannot tell apart: the home button pressed while the share
/// sheet is up looks like a target being picked, and gets the two minutes.
class PinBackgroundGuard {
  PinBackgroundGuard(this._ref);

  final Ref _ref;

  /// Running = an external action was announced and the app still has the
  /// screen.
  Timer? _announced;

  /// The app lost the focus right after an announcement.
  bool _leaving = false;

  /// In the background behind an external action, since then.
  PinStamp? _leftAt;
  Timer? _grace;

  PinClock get _clock => _ref.read(pinClockProvider);

  /// The app is about to open another app or a system screen. Call it
  /// BEFORE the platform call: the app can lose the screen before that call
  /// answers.
  void externalActionStarting() {
    if (_leftAt != null) return;
    _announced?.cancel();
    _announced = Timer(PinAutoLock.externalActionStart, _forget);
  }

  /// The platform said nothing was opened (no WhatsApp, no dialer).
  void externalActionFailed() {
    // Already away: whatever failed, this trip was announced.
    if (_leftAt == null) _forget();
  }

  void lifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        if (_announced != null) {
          _announced!.cancel();
          _announced = null;
          _leaving = true;
        }
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        // `hidden` then `paused`, and `hidden` again on the way back.
        if (_leftAt != null) return;
        if (_leaving || _announced != null) {
          _forget();
          _leftAt = _clock.stamp();
          _grace = Timer(PinAutoLock.externalActionGrace, _graceOver);
        } else {
          _lockNow();
        }
      case AppLifecycleState.detached:
        _forget();
        _endGrace();
        _lockNow();
      case AppLifecycleState.resumed:
        final left = _leftAt;
        _forget();
        _endGrace();
        // The timer above may not have run while the app was away.
        if (left != null &&
            _clock.passed(left, PinAutoLock.externalActionGrace)) {
          _lockNow();
        } else {
          _ref.read(pinResumeSignalProvider.notifier).cameBack();
        }
    }
  }

  void dispose() {
    _forget();
    _endGrace();
  }

  void _forget() {
    _announced?.cancel();
    _announced = null;
    _leaving = false;
  }

  void _endGrace() {
    _grace?.cancel();
    _grace = null;
    _leftAt = null;
  }

  void _graceOver() {
    _endGrace();
    _lockNow();
  }

  void _lockNow() => _ref.read(pinLockSignalProvider.notifier).lockNow();
}

final pinBackgroundGuardProvider = Provider<PinBackgroundGuard>((ref) {
  final guard = PinBackgroundGuard(ref);
  ref.onDispose(guard.dispose);
  return guard;
});

/// A PIN-unlocked session several screens share: `true` while unlocked.
///
/// [unlock] opens it; every [touch] (an interaction with one of its
/// screens) pushes the lock back by the "lock again after" time; with no
/// touch for that long — or on [pinLockSignalProvider] — it is `false`
/// again and the screens that watch it show their lock.
///
/// The timer lives here, not in a widget, so that the session locks on time
/// whichever of its screens happens to be on top — or none of them.
class PinSessionNotifier extends Notifier<bool> {
  Timer? _timer;
  PinStamp? _touchedAt;

  @override
  bool build() {
    ref
      ..onDispose(() => _timer?.cancel())
      ..listen(pinLockSignalProvider, (_, _) => lock())
      // Back from an external action in time: the idle time still counts,
      // and the timer may not have run meanwhile.
      ..listen(pinResumeSignalProvider, (_, _) {
        final touched = _touchedAt;
        if (state &&
            touched != null &&
            ref.read(pinClockProvider).passed(touched, _timeout)) {
          lock();
        }
      });
    return false;
  }

  Duration get _timeout => Duration(
        minutes: ref.read(pinAutoLockMinutesProvider).value ??
            PinAutoLock.defaultMinutes,
      );

  void unlock() {
    state = true;
    touch();
  }

  /// The user did something on one of the session's screens.
  void touch() {
    if (!state) return;
    _timer?.cancel();
    _timer = Timer(_timeout, lock);
    _touchedAt = ref.read(pinClockProvider).stamp();
  }

  void lock() {
    _timer?.cancel();
    _timer = null;
    _touchedAt = null;
    if (state) state = false;
  }
}

/// Mounted once, above every screen (see `SouqiApp`): hands the app's
/// lifecycle to [PinBackgroundGuard], which locks everything the PIN opened
/// when the app goes to the background (unless the app sent itself there).
///
/// "Background" is `hidden` / `paused` / `detached` — another app, the home
/// screen, the screen off. NOT `inactive`: that is also a permission dialog
/// or the notification shade pulled over the app for a moment, and locking
/// on those would make the Bluetooth permission prompt close the screen
/// that asked for it.
class PinSessionObserver extends ConsumerStatefulWidget {
  const PinSessionObserver({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PinSessionObserver> createState() => _PinSessionObserverState();
}

class _PinSessionObserverState extends ConsumerState<PinSessionObserver>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    ref.read(pinBackgroundGuardProvider).lifecycle(state);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Wraps ONE screen or dialog that was opened with the PIN and shows what
/// the PIN protects (the audit log, the card lookup, a card code in full):
/// it closes itself — and whatever was opened on top of it — after the
/// "lock again after" time without a touch, and at once when the app goes
/// to the background (two minutes later when the app sent itself there:
/// see [PinBackgroundGuard]). Getting back in means entering the PIN again,
/// which is how it was opened in the first place.
class PinGuardedRoute extends ConsumerStatefulWidget {
  const PinGuardedRoute({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PinGuardedRoute> createState() => _PinGuardedRouteState();
}

class _PinGuardedRouteState extends ConsumerState<PinGuardedRoute> {
  Timer? _timer;
  PinStamp? _touchedAt;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Duration get _timeout => Duration(
        minutes: ref.read(pinAutoLockMinutesProvider).value ??
            PinAutoLock.defaultMinutes,
      );

  bool _listening = false;

  void _restart() {
    _timer?.cancel();
    // The setting may not have loaded yet when the first thing the PIN
    // opened appears: reading it (and so starting the load) here, and
    // starting the timer over when it arrives, keeps "lock after 1 minute"
    // from being 5 the first time.
    if (!_listening) {
      _listening = true;
      ref.listenManual(pinAutoLockMinutesProvider, (previous, next) {
        if (previous?.value != next.value && mounted) _restart();
      });
    }
    _timer = Timer(_timeout, _close);
    _touchedAt = ref.read(pinClockProvider).stamp();
  }

  /// Back from an external action in time: the idle time still counts, and
  /// the timer may not have run meanwhile.
  void _checkIdle() {
    final touched = _touchedAt;
    if (touched != null &&
        ref.read(pinClockProvider).passed(touched, _timeout)) {
      _close();
    }
  }

  void _close() {
    _timer?.cancel();
    if (_closed || !mounted) return;
    final route = ModalRoute.of(context);
    // Nothing under it to go back to (it is the first screen): stay.
    if (route == null || !route.isActive || route.isFirst) return;
    _closed = true;
    // Whatever was opened on top of it (a date picker, a menu) goes first.
    Navigator.of(context)
      ..popUntil((candidate) => candidate == route)
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(pinLockSignalProvider, (_, _) => _close())
      ..listen(pinResumeSignalProvider, (_, _) => _checkIdle())
      // The setting is read once it has loaded; a touch then uses it.
      ..watch(pinAutoLockMinutesProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _restart(),
      child: widget.child,
    );
  }
}

/// Settings → Security → "Lock again after": 1, 5 or 15 minutes.
class PinAutoLockTile extends ConsumerWidget {
  const PinAutoLockTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final minutes =
        ref.watch(pinAutoLockMinutesProvider).value ?? PinAutoLock.defaultMinutes;
    return ListTile(
      key: const ValueKey('setting-pin-auto-lock'),
      leading: const Icon(Icons.lock_clock_outlined),
      title: Text(l10n.pinAutoLockTitle),
      // The picker sits UNDER the explanation, like the other pickers of
      // this screen: beside it, it squeezes the text on a small phone at a
      // large font.
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.pinAutoLockHint),
          DropdownButton<int>(
            key: const ValueKey('setting-pin-auto-lock-dropdown'),
            value: minutes,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            items: [
              for (final value in PinAutoLock.choices)
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    l10n.minutesCount(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) async {
              if (value == null) return;
              // The screen can be closed while the write runs.
              final container =
                  ProviderScope.containerOf(context, listen: false);
              await container
                  .read(settingsRepositoryProvider)
                  .setInt(SettingsKeys.pinAutoLockMinutes, value);
              container.invalidate(pinAutoLockMinutesProvider);
            },
          ),
        ],
      ),
    );
  }
}
