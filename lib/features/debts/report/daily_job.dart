import 'dart:io';
import 'dart:ui' show Locale;

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/constants/settings_keys.dart';
import '../../../core/money/money_format.dart';
import '../../../core/platform/report_platform.dart';
import '../../../data/repositories/debt_report_repository.dart';
import '../../../data/repositories/settings_repository.dart';
import '../../../domain/models/debt_report.dart';
import '../../../l10n/generated/app_localizations.dart';
import 'debt_report_pdf.dart';
import 'debt_report_xlsx.dart';
import 'report_schedule.dart';
import 'report_settings.dart';

/// Why the job ran.
enum ReportTrigger {
  /// WorkManager, around the chosen time.
  scheduled,

  /// The app started and the last scheduled report was missed.
  catchUp,

  /// "Create report now".
  manual,
}

/// A file an output made, staged in the app's own folder before it is
/// copied to the destination. The staged copy is what "Share" hands over.
class StagedFile {
  const StagedFile({
    required this.name,
    required this.path,
    required this.mimeType,
    this.shareable = true,
  });

  final String name;
  final String path;
  final String mimeType;

  /// Offered by the notification's "Share" (the report). False for the
  /// backup: it is written to the folder and its staged copy then removed —
  /// a whole shop is not something to hand over from a notification.
  final bool shareable;
}

/// What every output is given.
class DailyJobContext {
  const DailyJobContext({
    required this.db,
    required this.now,
    required this.stagingDir,
  });

  final Database db;

  /// Local time; the files are named after its date.
  final DateTime now;

  /// The app's own folder ([stagingDirName] under the app's files).
  final Directory stagingDir;
}

/// ONE OUTPUT OF THE DAILY JOB — the extension point.
///
/// The job runs every output, copies all their files into the SAME
/// destination folder (with the same fallback to Downloads), and applies
/// each output's OWN keep-N rule to its OWN files ([files]); files of
/// another output are never touched.
///
/// The encrypted daily backup is the second one (`BackupOutput`,
/// lib/features/backup/auto_backup.dart): `souqi-backup-YYYY-MM-DD.souqi`,
/// its own keep-N, its own on/off. It reaches the job through
/// [DailyReportJob.backupOutput] rather than [dailyOutputs], because it runs
/// with the debt report off too.
abstract class DailyOutput {
  String get id;

  DatedFilePattern get files;

  int get keepDays;

  Future<List<StagedFile>> build(DailyJobContext context);
}

/// The daily debt report: the Excel workbook and/or the PDF.
class DebtReportOutput implements DailyOutput {
  DebtReportOutput({required this.settings, required this.loadFonts});

  final DebtReportSettings settings;
  final Future<ReportFonts> Function() loadFonts;

  /// What the last [build] read — the notification quotes it.
  DebtReportData? data;

  @override
  String get id => 'debts';

  @override
  DatedFilePattern get files => debtReportFiles;

  @override
  int get keepDays => settings.keepDays;

  @override
  Future<List<StagedFile>> build(DailyJobContext context) async {
    final report = data =
        await DebtReportRepository(context.db).build(now: context.now);
    final staged = <StagedFile>[];
    for (final format in settings.orderedFormats) {
      final bytes = switch (format) {
        ReportFormat.xlsx => buildDebtReportXlsx(report),
        ReportFormat.pdf =>
          await buildDebtReportPdf(report, fonts: await loadFonts()),
      };
      final name = files.nameFor(context.now, format.extension);
      final file = File(p.join(context.stagingDir.path, name));
      await file.writeAsBytes(bytes, flush: true);
      staged.add(
        StagedFile(name: name, path: file.path, mimeType: format.mimeType),
      );
    }
    return staged;
  }
}

/// Every output of the daily job, in the order they run. PHASE 5: the
/// backup output is added to this list.
List<DailyOutput> dailyOutputs(
  DebtReportSettings settings, {
  required Future<ReportFonts> Function() loadFonts,
}) =>
    [DebtReportOutput(settings: settings, loadFonts: loadFonts)];

/// The folder (under the app's own files) where outputs are staged.
const String stagingDirName = 'reports';

class DailyJobResult {
  const DailyJobResult({
    this.outcome,
    this.problem,
    this.location,
    this.busy = false,
    this.skipped = false,
  });

  const DailyJobResult.busy() : this(busy: true);

  const DailyJobResult.skipped() : this(skipped: true);

