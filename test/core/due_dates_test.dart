import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/utils/due_dates.dart';

void main() {
  group('dueStatusOf, around midnight', () {
    // The account is due on 1 December: the local midnight starting it.
    final due = DateTime(2026, 12, 1);

    DueStatus? at(DateTime now, {int soonDays = 3}) =>
        dueStatusOf(due, now: now, soonDays: soonDays);

    test('one minute before the due day starts it is "due tomorrow"', () {
      expect(at(DateTime(2026, 11, 30, 23, 59)),
          const DueStatus(DueBucket.soon, 1));
    });

    test('at midnight it becomes "due today" and stays so all day', () {
      expect(at(DateTime(2026, 12, 1)), const DueStatus(DueBucket.today, 0));
      expect(at(DateTime(2026, 12, 1, 12)),
          const DueStatus(DueBucket.today, 0));
      expect(at(DateTime(2026, 12, 1, 23, 59, 59)),
          const DueStatus(DueBucket.today, 0));
    });

    test('at the next midnight it is overdue by one day', () {
      expect(at(DateTime(2026, 12, 2)),
          const DueStatus(DueBucket.overdue, 1));
      expect(at(DateTime(2026, 12, 2, 23, 59)),
          const DueStatus(DueBucket.overdue, 1));
      expect(at(DateTime(2026, 12, 3, 0, 0, 1)),
          const DueStatus(DueBucket.overdue, 2));
    });

    test('the "next N days" window opens exactly N days before', () {
      // N = 3: due in 3 days is on the list, due in 4 is not yet.
      expect(at(DateTime(2026, 11, 28)), const DueStatus(DueBucket.soon, 3));
      expect(at(DateTime(2026, 11, 28, 23, 59)),
          const DueStatus(DueBucket.soon, 3));
      expect(at(DateTime(2026, 11, 27, 23, 59)),
          const DueStatus(DueBucket.later, 4));
    });

    test('the window follows the setting', () {
      final now = DateTime(2026, 11, 24, 10);
      expect(at(now, soonDays: 3), const DueStatus(DueBucket.later, 7));
      expect(at(now, soonDays: 7), const DueStatus(DueBucket.soon, 7));
      // A window of 0 lists only today and overdue.
      expect(at(DateTime(2026, 11, 30, 9), soonDays: 0),
          const DueStatus(DueBucket.later, 1));
      expect(at(DateTime(2026, 12, 1, 9), soonDays: 0),
          const DueStatus(DueBucket.today, 0));
    });

    test('a due date read back from the database (UTC) is the same day', () {
      final stored = DateTime.fromMillisecondsSinceEpoch(
        due.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );
      expect(
        dueStatusOf(stored, now: DateTime(2026, 12, 1, 8), soonDays: 3),
        const DueStatus(DueBucket.today, 0),
      );
      expect(
        dueStatusOf(stored, now: DateTime(2026, 11, 30, 23, 59), soonDays: 3),
        const DueStatus(DueBucket.soon, 1),
      );
    });

    test('no due date, no status', () {
      expect(dueStatusOf(null, now: DateTime(2026), soonDays: 3), isNull);
    });

    test('only "later" is off the due list', () {
      expect(const DueStatus(DueBucket.overdue, 2).needsAttention, isTrue);
      expect(const DueStatus(DueBucket.today, 0).needsAttention, isTrue);
      expect(const DueStatus(DueBucket.soon, 1).needsAttention, isTrue);
      expect(const DueStatus(DueBucket.later, 9).needsAttention, isFalse);
    });
  });

  group('nextDueAfter', () {
    test('counts calendar days, whatever the time of the renewal', () {
      final morning = nextDueAfter(DateTime(2026, 11, 1, 8), 30);
      final lastMinute = nextDueAfter(DateTime(2026, 11, 1, 23, 50), 30);
      expect(morning, DateTime(2026, 12, 1));
      expect(lastMinute, DateTime(2026, 12, 1));
    });

    test('a renewal just after midnight belongs to the new day', () {
      expect(nextDueAfter(DateTime(2026, 11, 2, 0, 1), 30),
          DateTime(2026, 12, 2));
    });

    test('rolls over months and years', () {
      expect(nextDueAfter(DateTime(2026, 1, 31, 10), 30), DateTime(2026, 3, 2));
      expect(nextDueAfter(DateTime(2026, 12, 15), 30), DateTime(2027, 1, 14));
      // 2028 is a leap year.
      expect(nextDueAfter(DateTime(2028, 2, 1), 30), DateTime(2028, 3, 2));
    });

    test('a UTC moment is taken on its local day', () {
      final renewedAt = DateTime(2026, 11, 1, 23, 50).toUtc();
      expect(nextDueAfter(renewedAt, 7), DateTime(2026, 11, 8));
    });
  });

  group('calendarDaysBetween', () {
    test('is about days, not 24-hour periods', () {
      expect(
        calendarDaysBetween(
          DateTime(2026, 11, 30, 23, 59),
          DateTime(2026, 12, 1, 0, 1),
        ),
        1,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 12, 1, 0, 1), DateTime(2026, 12, 1)),
        0,
      );
      expect(
        calendarDaysBetween(DateTime(2026, 12, 3), DateTime(2026, 12, 1, 18)),
        -2,
      );
    });
  });

  group('dueWindowEnd', () {
    test('is the midnight after the last day of the window', () {
      expect(dueWindowEnd(DateTime(2026, 11, 28, 15), 3), DateTime(2026, 12, 2));
      expect(dueWindowEnd(DateTime(2026, 11, 28, 15), 0),
          DateTime(2026, 11, 29));
    });

    test('agrees with dueStatusOf on what is inside the window', () {
      final now = DateTime(2026, 11, 28, 15);
      final end = dueWindowEnd(now, 3);
      final lastInside = DateTime(2026, 12, 1);
      final firstOutside = DateTime(2026, 12, 2);
      expect(lastInside.isBefore(end), isTrue);
      expect(firstOutside.isBefore(end), isFalse);
      expect(dueStatusOf(lastInside, now: now, soonDays: 3)!.needsAttention,
          isTrue);
      expect(dueStatusOf(firstOutside, now: now, soonDays: 3)!.needsAttention,
          isFalse);
    });
  });
}
