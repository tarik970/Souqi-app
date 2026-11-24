import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/date_ranges.dart';
import 'package:souqi/data/repositories/archive_repository.dart';

void main() {
  // Tuesday 24 November 2026, mid-afternoon.
  final now = DateTime(2026, 11, 24, 15, 30);

  group('startOfDay / startOfWeek / startOfMonth', () {
    test('a day starts at local midnight', () {
      expect(startOfDay(now), DateTime(2026, 11, 24));
    });

    test('the week starts on Saturday', () {
      // Tuesday the 24th belongs to the week that began Saturday the 21st.
      expect(startOfWeek(now), DateTime(2026, 11, 21));
      expect(startOfWeek(DateTime(2026, 11, 21, 23)), DateTime(2026, 11, 21));
      // Friday the 20th is the last day of the week before it.
      expect(startOfWeek(DateTime(2026, 11, 20)), DateTime(2026, 11, 14));
    });

    test('a month starts on the 1st', () {
      expect(startOfMonth(now), DateTime(2026, 11));
    });
  });

  group('resolvePeriod', () {
    test('today is one day, ending at tomorrow midnight', () {
      final range = resolvePeriod(ArchivePeriod.today, now: now)!;
      expect(range.from, DateTime(2026, 11, 24));
      expect(range.to, DateTime(2026, 11, 25));
      expect(range.length, const Duration(days: 1));
    });

    test('yesterday ends where today begins', () {
      final yesterday = resolvePeriod(ArchivePeriod.yesterday, now: now)!;
      final today = resolvePeriod(ArchivePeriod.today, now: now)!;
      expect(yesterday.from, DateTime(2026, 11, 23));
      expect(yesterday.to, today.from);
    });

    test('this week runs from Saturday to the end of today, not to Friday',
        () {
      // A week-to-date, so the comparison is against a period that has
      // actually happened.
      final range = resolvePeriod(ArchivePeriod.thisWeek, now: now)!;
      expect(range.from, DateTime(2026, 11, 21));
      expect(range.to, DateTime(2026, 11, 25));
      expect(range.length, const Duration(days: 4));
    });

    test('this month runs from the 1st to the end of today', () {
      final range = resolvePeriod(ArchivePeriod.thisMonth, now: now)!;
      expect(range.from, DateTime(2026, 11));
      expect(range.to, DateTime(2026, 11, 25));
    });

    test('all and custom have no preset bounds', () {
      expect(resolvePeriod(ArchivePeriod.all, now: now), isNull);
      expect(resolvePeriod(ArchivePeriod.custom, now: now), isNull);
    });
  });

  group('previous', () {
    test('is the equal-length range immediately before', () {
      final today = resolvePeriod(ArchivePeriod.today, now: now)!;
      expect(today.previous.from, DateTime(2026, 11, 23));
      expect(today.previous.to, DateTime(2026, 11, 24));
    });

    test('a 4-day week-to-date is compared with the 4 days before it', () {
      final week = resolvePeriod(ArchivePeriod.thisWeek, now: now)!;
      expect(week.previous.length, week.length);
      expect(week.previous.from, DateTime(2026, 11, 17));
      expect(week.previous.to, DateTime(2026, 11, 21));
    });

    test('the two never overlap', () {
      for (final period in [
        ArchivePeriod.today,
        ArchivePeriod.yesterday,
        ArchivePeriod.thisWeek,
        ArchivePeriod.thisMonth,
      ]) {
        final range = resolvePeriod(period, now: now)!;
        expect(range.previous.to, range.from, reason: '$period');
      }
    });
  });

  group('customRange', () {
    test('covers both whole days the user picked', () {
      final range = customRange(DateTime(2026, 11, 10, 9), DateTime(2026, 11, 12, 18));
      expect(range.from, DateTime(2026, 11, 10));
      expect(range.to, DateTime(2026, 11, 13));
      expect(range.length, const Duration(days: 3));
    });

    test('one day picked twice is that one day', () {
      final day = DateTime(2026, 11, 10);
      expect(customRange(day, day).length, const Duration(days: 1));
    });
  });
}
