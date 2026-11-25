import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../core/utils/date_ranges.dart';
import '../../core/utils/temp_files.dart';
import '../../data/repositories/archive_repository.dart';
import '../../data/repositories/maintenance_repository.dart';
import '../archive/archive_providers.dart';
import '../customers/customers_providers.dart';
import '../invoice/invoice_output.dart';

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return MaintenanceRepository(database.db, filePath: database.path);
});

/// What Settings → About shows about storage.
class StorageStats {
  const StorageStats({required this.invoiceCount, required this.databaseBytes});

  final int invoiceCount;

  /// 0 when there is no file to measure (an in-memory database in tests).
  final int databaseBytes;
}

/// Re-read after any delete or VACUUM, so the figures in About are never the
/// ones from before the cleanup.
final storageStatsProvider = FutureProvider<StorageStats>((ref) async {
  final repository = ref.watch(maintenanceRepositoryProvider);
  return StorageStats(
    invoiceCount: await repository.invoiceCount(),
    databaseBytes: await repository.databaseSizeBytes(),
  );
});

/// Invoices that must be deleted at once before the file is rewritten.
///
/// A VACUUM costs a full copy of the database and the seller waits for it, so
/// it has to buy back real space. Below this many invoices the free pages are
/// a few hundred kilobytes that the next weeks of sales fill in again anyway.
const int vacuumInvoiceThreshold = 1000;

/// What housekeeping is doing right now.
enum HousekeepingPhase { idle, deleting, optimizing }

/// The single piece of state every cleanup shares — and the lock.
///
/// Anything but [HousekeepingPhase.idle] means a job owns the database: a
/// second delete, the retention sweep and a VACUUM all stand down rather
/// than interleave. That is what stopped the archive being cleared twice at
/// once when an impatient tap landed on "Delete" again.
class HousekeepingState {
  const HousekeepingState({
    this.phase = HousekeepingPhase.idle,
    this.done = 0,
    this.total = 0,
  });

  final HousekeepingPhase phase;

  /// Invoices deleted so far, and how many the job set out to delete.
  final int done;
  final int total;

  bool get busy => phase != HousekeepingPhase.idle;
  bool get deleting => phase == HousekeepingPhase.deleting;
  bool get optimizing => phase == HousekeepingPhase.optimizing;

  /// 0..1 for the progress bar, or null while the count is still unknown.
  double? get progress =>
      total <= 0 ? null : (done / total).clamp(0.0, 1.0).toDouble();

  @override
  bool operator ==(Object other) =>
      other is HousekeepingState &&
      other.phase == phase &&
      other.done == done &&
      other.total == total;

  @override
  int get hashCode => Object.hash(phase, done, total);
}

/// How a delete ended.
class DeleteOutcome {
  const DeleteOutcome({
    required this.deleted,
    required this.remaining,
    this.error,
    this.refused = false,
  });

  /// Another cleanup already owned the database; nothing was touched.
  const DeleteOutcome.refused()
      : deleted = 0,
        remaining = 0,
        error = null,
        refused = true;

  final int deleted;

  /// Invoices that still match the criteria. 0 on a clean finish.
  final int remaining;

  final Object? error;
  final bool refused;

  bool get complete => !refused && error == null && remaining == 0;
}

/// Runs the deletes that free space and the VACUUM that reclaims it.
///
/// Every cleanup in the app goes through here, which is what makes the lock
/// in [HousekeepingState] global. Deletes run in chunks so the screen can
/// show real progress and stay responsive; the SQL itself is executed by
/// sqflite on a native background thread, so it never blocks the UI isolate.
class HousekeepingController extends Notifier<HousekeepingState> {
  @override
  HousekeepingState build() => const HousekeepingState();

  MaintenanceRepository get _maintenance =>
      ref.read(maintenanceRepositoryProvider);

  ArchiveRepository get _archive => ref.read(archiveRepositoryProvider);

  /// Deletes every invoice matching [filter] — a date range, or no bounds at
  /// all for the whole archive — in chunks, reporting progress as it goes.
  ///
  /// The criteria are the archive's own, so the number the confirmation
  /// showed is the number that goes; the ids a screen has loaded never come
  /// into it. The loop ends only when nothing matches any more, and a final
  /// count says so, so a big clear can never stop half way in silence.
  Future<DeleteOutcome> deleteMatching(ArchiveFilter filter) async {
    if (state.busy) return const DeleteOutcome.refused();
    // Claimed synchronously, BEFORE the first await: two taps in the same
    // frame cannot both get past the check above.
    state = const HousekeepingState(phase: HousekeepingPhase.deleting);

    var deleted = 0;
    var remaining = 0;
    Object? failure;
    try {
      final total = await _archive.countMatching(filter);
      _publish(done: 0, total: total);
      while (true) {
        final gone = await _archive.deleteMatchingChunk(filter);
        if (gone == 0) break;
        deleted += gone;
        _publish(done: deleted, total: total);
        // Hand the frame back between chunks so the progress bar actually
        // moves and a tap on the barrier is not queued up for minutes.
        await Future<void>.delayed(Duration.zero);
        if (!ref.mounted) break;
      }
      remaining = await _archive.countMatching(filter);
    } on Object catch (error) {
      failure = error;
      // Each chunk was its own transaction, so what is left is consistent;
      // say how much of it there is.
      try {
        remaining = await _archive.countMatching(filter);
      } on Object {
        remaining = -1;
      }
    }

    // The lock is released before the VACUUM, which takes it again as
    // [HousekeepingPhase.optimizing] — a different indicator, and one the
    // seller may walk away from.
    _idle();
    _refresh();
    if (failure == null && deleted > vacuumInvoiceThreshold) {
      await vacuum();
    }
    return DeleteOutcome(
      deleted: deleted,
      remaining: remaining,
      error: failure,
    );
  }

