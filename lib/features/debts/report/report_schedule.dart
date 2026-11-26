/// When the daily job runs, what its files are called and which of them
/// are old enough to go. No Flutter, no platform: unit-tested directly.
///
/// Times are handled as an INSTANT plus the UTC offset of the place the
/// phone is in, so the tests can move the phone between time zones. The
/// app passes nothing and gets the phone's own zone.
library;

/// Minutes after midnight of the default report time, 22:00.
const int defaultReportMinuteOfDay = 22 * 60;

Duration _offsetOf(DateTime now, Duration? offset) =>
    offset ?? now.toLocal().timeZoneOffset;

/// [now] on the wall clock of [offset]: a UTC DateTime whose fields are the
/// local date and time.
DateTime _wall(DateTime now, Duration offset) => now.toUtc().add(offset);

DateTime _slot(DateTime wall, int dayShift, int minuteOfDay) => DateTime.utc(
      wall.year,
      wall.month,
      wall.day + dayShift,
      minuteOfDay ~/ 60,
      minuteOfDay % 60,
    );

/// The most recent time the job was due at or before [now]: today at
/// [minuteOfDay] once that has passed, otherwise yesterday at it. An instant
/// (UTC).
DateTime lastScheduledRun(
  DateTime now,
  int minuteOfDay, {
  Duration? utcOffset,
}) {
  final offset = _offsetOf(now, utcOffset);
  final wall = _wall(now, offset);
  var slot = _slot(wall, 0, minuteOfDay);
  if (slot.isAfter(wall)) slot = _slot(wall, -1, minuteOfDay);
  return slot.subtract(offset);
}

/// The next time the job is due, strictly after [now]. An instant (UTC).
/// The Android side works out the same thing for WorkManager
/// (`ReportScheduler.nextRunAt`); this one is what the screen shows.
DateTime nextScheduledRun(
  DateTime now,
  int minuteOfDay, {
  Duration? utcOffset,
}) {
  final offset = _offsetOf(now, utcOffset);
  final wall = _wall(now, offset);
  var slot = _slot(wall, 0, minuteOfDay);
  if (!slot.isAfter(wall)) slot = _slot(wall, 1, minuteOfDay);
  return slot.subtract(offset);
}

/// How long the app waits after a failed attempt before the next app start
/// tries again — so a phone that cannot write the report does not try on
/// every single launch.
const Duration catchUpRetryPause = Duration(minutes: 10);

/// THE CATCH-UP RULE: the scheduled run can be held back by battery saving
/// or missed with the phone off. When the last successful report is older
/// than the last time one was due, the next app start makes it.
///
/// - [lastSuccessAt]: the last report that was written (to the chosen folder
///   or, as a fallback, to Downloads).
/// - [enabledAt]: when the feature was turned on. A report due before that
///   was never owed — turning it on at 23:00 with the time at 22:00 does not
///   make one on the spot ("Create report now" is there for that).
/// - [lastAttemptAt]: a failed attempt less than [catchUpRetryPause] ago is
///   not repeated yet.
///
/// Compared as instants, so a change of time zone does not make a report
/// look missing: the due time is worked out on the wall clock where the
/// phone is NOW, and the last success is a moment in time.
bool needsCatchUp({
  required DateTime now,
  required int minuteOfDay,
  DateTime? lastSuccessAt,
  DateTime? enabledAt,
  DateTime? lastAttemptAt,
  Duration? utcOffset,
}) {
  final due = lastScheduledRun(now, minuteOfDay, utcOffset: utcOffset);
  if (enabledAt != null && enabledAt.isAfter(due)) return false;
  if (lastSuccessAt != null && !lastSuccessAt.isBefore(due)) return false;
  if (lastAttemptAt != null) {
    final since = now.difference(lastAttemptAt);
    if (!since.isNegative && since < catchUpRetryPause) return false;
  }
  return true;
}

/// The files of one daily output: `<prefix>-YYYY-MM-DD.<extension>`, one
/// set per day. Running again on the same day writes the same names, so
/// that day's files are overwritten.
///
/// Phase 5's backup is a second pattern (its own prefix and extension) in
/// the same folder, with its own keep-N rule.
class DatedFilePattern {
  const DatedFilePattern({required this.prefix, required this.extensions});

  final String prefix;
  final List<String> extensions;

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// The name of the file of the day [day] is on — its own date fields, so
  /// pass a LOCAL date-time (what `DateTime.now()` is).
  String nameFor(DateTime day, String extension) {
    assert(extensions.contains(extension), extension);
    return '$prefix-${day.year.toString().padLeft(4, '0')}-'
        '${_two(day.month)}-${_two(day.day)}.$extension';
  }

  /// `souqi-debts-2026-11-26.xlsx`, and the copies a file manager or
  /// MediaStore makes of it (`souqi-debts-2026-11-26 (1).xlsx`) — those are
  /// the same day's report and rotate with it.
  RegExp get _pattern => RegExp(
        '^${RegExp.escape(prefix)}-(\\d{4})-(\\d{2})-(\\d{2})'
        '(?: \\(\\d+\\))?\\.(${extensions.map(RegExp.escape).join('|')})\$',
      );

  /// The day a file is of, as `YYYYMMDD`, or null when [name] is not one of
  /// these files. Anything else in the folder is never touched.
  int? dayKeyOf(String name) {
    final match = _pattern.firstMatch(name);
    if (match == null) return null;
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return year * 10000 + month * 100 + day;
  }

  bool matches(String name) => dayKeyOf(name) != null;

  /// KEEP-N: the files to delete so that only the newest [keepDays] DAYS of
  /// reports stay. Counted in days that HAVE a report, not in calendar
  /// days: a phone that was off for six weeks keeps its last 30 reports
  /// instead of losing all of them to the calendar.
  List<String> namesToDelete(Iterable<String> names, {required int keepDays}) {
    final byDay = <int, List<String>>{};
    for (final name in names) {
      final key = dayKeyOf(name);
      if (key != null) (byDay[key] ??= []).add(name);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final keep = keepDays < 1 ? 1 : keepDays;
    return [
      for (final day in days.skip(keep)) ...byDay[day]!..sort(),
    ];
  }
}

/// The daily debt report: `souqi-debts-YYYY-MM-DD.xlsx` / `.pdf`.
const debtReportFiles = DatedFilePattern(
  prefix: 'souqi-debts',
  extensions: ['xlsx', 'pdf'],
);
