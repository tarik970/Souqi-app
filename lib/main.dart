import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/features.dart';
import 'core/constants/settings_keys.dart';
import 'core/platform/report_platform.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'features/debts/report/daily_job.dart';
import 'features/debts/report/report_providers.dart';
import 'features/settings/storage_providers.dart';

Future<void> main() async {
  assert(featureFlagsConsistent,
      'accounts and debt feature flags require customersEnabled');
  WidgetsFlutterBinding.ensureInitialized();

  final appDb = await AppDatabase.open();
  final settings = SettingsRepository(appDb.db);
  final language = await settings.getString(SettingsKeys.appLanguage);
  final setupDone = await settings.getBool(SettingsKeys.setupDone);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(appDb),
        appLocaleProvider
            .overrideWith(() => AppLocaleNotifier(Locale(language))),
        setupDoneProvider.overrideWith(() => SetupDoneNotifier(setupDone)),
        // Only the real app sweeps old invoices and stale share files.
        housekeepingOnStartProvider.overrideWithValue(true),
      ],
      child: const SouqiApp(),
    ),
  );
}

/// THE DAILY DEBT REPORT, run by WorkManager in a Flutter engine of its own
/// with no screen (android/.../DebtReportWorker.kt starts it by this name).
///
/// It builds the report, writes it, rotates the old files, records the
/// status and posts the notification — [DailyReportJob], the same code the
/// app runs for a catch-up or "Create report now" — and then tells the
/// worker it may end. It only READS the database.
@pragma('vm:entry-point')
Future<void> debtReportWorkerMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  const platform = MethodChannelReportPlatform();
  try {
    final appDb = await AppDatabase.open();
    try {
      await DailyReportJob(
        db: appDb.db,
        platform: platform,
        stagingDir: appReportStagingDir,
        loadFonts: loadBundledReportFonts,
        // The same switch as `debtFeatureProvider`, which this engine has
        // no ProviderScope for. PHASE 5b: also check the license here.
        featureOn: debtEnabled && customersEnabled,
      ).run(ReportTrigger.scheduled);
    } finally {
      await appDb.close();
    }
  } on Object {
    // The worker records the failure when no status was written.
  } finally {
    await platform.workerFinished();
  }
}
