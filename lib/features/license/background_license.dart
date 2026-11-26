import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../../config/features.dart';
import '../../core/licensing/license_service.dart';
import '../../core/platform/report_platform.dart';
import '../debts/report/daily_job.dart';
import '../debts/report/debt_report_pdf.dart';

/// What the daily job may make tonight, as the license has it.
class DailyJobRights {
  const DailyJobRights({required this.debtReport, required this.backup});

  /// The daily debt report (needs the debt ledger and customers too).
  final bool debtReport;

  /// The daily automatic backup.
  final bool backup;
}

/// THE LICENSE CHECK OF THE BACKGROUND ENGINE.
///
/// The engine WorkManager starts has no `ProviderScope` and never saw the
/// app's own check, so it makes its own: [license] reads the stored code,
/// verifies the signature, the device and the expiry — read-only, the engine
/// writes nothing — and `featureOn` then answers here as it does in the
/// app. A license without the daily report writes no report; one without
/// backups writes no backup.
///
/// A phone that is NOT licensed (the trial is over, the license expired)
/// keeps its features for reading: the report and the backup go on — the
/// shop's data is never locked away.
Future<DailyJobRights> dailyJobRights(LicenseService license) async {
  try {
    final status = await license.start(readOnly: true);
    FeatureGate.apply(status.featureMask);
  } on Object {
    // A check that could not be made must not cost the shop tonight's
    // backup. Selling is what a license guards, and that is not done here.
    FeatureGate.reset();
  }
  return DailyJobRights(
    debtReport: featureOn(Feature.dailyReport),
    backup: featureOn(Feature.backup),
  );
}

/// The daily job as the background engine runs it: the license first, then
/// only what it allows. (`debtReportWorkerMain` in main.dart calls this; the
/// tests call it with fakes.)
Future<DailyJobResult> runDailyJobInBackground({
  required Database db,
  required ReportPlatform platform,
  required LicenseService license,
  required Future<Directory> Function() stagingDir,
  required Future<ReportFonts> Function() loadFonts,
  required Future<DailyOutput?> Function(Map<String, String> stored)
      backupOutput,
  DateTime Function() clock = DateTime.now,
}) async {
  final rights = await dailyJobRights(license);
  return DailyReportJob(
    db: db,
    platform: platform,
    stagingDir: stagingDir,
    loadFonts: loadFonts,
    featureOn: rights.debtReport,
    clock: clock,
    backupOutput: rights.backup ? backupOutput : null,
  ).run(ReportTrigger.scheduled, lockHeld: true);
}
