import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/platform/report_platform.dart';
import '../../../core/providers.dart';
import '../../customers/customers_providers.dart';
import 'daily_job.dart';
import 'debt_report_pdf.dart';
import 'report_schedule.dart';
import 'report_settings.dart';

/// The Android side of the report (files, WorkManager, the notification).
/// Tests override it with a fake.
final reportPlatformProvider = Provider<ReportPlatform>(
  (ref) => const MethodChannelReportPlatform(),
);

/// Where the job stages its files: a folder of the app's own, which is
/// never swept by the share-file housekeeping (the copies there are what
/// the notification's "Share" sends, possibly days later).
Future<Directory> appReportStagingDir() async {
  final base = await getApplicationSupportDirectory();
  return Directory(p.join(base.path, stagingDirName));
}

final reportStagingDirProvider = Provider<Future<Directory> Function()>(
  (ref) => appReportStagingDir,
);

/// The bundled Tajawal fonts, for the PDF. Also used by the background
/// engine, which has the same asset bundle.
Future<ReportFonts> loadBundledReportFonts() async => ReportFonts.fromBytes(
      regular: await rootBundle.load(ReportFonts.regularAsset),
      bold: await rootBundle.load(ReportFonts.boldAsset),
    );

final reportFontsProvider = Provider<Future<ReportFonts> Function()>(
  (ref) => loadBundledReportFonts,
);

class DebtReportSettingsNotifier extends AsyncNotifier<DebtReportSettings> {
  @override
  Future<DebtReportSettings> build() async => DebtReportSettings.fromMap(
        await ref.watch(settingsRepositoryProvider).getAll(),
      );

  /// Applies [next] at once and writes it.
  Future<void> save(DebtReportSettings next) async {
    state = AsyncData(next);
    await ref.read(settingsRepositoryProvider).setMany(next.toMap());
  }
}

final debtReportSettingsProvider =
    AsyncNotifierProvider<DebtReportSettingsNotifier, DebtReportSettings>(
  DebtReportSettingsNotifier.new,
);

/// The last run, as Android keeps it.
final debtReportStatusProvider = FutureProvider<DebtReportStatus>((ref) async {
  try {
    return DebtReportStatus.fromJson(
      await ref.watch(reportPlatformProvider).loadStatus(),
    );
  } on Object {
    return const DebtReportStatus();
  }
});

final batteryExemptProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(reportPlatformProvider).batteryOptimizationIgnored();
  } on Object {
    // Unknown: say nothing rather than nag.
    return true;
  }
});

final reportNotificationsAllowedProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(reportPlatformProvider).notificationsAllowed();
  } on Object {
    return true;
  }
});

/// The job as the app runs it (catch-up, "Create report now").
final dailyReportJobProvider = Provider<DailyReportJob>(
  (ref) => DailyReportJob(
    db: ref.watch(databaseProvider).db,
    platform: ref.watch(reportPlatformProvider),
    stagingDir: ref.watch(reportStagingDirProvider),
    loadFonts: ref.watch(reportFontsProvider),
    featureOn: ref.watch(debtFeatureProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// True while the app itself is making a report.
class ReportRunningNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool running) => state = running;
}

final reportRunningProvider =
    NotifierProvider<ReportRunningNotifier, bool>(ReportRunningNotifier.new);

/// Runs the job in the app and refreshes what shows its status.
Future<DailyJobResult> runDebtReport(
  ProviderContainer container,
  ReportTrigger trigger,
) async {
  final running = container.read(reportRunningProvider.notifier);
  running.set(true);
  try {
    return await container.read(dailyReportJobProvider).run(trigger);
  } finally {
    running.set(false);
    container.invalidate(debtReportStatusProvider);
  }
}

/// On every app start: make sure the daily run is planned (WorkManager
/// keeps it across reboots and updates; this re-plans it after a time-zone
/// change or anything else that lost it), then the CATCH-UP RULE — a
/// report that was due and not made is made now.
Future<void> debtReportOnAppStart(ProviderContainer container) async {
  if (!container.read(debtFeatureProvider)) return;
  final settings = await container.read(debtReportSettingsProvider.future);
  final platform = container.read(reportPlatformProvider);
  if (!settings.enabled) {
    // A plan left over from before (a restored database that has it off):
    // the worker would wake every day for nothing.
    try {
      await platform.cancelSchedule();
    } on Object {
      // Nothing planned on this platform.
    }
    return;
  }
  try {
    await platform.schedule(settings.minuteOfDay);
  } on Object {
    // Not on Android (or a test): nothing to plan.
  }
  final status = await container.read(debtReportStatusProvider.future);
  final due = needsCatchUp(
    now: container.read(clockProvider)(),
    minuteOfDay: settings.minuteOfDay,
    lastSuccessAt: status.lastSuccessAt,
    enabledAt: settings.enabledAt,
    lastAttemptAt: status.lastAttemptAt,
  );
  if (!due) return;
  await runDebtReport(container, ReportTrigger.catchUp);
}