  final ReportOutcome? outcome;
  final ReportProblem? problem;
  final String? location;

  /// Another run (the other engine's) held the lock.
  final bool busy;

  /// Nothing to do: the feature is off.
  final bool skipped;
}

/// THE DAILY JOB: build every output, write the files to the chosen folder —
/// or, when it is not available, to Download/Souqi/Reports — rotate the old
/// files, record the status and post the notification.
///
/// Runs the same in the app (catch-up, "Create report now") and in the
/// background engine WorkManager starts. It READS the database and writes
/// nothing to it: the status goes to the Android side ([ReportPlatform]),
/// so two engines never write to the database at the same time.
///
/// The app never sends anything by itself: the files land in a folder, and
/// only the user's own tap on "Share" hands them to another app.
class DailyReportJob {
  DailyReportJob({
    required this.db,
    required this.platform,
    required this.stagingDir,
    required this.loadFonts,
    required this.featureOn,
    this.clock = DateTime.now,
    this.outputsFor = dailyOutputs,
    this.backupOutput,
  });

  final Database db;
  final ReportPlatform platform;
  final Future<Directory> Function() stagingDir;
  final Future<ReportFonts> Function() loadFonts;

  /// The daily debt report may be made: `featureOn(Feature.dailyReport)` —
  /// in the build, in the license, and the ledger with it.
  final bool featureOn;
  final DateTime Function() clock;
  final List<DailyOutput> Function(
    DebtReportSettings settings, {
    required Future<ReportFonts> Function() loadFonts,
  }) outputsFor;

  /// The daily automatic backup (phase 5): its output for this run, or null
  /// when it is off. It has its own on/off — it runs with the debt report
  /// (and even the whole debt ledger) off — and is never part of "Create
  /// report now".
  final Future<DailyOutput?> Function(Map<String, String> stored)?
      backupOutput;

  /// [lockHeld]: the caller already holds the run lock (the background
  /// engine takes it BEFORE it opens the database, so a restore in the app
  /// cannot swap the file under it).
  Future<DailyJobResult> run(
    ReportTrigger trigger, {
    bool lockHeld = false,
  }) async {
    final stored = await SettingsRepository(db).getAll();
    final settings = DebtReportSettings.fromMap(stored);
    final reportWanted =
        featureOn && (trigger == ReportTrigger.manual || settings.enabled);
    final backup = trigger == ReportTrigger.manual || backupOutput == null
        ? null
        : await backupOutput!(stored);
    if (!reportWanted && backup == null) return const DailyJobResult.skipped();
    if (!lockHeld && !await platform.tryBeginRun()) {
      return const DailyJobResult.busy();
    }
    try {
      return await _run(settings, stored, report: reportWanted, backup: backup);
    } finally {
      if (!lockHeld) await platform.endRun();
    }
  }

  Future<DailyJobResult> _run(
    DebtReportSettings settings,
    Map<String, String> stored, {
    required bool report,
    required DailyOutput? backup,
  }) async {
    final now = clock().toLocal();
    final previous = DebtReportStatus.fromJson(await platform.loadStatus());
    final outputs = [
      if (report) ...outputsFor(settings, loadFonts: loadFonts),
      ?backup,
    ];
    final dir = await stagingDir();
    await dir.create(recursive: true);

    // 1. Build every output.
    final staged = <StagedFile>[];
    try {
      for (final output in outputs) {
        staged.addAll(await output.build(
          DailyJobContext(db: db, now: now, stagingDir: dir),
        ));
      }
    } on Object {
      return _finish(
        settings,
        stored,
        previous,
        now,
        outputs,
        outcome: ReportOutcome.failed,
        problem: ReportProblem.unknown,
      );
    }
    _pruneStaging(dir, outputs, keep: {for (final f in staged) f.name});

    // 2. Write them: to the chosen folder, or to Downloads.
    final chosen = settings.folderUri;
    var destination = chosen == null
        ? const ReportDestination.downloads()
        : ReportDestination.folder(chosen);
    var outcome = ReportOutcome.ok;
    ReportProblem? problem;
    String? location;
    if (chosen != null && !await _available(chosen)) {
      destination = const ReportDestination.downloads();
      outcome = ReportOutcome.fallback;
      problem = ReportProblem.folderUnavailable;
    }
    try {
      location = await _writeAll(destination, staged);
    } on Object catch (error) {
      if (destination.isDownloads) {
        return _finish(
          settings,
          stored,
          previous,
          now,
          outputs,
          outcome: ReportOutcome.failed,
          problem: ReportProblem.writeFailed,
        );
      }
      // The folder failed half-way: the whole set goes to Downloads.
      destination = const ReportDestination.downloads();
      outcome = ReportOutcome.fallback;
      problem = error is ReportDestinationUnavailable
          ? ReportProblem.folderUnavailable
          : ReportProblem.writeFailed;
      try {
        location = await _writeAll(destination, staged);
      } on Object {
        return _finish(
          settings,
          stored,
          previous,
          now,
          outputs,
          outcome: ReportOutcome.failed,
          problem: ReportProblem.writeFailed,
        );
      }
    }

    // The staged copies nobody will share (the backup) go now.
    for (final file in staged) {
      if (file.shareable) continue;
      try {
        await File(file.path).delete();
      } on FileSystemException {
        // Swept with the staging folder next time.
      }
    }

    // 3. Keep-N, per output, in the folder actually written to.
    await _rotate(destination, outputs);

    return _finish(
      settings,
      stored,
      previous,
      now,
      outputs,
      outcome: outcome,
      problem: problem,
      location: location,
      destination: destination,
      staged: staged,
    );
  }

