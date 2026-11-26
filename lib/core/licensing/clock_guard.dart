/// The clock as licensing reads it: one that cannot be turned back.
///
/// A trial of seven days and a license that expires both end by the phone's
/// own clock — which its owner can set to any date. So the latest time ever
/// seen is remembered (the MARK), and:
///
/// - while the phone's clock is at or past the mark, the mark follows it;
/// - while the phone's clock is BEHIND the mark, the mark keeps walking at
///   the pace real time passes (the difference between two looks at the
///   clock, at most 48 hours a look). Setting the date back a year therefore
///   does not buy a year: licensing time continues from where it was.
///
/// A clock that is behind the mark by more than [clockRollbackTolerance] is
/// reported ([ClockReading.wentBack]) and the mark is what trial and expiry
/// are judged by. A smaller step back — a clock corrected by an hour, a
/// phone that was a day ahead — is taken as it is, without a warning.
///
/// Pure: no storage, no real clock. `LicenseService` feeds it and persists
/// the state (in the Keystore AND in the database).
library;

/// How far the clock may step back before it is called tampering.
const Duration clockRollbackTolerance = Duration(hours: 48);

/// What is remembered between two looks at the clock.
class ClockState {
  const ClockState({this.latestMs = 0, this.lastNowMs = 0});

  /// The mark: the latest moment ever seen (epoch milliseconds, UTC).
  /// 0 = nothing seen yet.
  final int latestMs;

  /// What the phone's clock said at the last look.
  final int lastNowMs;

  bool get isEmpty => latestMs == 0;

  /// The one that has seen more.
  static ClockState newer(ClockState a, ClockState b) {
    if (a.latestMs != b.latestMs) return a.latestMs > b.latestMs ? a : b;
    return a.lastNowMs >= b.lastNowMs ? a : b;
  }

  @override
  bool operator ==(Object other) =>
      other is ClockState &&
      other.latestMs == latestMs &&
      other.lastNowMs == lastNowMs;

  @override
  int get hashCode => Object.hash(latestMs, lastNowMs);
}

/// One look at the clock.
class ClockReading {
  const ClockReading({
    required this.state,
    required this.now,
    required this.wentBack,
  });

  /// What to remember for the next look.
  final ClockState state;

  /// The time trial and expiry are judged by.
  final DateTime now;

  /// The phone's clock is more than [clockRollbackTolerance] behind what it
  /// showed before.
  final bool wentBack;
}

/// Looks at the phone's clock ([wallNow]) knowing [state].
ClockReading observeClock(ClockState state, DateTime wallNow) {
  final now = wallNow.toUtc().millisecondsSinceEpoch;
  if (state.isEmpty) {
    return ClockReading(
      state: ClockState(latestMs: now, lastNowMs: now),
      now: wallNow.toUtc(),
      wentBack: false,
    );
  }
  var latest = state.latestMs;
  if (now >= latest) {
    latest = now;
  } else {
    // Behind the mark: the time that passed since the last look still
    // passed. One look never adds more than the tolerance: a shop opens the
    // app every day, so nothing is lost to the cap, and a date typed wrong
    // twice (2010, then 2020) cannot throw the mark years ahead.
    final passed = now - state.lastNowMs;
    if (passed > 0) {
      final cap = clockRollbackTolerance.inMilliseconds;
      latest += passed > cap ? cap : passed;
    }
  }
  final wentBack = latest - now > clockRollbackTolerance.inMilliseconds;
  return ClockReading(
    state: ClockState(latestMs: latest, lastNowMs: now),
    now: wentBack
        ? DateTime.fromMillisecondsSinceEpoch(latest, isUtc: true)
        : wallNow.toUtc(),
    wentBack: wentBack,
  );
}

/// The state after a NEWER license than any before it was activated: the
/// developer signed it at [issuedAt], so it is at least that late — and a
/// mark left far in the future by a clock that was once wrong is let go.
ClockState restartClock(DateTime wallNow, DateTime issuedAt) {
  final now = wallNow.toUtc().millisecondsSinceEpoch;
  final issued = issuedAt.toUtc().millisecondsSinceEpoch;
  return ClockState(latestMs: issued > now ? issued : now, lastNowMs: now);
}
