import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/features/debts/report/report_schedule.dart';

/// The daily report's clock: when it was due, when it is due next, and the
/// catch-up rule — including across midnight and when the phone changes
/// time zone (an instant + the UTC offset of where the phone is).
void main() {
  const damascus = Duration(hours: 3);
  const dubai = Duration(hours: 4);
  const london = Duration.zero;
  const at22 = 22 * 60;

  /// The instant that is [h]:[m] on [day] of November 2026 on the wall
  /// clock of [offset].
  DateTime wall(int day, int h, int m, Duration offset) =>
      DateTime.utc(2026, 11, day, h, m).subtract(offset);

  group('lastScheduledRun / nextScheduledRun', () {
    test('after the time: today; before it: yesterday', () {
      expect(
        lastScheduledRun(wall(26, 22, 30, damascus), at22, utcOffset: damascus),
        wall(26, 22, 0, damascus),
      );
      expect(
        lastScheduledRun(wall(26, 21, 59, damascus), at22, utcOffset: damascus),
        wall(25, 22, 0, damascus),
      );
      // Exactly on time counts as due.
      expect(
        lastScheduledRun(wall(26, 22, 0, damascus), at22, utcOffset: damascus),
        wall(26, 22, 0, damascus),
      );
    });

    test('next is strictly after now, across midnight and month ends', () {
      expect(
        nextScheduledRun(wall(26, 21, 0, damascus), at22, utcOffset: damascus),
        wall(26, 22, 0, damascus),
      );
      expect(
        nextScheduledRun(wall(26, 22, 0, damascus), at22, utcOffset: damascus),
        wall(27, 22, 0, damascus),
      );
      // 30 November 23:00 → 1 December 22:00.
      expect(
        nextScheduledRun(wall(30, 23, 0, damascus), at22, utcOffset: damascus),
        DateTime.utc(2026, 12, 1, 22).subtract(damascus),
      );
      // A time just after midnight.
      expect(
        nextScheduledRun(wall(26, 23, 50, damascus), 15, utcOffset: damascus),
        wall(27, 0, 15, damascus),
      );
    });
  });

  group('needsCatchUp', () {
    test('a report made after the last due time: nothing to catch up', () {
      expect(
        needsCatchUp(
          now: wall(27, 9, 0, damascus),
          minuteOfDay: at22,
          lastSuccessAt: wall(26, 22, 1, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isFalse,
      );
    });

    test('yesterday\'s run was held back: caught up at the next start', () {
      expect(
        needsCatchUp(
          now: wall(27, 9, 0, damascus),
          minuteOfDay: at22,
          lastSuccessAt: wall(25, 22, 5, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isTrue,
      );
    });

    test('across midnight: started at 00:30, last report at 22:01 — fine', () {
      expect(
        needsCatchUp(
          now: wall(27, 0, 30, damascus),
          minuteOfDay: at22,
          lastSuccessAt: wall(26, 22, 1, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isFalse,
      );
      // …and at 00:30 with the last report from the day before yesterday.
      expect(
        needsCatchUp(
          now: wall(27, 0, 30, damascus),
          minuteOfDay: at22,
          lastSuccessAt: wall(25, 22, 1, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isTrue,
      );
    });

    test('a time just after midnight, checked late in the evening', () {
      // Due at 00:15 today; made at 00:16 — nothing owed at 23:00.
      expect(
        needsCatchUp(
          now: wall(26, 23, 0, damascus),
          minuteOfDay: 15,
          lastSuccessAt: wall(26, 0, 16, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isFalse,
      );
      expect(
        needsCatchUp(
          now: wall(26, 23, 0, damascus),
          minuteOfDay: 15,
          lastSuccessAt: wall(25, 0, 16, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isTrue,
      );
    });

    test('never made one: owed once a due time has passed since turning on',
        () {
      expect(
        needsCatchUp(
          now: wall(27, 9, 0, damascus),
          minuteOfDay: at22,
          enabledAt: wall(26, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isTrue,
      );
      // Turned on at 23:00 with the time at 22:00: nothing was owed yet.
      expect(
        needsCatchUp(
          now: wall(26, 23, 30, damascus),
          minuteOfDay: at22,
          enabledAt: wall(26, 23, 0, damascus),
          utcOffset: damascus,
        ),
        isFalse,
      );
    });

    test('a failed attempt is not retried on every start', () {
      final now = wall(27, 9, 0, damascus);
      bool due(Duration since) => needsCatchUp(
            now: now,
            minuteOfDay: at22,
            lastSuccessAt: wall(25, 22, 1, damascus),
            enabledAt: wall(1, 10, 0, damascus),
            lastAttemptAt: now.subtract(since),
            utcOffset: damascus,
          );
      expect(due(const Duration(minutes: 2)), isFalse);
      expect(due(catchUpRetryPause), isTrue);
      expect(due(const Duration(hours: 3)), isTrue);
    });

    test('flying east: the next morning in Dubai is not a missed report', () {
      // Made at 22:01 in Damascus, then the phone is in Dubai (+1 hour):
      // there it is 23:01 that same evening, after its own 22:00.
      final made = wall(26, 22, 1, damascus);
      expect(
        needsCatchUp(
          now: made.add(const Duration(minutes: 30)),
          minuteOfDay: at22,
          lastSuccessAt: made,
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: dubai,
        ),
        isFalse,
      );
      // The next morning in Dubai: still covered.
      expect(
        needsCatchUp(
          now: wall(27, 8, 0, dubai),
          minuteOfDay: at22,
          lastSuccessAt: made,
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: dubai,
        ),
        isFalse,
      );
    });

    test('flying west: 22:00 comes again where the phone is now', () {
      // Made at 22:01 Damascus = 19:01 in London. At 22:30 London time the
      // London 22:00 has passed after that report: a new one is owed.
      final made = wall(26, 22, 1, damascus);
      expect(
        needsCatchUp(
          now: wall(26, 22, 30, london),
          minuteOfDay: at22,
          lastSuccessAt: made,
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: london,
        ),
        isTrue,
      );
      // But at 21:00 London time (before its 22:00) nothing is owed.
      expect(
        needsCatchUp(
          now: wall(26, 21, 0, london),
          minuteOfDay: at22,
          lastSuccessAt: made,
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: london,
        ),
        isFalse,
      );
    });

    test('a clock set back before the last report does not ask for more', () {
      expect(
        needsCatchUp(
          now: wall(20, 23, 0, damascus),
          minuteOfDay: at22,
          lastSuccessAt: wall(26, 22, 1, damascus),
          enabledAt: wall(1, 10, 0, damascus),
          utcOffset: damascus,
        ),
        isFalse,
      );
    });
  });

  group('file names', () {
    test('souqi-debts-YYYY-MM-DD.xlsx / .pdf, from the local date', () {
      final day = DateTime(2026, 3, 7, 22, 1);
      expect(debtReportFiles.nameFor(day, 'xlsx'), 'souqi-debts-2026-03-07.xlsx');
      expect(debtReportFiles.nameFor(day, 'pdf'), 'souqi-debts-2026-03-07.pdf');
      // Running again the same day gives the same names: overwritten.
      expect(
        debtReportFiles.nameFor(DateTime(2026, 3, 7, 8), 'pdf'),
        debtReportFiles.nameFor(day, 'pdf'),
      );
    });

    test('only our own files match', () {
      expect(debtReportFiles.dayKeyOf('souqi-debts-2026-11-26.xlsx'), 20261126);
      expect(debtReportFiles.dayKeyOf('souqi-debts-2026-11-26 (1).pdf'), 20261126);
      for (final other in [
        'souqi-debts-2026-11-26.docx',
        'my-souqi-debts-2026-11-26.xlsx',
        'souqi-debts-2026-13-01.xlsx',
        'souqi-debts-26-11-2026.xlsx',
        'souqi-backup-2026-11-26.xlsx',
        'invoice-12.pdf',
        'notes.txt',
      ]) {
        expect(debtReportFiles.matches(other), isFalse, reason: other);
      }
    });
  });

  group('keep-N rotation', () {
    test('keeps the newest N days that have a report, deletes the rest', () {
      final names = [
        for (var day = 1; day <= 40; day++)
          'souqi-debts-2026-10-${day.toString().padLeft(2, '0')}.xlsx',
      ].where(debtReportFiles.matches).toList();
      // Days 32–40 are no dates: not our files, never touched.
      expect(names, hasLength(31));
      final pdfs = [for (final n in names) n.replaceFirst('.xlsx', '.pdf')];
      final doomed = debtReportFiles.namesToDelete(
        [...names, ...pdfs, 'notes.txt', 'souqi-backup-2026-10-01.bak'],
        keepDays: 30,
      );
      expect(doomed, ['souqi-debts-2026-10-01.pdf', 'souqi-debts-2026-10-01.xlsx']);
    });

    test('counted in days WITH a report: six weeks off keeps all 30', () {
      final names = [
        for (var day = 1; day <= 30; day++)
          'souqi-debts-2026-09-${day.toString().padLeft(2, '0')}.pdf',
        // The phone was off; then one report on 15 November.
        'souqi-debts-2026-11-15.pdf',
      ];
      expect(
        debtReportFiles.namesToDelete(names, keepDays: 30),
        ['souqi-debts-2026-09-01.pdf'],
      );
      expect(debtReportFiles.namesToDelete(names, keepDays: 31), isEmpty);
    });

    test('a day\'s copies rotate with it; keep at least one day', () {
      final names = [
        'souqi-debts-2026-11-24.xlsx',
        'souqi-debts-2026-11-24 (1).xlsx',
        'souqi-debts-2026-11-25.xlsx',
        'souqi-debts-2026-11-26.xlsx',
      ];
      expect(
        debtReportFiles.namesToDelete(names, keepDays: 2),
        ['souqi-debts-2026-11-24 (1).xlsx', 'souqi-debts-2026-11-24.xlsx'],
      );
      expect(
        debtReportFiles.namesToDelete(names, keepDays: 0),
        hasLength(3),
      );
    });

    test('another output\'s files are never touched', () {
      const backups = DatedFilePattern(
        prefix: 'souqi-backup',
        extensions: ['souqibak'],
      );
      final names = [
        'souqi-debts-2026-11-24.pdf',
        'souqi-debts-2026-11-25.pdf',
        'souqi-backup-2026-11-24.souqibak',
        'souqi-backup-2026-11-25.souqibak',
      ];
      expect(
        debtReportFiles.namesToDelete(names, keepDays: 1),
        ['souqi-debts-2026-11-24.pdf'],
      );
      expect(
        backups.namesToDelete(names, keepDays: 1),
        ['souqi-backup-2026-11-24.souqibak'],
      );
    });
  });
}