  Future<bool> _available(String uri) async {
    try {
      return await platform.folderAvailable(uri);
    } on Object {
      return false;
    }
  }

  Future<String?> _writeAll(
    ReportDestination destination,
    List<StagedFile> staged,
  ) async {
    String? location;
    for (final file in staged) {
      location = await platform.writeFile(
        destination,
        name: file.name,
        sourcePath: file.path,
        mimeType: file.mimeType,
      );
    }
    return location;
  }

  /// Deletes what each output's keep-N rule says, and only its own files.
  /// A rotation that fails is tried again on the next run.
  Future<void> _rotate(
    ReportDestination destination,
    List<DailyOutput> outputs,
  ) async {
    final List<String> names;
    try {
      names = await platform.listFiles(destination);
    } on Object {
      return;
    }
    for (final output in outputs) {
      for (final name in output.files.namesToDelete(
        names,
        keepDays: output.keepDays,
      )) {
        try {
          await platform.deleteFile(destination, name);
        } on Object {
          // Next time.
        }
      }
    }
  }

  /// The app's own copies: only the newest set stays (it is what "Share"
  /// sends); every older file of these outputs goes.
  void _pruneStaging(
    Directory dir,
    List<DailyOutput> outputs, {
    required Set<String> keep,
  }) {
    try {
      for (final entity in dir.listSync()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (keep.contains(name)) continue;
        if (outputs.any((o) => o.files.matches(name))) entity.deleteSync();
      }
    } on FileSystemException {
      // Housekeeping only.
    }
  }

  Future<DailyJobResult> _finish(
    DebtReportSettings settings,
    Map<String, String> stored,
    DebtReportStatus previous,
    DateTime now,
    List<DailyOutput> outputs, {
    required ReportOutcome outcome,
    ReportProblem? problem,
    String? location,
    ReportDestination? destination,
    List<StagedFile> staged = const [],
  }) async {
    final written = outcome != ReportOutcome.failed;
    final report = outputs.whereType<DebtReportOutput>().firstOrNull?.data;
    final backedUp = outputs.any((o) => o.id == 'backup');
    final status = written
        ? DebtReportStatus(
            lastAttemptAt: now,
            lastSuccessAt: now,
            outcome: outcome,
            problem: problem,
            location: location,
            savedToFolderUri: destination?.treeUri,
            files: [
              for (final f in staged)
                if (f.shareable) f.path,
            ],
            debtors: report?.summary.debtorsCount,
            outstandingBaseMinor: report?.summary.totalOutstandingBaseMinor,
            lastBackupAt: backedUp ? now : previous.lastBackupAt,
            backupLocation: backedUp ? location : previous.backupLocation,
          )
        // A failure keeps what the last good report said, so "Share" and
        // "Open folder" still find it.
        : DebtReportStatus(
            lastAttemptAt: now,
            lastSuccessAt: previous.lastSuccessAt,
            outcome: outcome,
            problem: problem,
            location: previous.location,
            savedToFolderUri: previous.savedToFolderUri,
            files: previous.files,
            debtors: previous.debtors,
            outstandingBaseMinor: previous.outstandingBaseMinor,
            lastBackupAt: previous.lastBackupAt,
            backupLocation: previous.backupLocation,
          );
    try {
      await platform.saveStatus(status.toJson());
    } on Object {
      // The files are written; a lost status only means a catch-up run.
    }
    final notice = report == null && backedUp
        ? _backupNotice(stored, status)
        : _notice(stored, settings, status, report);
    if (notice != null) {
      try {
        await platform.showNotice(notice);
      } on Object {
        // Notifications off, or none on this platform.
      }
    }
    return DailyJobResult(
      outcome: outcome,
      problem: problem,
      location: written ? location : null,
    );
  }