  /// Applies the `auto_delete_days` retention setting ('0' = keep
  /// everything) and returns how many invoices it dropped. Chunked and
  /// locked exactly like a manual delete.
  Future<int> applyRetention({DateTime? now}) async {
    final days = await ref
        .read(settingsRepositoryProvider)
        .getInt(SettingsKeys.autoDeleteDays);
    if (days <= 0) return 0;
    final cutoff = (now ?? DateTime.now()).subtract(Duration(days: days));
    final outcome = await deleteMatching(ArchiveFilter(to: cutoff));
    return outcome.deleted;
  }

  /// [applyRetention], but at most once a calendar day, and it announces
  /// what it dropped — once, at the end.
  ///
  /// Called from [runOnAppStart]. A shop that opens the app twenty times a
  /// day must not pay for twenty sweeps, and the seller gets ONE notice on
  /// the first launch of the day rather than one per launch.
  ///
  /// The day is stamped BEFORE the delete: if the delete fails halfway the
  /// invoices simply stay until tomorrow, which is the safe direction.
  Future<int> applyRetentionDaily({DateTime? now}) async {
    // Checked before the day is stamped: a sweep that never ran because a
    // manual delete held the lock must still be free to run later today.
    if (state.busy) return 0;
    final settings = ref.read(settingsRepositoryProvider);
    if (await settings.getInt(SettingsKeys.autoDeleteDays) <= 0) return 0;
    final moment = now ?? DateTime.now();
    final last = await settings.getInt(SettingsKeys.autoDeleteLastRunAt);
    if (last > 0 &&
        startOfDay(DateTime.fromMillisecondsSinceEpoch(last)) ==
            startOfDay(moment)) {
      return 0;
    }
    await settings.setInt(
      SettingsKeys.autoDeleteLastRunAt,
      moment.millisecondsSinceEpoch,
    );
    final deleted = await applyRetention(now: moment);
    if (deleted > 0 && ref.mounted) {
      ref.read(retentionNoticeProvider.notifier).report(deleted);
    }
    return deleted;
  }

  /// Rewrites the database file, with the indicator up while it runs. Stands
  /// down if another cleanup owns the database.
  Future<void> vacuum() async {
    if (state.busy) return;
    state = const HousekeepingState(phase: HousekeepingPhase.optimizing);
    try {
      await _maintenance.vacuum();
    } finally {
      _idle();
      _refresh();
    }
  }

  /// Housekeeping done once per launch, off the first frame: retention
  /// cleanup and the share files left in the cache by earlier sessions.
  ///
  /// Neither one may ever take the app down with it, so each is tried on its
  /// own and a failure is simply left for the next launch.
  Future<void> runOnAppStart() async {
    try {
      await applyRetentionDaily();
    } on Object {
      // A locked or half-upgraded database: the archive keeps its invoices.
    }
    try {
      await pruneOldFiles(
        await ref.read(outputDirectoryProvider)(),
        maxAge: shareFileMaxAge,
      );
    } on Object {
      // No cache directory on this platform (or in a widget test).
    }
  }

  void _publish({required int done, required int total}) {
    // The container can be torn down mid-job (the app closing).
    if (!ref.mounted) return;
    state = HousekeepingState(
      phase: HousekeepingPhase.deleting,
      done: done,
      total: total,
    );
  }

  void _idle() {
    if (ref.mounted) state = const HousekeepingState();
  }

  /// Everything that counts invoices is now wrong: the archive page, its
  /// summary line and the storage figures in About.
  void _refresh() {
    if (!ref.mounted) return;
    ref
      ..invalidate(storageStatsProvider)
      ..invalidate(archiveListProvider)
      ..invalidate(archiveRangeSummaryProvider)
      // A customer's purchase history and totals are read from the invoices
      // that are still there.
      ..invalidate(customerHistoryProvider)
      ..invalidate(customerTotalsProvider);
  }
}

final housekeepingProvider =
    NotifierProvider<HousekeepingController, HousekeepingState>(
  HousekeepingController.new,
);

/// Whether [HousekeepingController.runOnAppStart] runs when the app's first
/// frame is up. Overridden to true in `main()`; false everywhere else so a
/// widget test is never surprised by a delete or a file sweep it did not ask
/// for.
final housekeepingOnStartProvider = Provider<bool>((ref) => false);

/// How many invoices the last retention sweep deleted, until the notice has
/// been shown.
///
/// Null means "nothing to say". The sweep runs before any screen is up and
/// outlives whatever screen is, so the count waits in a provider instead of
/// being pushed at a widget that may not exist yet.
class RetentionNoticeNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void report(int deleted) => state = deleted;

  /// Called by the notice once the seller has seen (or dismissed) it.
  void clear() => state = null;
}

final retentionNoticeProvider =
    NotifierProvider<RetentionNoticeNotifier, int?>(
  RetentionNoticeNotifier.new,
);

/// The `auto_delete_days` retention setting. 0 is off.
final retentionDaysProvider = FutureProvider<int>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getInt(SettingsKeys.autoDeleteDays),
);
