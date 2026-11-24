import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/settings_keys.dart';
import '../../core/providers.dart';
import '../../core/utils/temp_files.dart';
import '../../data/repositories/maintenance_repository.dart';
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

/// Runs the deletes that free space and the VACUUM that reclaims it.
///
/// The state is whether a VACUUM is running right now — the "optimizing…"
/// indicator in [SouqiApp]'s builder watches it, so the seller sees that the
/// app is busy rather than stuck, wherever the delete was started from.
class HousekeepingController extends Notifier<bool> {
  @override
  bool build() => false;

  MaintenanceRepository get _repository =>
      ref.read(maintenanceRepositoryProvider);

  /// Deletes the invoices in a date range (from inclusive, to exclusive) and
  /// returns how many went. VACUUMs afterwards when the delete was big.
  Future<int> deleteRange({DateTime? from, DateTime? to}) async {
    final deleted = await _repository.deleteInvoicesCreatedBetween(
      from: from,
      to: to,
    );
    await _afterDelete(deleted);
    return deleted;
  }

  /// Applies the `auto_delete_days` retention setting ('0' = keep
  /// everything) and returns how many invoices it dropped.
  Future<int> applyRetention({DateTime? now}) async {
    final days = await ref
        .read(settingsRepositoryProvider)
        .getInt(SettingsKeys.autoDeleteDays);
    if (days <= 0) return 0;
    final deleted = await _repository.deleteOlderThan(days, now: now);
    await _afterDelete(deleted);
    return deleted;
  }

  Future<void> _afterDelete(int deleted) async {
    if (deleted == 0) return;
    _invalidateStats();
    if (deleted > vacuumInvoiceThreshold) await vacuum();
  }

  /// Rewrites the database file, with the indicator up while it runs. A
  /// second call during the first one is ignored.
  Future<void> vacuum() async {
    if (state) return;
    _setOptimizing(true);
    try {
      await _repository.vacuum();
    } finally {
      _setOptimizing(false);
      _invalidateStats();
    }
  }

  /// Housekeeping done once per launch, off the first frame: retention
  /// cleanup and the share files left in the cache by earlier sessions.
  ///
  /// Neither one may ever take the app down with it, so each is tried on its
  /// own and a failure is simply left for the next launch.
  Future<void> runOnAppStart() async {
    try {
      await applyRetention();
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

  void _setOptimizing(bool value) {
    // The container can be torn down while a VACUUM runs (the app closing).
    if (ref.mounted) state = value;
  }

  void _invalidateStats() {
    if (ref.mounted) ref.invalidate(storageStatsProvider);
  }
}

final housekeepingProvider =
    NotifierProvider<HousekeepingController, bool>(HousekeepingController.new);

/// Whether [HousekeepingController.runOnAppStart] runs when the app's first
/// frame is up. Overridden to true in `main()`; false everywhere else so a
/// widget test is never surprised by a delete or a file sweep it did not ask
/// for.
final housekeepingOnStartProvider = Provider<bool>((ref) => false);