  /// The notification, in the APP language (it speaks to the seller). A
  /// good run only notifies with "Notify me when ready" on; a fallback or a
  /// failure always does — that is exactly when the shop must know.
  ReportNotice? _notice(
    Map<String, String> stored,
    DebtReportSettings settings,
    DebtReportStatus status,
    DebtReportData? report,
  ) {
    final language =
        (stored[SettingsKeys.appLanguage] ?? 'ar') == 'en' ? 'en' : 'ar';
    final l10n = lookupAppLocalizations(Locale(language));
    final channel = l10n.debtReportChannelName;
    final location = status.location ?? '';
    switch (status.outcome) {
      case ReportOutcome.ok:
        if (!settings.notify || report == null) return null;
        final currency = report.currency;
        return ReportNotice(
          channelName: channel,
          title: l10n.debtReportNoticeReady,
          text: l10n.debtReportNoticeReadyText(
            report.summary.debtorsCount,
            formatMinor(
              report.summary.totalOutstandingBaseMinor,
              decimals: currency.decimals,
              locale: language,
              symbol: currency.label,
            ),
          ),
          publicTitle: l10n.debtReportNoticeReady,
          shareLabel: l10n.debtReportShare,
          openFolderLabel: l10n.debtReportOpenFolder,
        );
      case ReportOutcome.fallback:
        return ReportNotice(
          channelName: channel,
          title: l10n.debtReportNoticeFallback,
          text: l10n.debtReportNoticeFallbackText(location),
          publicTitle: l10n.debtReportNoticeFallback,
          shareLabel: l10n.debtReportShare,
          openFolderLabel: l10n.debtReportOpenFolder,
        );
      case ReportOutcome.failed:
        final reason = reportProblemText(l10n, status.problem);
        return ReportNotice(
          channelName: channel,
          title: l10n.debtReportNoticeFailed,
          text: l10n.debtReportNoticeFailedText(
            reason.isEmpty
                ? reason
                : reason[0].toUpperCase() + reason.substring(1),
          ),
          publicTitle: l10n.debtReportNoticeFailed,
        );
      case null:
        return null;
    }
  }
}

extension on DailyReportJob {
  /// A run that made only the backup (the debt report is off): nothing to
  /// say when it worked; a fallback or a failure is said, like the report's.
  ReportNotice? _backupNotice(
    Map<String, String> stored,
    DebtReportStatus status,
  ) {
    final language =
        (stored[SettingsKeys.appLanguage] ?? 'ar') == 'en' ? 'en' : 'ar';
    final l10n = lookupAppLocalizations(Locale(language));
    final channel = l10n.debtReportChannelName;
    switch (status.outcome) {
      case ReportOutcome.ok:
      case null:
        return null;
      case ReportOutcome.fallback:
        return ReportNotice(
          channelName: channel,
          title: l10n.backupNoticeFallback,
          text: l10n.backupNoticeFallbackText(status.location ?? ''),
          publicTitle: l10n.backupNoticeFallback,
          openFolderLabel: l10n.debtReportOpenFolder,
        );
      case ReportOutcome.failed:
        final reason = reportProblemText(l10n, status.problem);
        return ReportNotice(
          channelName: channel,
          title: l10n.backupNoticeFailed,
          text: l10n.backupNoticeFailedText(
            reason.isEmpty
                ? reason
                : reason[0].toUpperCase() + reason.substring(1),
          ),
          publicTitle: l10n.backupNoticeFailed,
        );
    }
  }
}

/// "folder not available", "the file could not be written"…
String reportProblemText(AppLocalizations l10n, ReportProblem? problem) =>
    switch (problem) {
      ReportProblem.folderUnavailable => l10n.debtReportProblemFolder,
      ReportProblem.writeFailed => l10n.debtReportProblemWrite,
      ReportProblem.unknown || null => l10n.debtReportProblemUnknown,
    };
