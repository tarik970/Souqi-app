import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/utils/date_ranges.dart';
import '../../data/repositories/archive_repository.dart';
import '../../data/repositories/audit_repository.dart';
import '../../domain/models/voucher.dart';

/// The period the audit log screen is showing.
class AuditPeriod {
  const AuditPeriod({this.preset = ArchivePeriod.all, this.range});

  final ArchivePeriod preset;

  /// Null = no bounds ("All").
  final DateRange? range;

  @override
  bool operator ==(Object other) =>
      other is AuditPeriod && other.preset == preset && other.range == range;

  @override
  int get hashCode => Object.hash(preset, range);
}

class AuditPeriodNotifier extends Notifier<AuditPeriod> {
  @override
  AuditPeriod build() => const AuditPeriod();

  void setPreset(ArchivePeriod preset, {DateTime? now}) => state = AuditPeriod(
        preset: preset,
        range: resolvePeriod(preset, now: now),
      );

  void setCustomRange(DateTime first, DateTime last) => state = AuditPeriod(
        preset: ArchivePeriod.custom,
        range: customRange(first, last),
      );
}

final auditPeriodProvider =
    NotifierProvider.autoDispose<AuditPeriodNotifier, AuditPeriod>(
  AuditPeriodNotifier.new,
);

/// The rows loaded so far and whether there may be more below them.
class AuditList {
  const AuditList({required this.entries, required this.hasMore});

  final List<AuditEntry> entries;
  final bool hasMore;
}

class AuditLogNotifier extends AsyncNotifier<AuditList> {
  @override
  Future<AuditList> build() async {
    final period = ref.watch(auditPeriodProvider);
    final entries = await ref.watch(auditRepositoryProvider).list(
          from: period.range?.from,
          to: period.range?.to,
        );
    return AuditList(
      entries: entries,
      hasMore: entries.length >= AuditRepository.pageSize,
    );
  }

  /// Appends the next page under the last row shown.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.entries.isEmpty) return;
    final period = ref.read(auditPeriodProvider);
    final more = await ref.read(auditRepositoryProvider).list(
          from: period.range?.from,
          to: period.range?.to,
          beforeId: current.entries.last.id,
        );
    if (!ref.mounted) return;
    state = AsyncData(AuditList(
      entries: [...current.entries, ...more],
      hasMore: more.length >= AuditRepository.pageSize,
    ));
  }
}

final auditLogProvider =
    AsyncNotifierProvider.autoDispose<AuditLogNotifier, AuditList>(
  AuditLogNotifier.new,
);
