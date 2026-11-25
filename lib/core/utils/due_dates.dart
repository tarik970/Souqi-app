/// Renewal due dates: when an account is next due and which bucket of the
/// "Due for renewal" list it falls into.
///
/// A due date is a DAY, not a moment. It is stored as the local midnight that
/// starts that day, and everything here compares calendar days in LOCAL time
/// — the shop's day, the same convention as `date_ranges.dart`. So an account
/// due "today" stays "due today" until midnight and is "overdue" one minute
/// later, whatever time of day it was renewed at.
library;

/// Which part of the due list an account belongs to.
enum DueBucket {
  /// The due day has passed.
  overdue,

  /// Due today.
  today,

  /// Due within the "next N days" window (N is a setting).
  soon,

  /// Due later than that: nothing to do yet.
  later,
}

class DueStatus {
  const DueStatus(this.bucket, this.days);

  final DueBucket bucket;

  /// Whole calendar days: how late for [DueBucket.overdue], how long until
  /// the due day for [DueBucket.soon] and [DueBucket.later], 0 for today.
  final int days;

  /// On the "Due for renewal" list (and counted by the home screen badge).
  bool get needsAttention => bucket != DueBucket.later;

  @override
  bool operator ==(Object other) =>
      other is DueStatus && other.bucket == bucket && other.days == days;

  @override
  int get hashCode => Object.hash(bucket, days);

  @override
  String toString() => 'DueStatus(${bucket.name}, $days)';
}

/// Calendar days from [from]'s day to [to]'s day, in local time. Negative
/// when [to] is the earlier day.
///
/// Counted on UTC dates built from the local year/month/day, so a daylight
/// saving change (a 23- or 25-hour day) can never make a day count as zero
/// or as two.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = from.toLocal();
  final b = to.toLocal();
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}

/// The bucket of an account due on [nextDueAt], seen at [now]. Null when the
/// account has no due date.
///
/// [soonDays] is the "due in the next N days" setting: with 3, an account due
/// in 1, 2 or 3 days is [DueBucket.soon].
DueStatus? dueStatusOf(
  DateTime? nextDueAt, {
  required DateTime now,
  required int soonDays,
}) {
  if (nextDueAt == null) return null;
  final days = calendarDaysBetween(now, nextDueAt);
  if (days < 0) return DueStatus(DueBucket.overdue, -days);
  if (days == 0) return const DueStatus(DueBucket.today, 0);
  if (days <= soonDays) return DueStatus(DueBucket.soon, days);
  return DueStatus(DueBucket.later, days);
}

/// The due day of an account renewed at [renewedAt] for [renewalDays] days:
/// the local midnight that starts the day [renewalDays] calendar days later.
///
/// Calendar arithmetic, not `+ 24 h × days`: a renewal at 23:50 is due on the
/// same day as one made that morning.
DateTime nextDueAfter(DateTime renewedAt, int renewalDays) {
  final local = renewedAt.toLocal();
  return DateTime(local.year, local.month, local.day + renewalDays);
}

/// The first moment that is NOT on the due list any more: the midnight that
/// ends the last day of the "next [soonDays] days" window. Everything due
/// before it is overdue, due today or due soon.
DateTime dueWindowEnd(DateTime now, int soonDays) {
  final local = now.toLocal();
  return DateTime(local.year, local.month, local.day + soonDays + 1);
}
