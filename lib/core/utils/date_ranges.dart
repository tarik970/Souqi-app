/// The date ranges the archive and the statistics screen offer.
///
/// Every range is half-open — `from` inclusive, `to` exclusive — and built in
/// LOCAL time, because "today" means the shop's day, not UTC's. The
/// repositories convert to the UTC milliseconds the `created_at` columns hold.
library;

import '../../data/repositories/archive_repository.dart';

/// A resolved period.
class DateRange {
  const DateRange(this.from, this.to);

  /// Inclusive.
  final DateTime from;

  /// Exclusive.
  final DateTime to;

  Duration get length => to.difference(from);

  /// The equal-length period immediately before this one, for the
  /// comparison on the statistics screen. A 7-day week is compared with the
  /// 7 days before it; a custom 3-day range with the 3 days before it.
  DateRange get previous => DateRange(from.subtract(length), from);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);

  @override
  String toString() => 'DateRange($from .. $to)';
}

/// Midnight at the start of [moment]'s day, local time.
DateTime startOfDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);

/// The first day of [moment]'s week. The week starts on SATURDAY: that is
/// the working week in Syria, where the shops using Souqi are.
DateTime startOfWeek(DateTime moment) {
  final day = startOfDay(moment);
  // Monday is 1 … Sunday is 7, so Saturday (6) maps to offset 0.
  final offset = (day.weekday + 1) % 7;
  return DateTime(day.year, day.month, day.day - offset);
}

/// Midnight at the start of the day after [day]. A CALENDAR day, not
/// "+24 hours": on a phone whose time zone still switches to summer time the
/// two differ by an hour twice a year, and a range ending an hour late
/// takes the next day's first invoices with it.
DateTime startOfNextDay(DateTime day) =>
    DateTime(day.year, day.month, day.day + 1);

DateTime startOfMonth(DateTime moment) =>
    DateTime(moment.year, moment.month);

/// Resolves a preset into dates. [ArchivePeriod.all] has no bounds and
/// [ArchivePeriod.custom] keeps whatever the user picked, so both return
/// null and the caller leaves the filter's dates as they are.
DateRange? resolvePeriod(ArchivePeriod period, {DateTime? now}) {
  final moment = now ?? DateTime.now();
  final today = startOfDay(moment);
  return switch (period) {
    ArchivePeriod.all => null,
    ArchivePeriod.custom => null,
    ArchivePeriod.today => DateRange(today, startOfNextDay(today)),
    ArchivePeriod.yesterday =>
      DateRange(DateTime(today.year, today.month, today.day - 1), today),
    // Running weeks and months: up to the end of today, not to a future
    // Friday — a "+12%" against a period that has not happened yet is a lie.
    ArchivePeriod.thisWeek =>
      DateRange(startOfWeek(moment), startOfNextDay(today)),
    ArchivePeriod.thisMonth =>
      DateRange(startOfMonth(moment), startOfNextDay(today)),
  };
}

/// A custom range from two days the user picked in a date picker: from the
/// start of the first day to the end of the last one.
DateRange customRange(DateTime first, DateTime last) => DateRange(
      startOfDay(first),
      startOfNextDay(startOfDay(last)),
    );
