import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/logging/error_log.dart';
import '../../config/features.dart';
import '../../core/backup/backup_crypto.dart';
import '../../core/backup/backup_file.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/platform/report_platform.dart';
import '../../core/providers.dart';
import '../../data/backup/backup_service.dart';
import '../../data/backup/restore_journal.dart';
import '../../data/db/app_database.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../debts/report/debt_report_settings_screen.dart';
import '../debts/report/report_providers.dart';
import '../debts/report/report_schedule.dart';
import '../debts/report/report_settings.dart';
import '../invoice/invoice_providers.dart';
import '../security/audit_providers.dart';
import '../security/pin_dialogs.dart';
import 'auto_backup.dart';
import 'backup_actions.dart';
import 'backup_dialogs.dart';
import 'backup_providers.dart';

/// Where a backup made by hand goes.
enum BackupDestination { share, phone, folder }

/// Downloads/Souqi/Backups.
const String backupDownloadsFolder = 'Souqi/Backups';

/// Settings → "Backup & restore", with the date of the last backup.
class BackupSettingsTile extends ConsumerWidget {
  const BackupSettingsTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final now = ref.watch(clockProvider)();
    final last = ref.watch(lastBackupAtProvider).value;
    // A license without backups: no way into the page.
    if (!featureOn(Feature.backup)) return const SizedBox.shrink();
    return ListTile(
      key: const ValueKey('setting-backup'),
      leading: const Icon(Icons.backup_outlined),
      title: Text(l10n.backupTitle),
      subtitle: Text(
        last == null
            ? l10n.backupNever
            : l10n.backupLast(
                formatReportWhen(l10n, last, now: now, locale: locale),
              ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
      ),
    );
  }
}

/// "No backup in the last 7 days" — at the top of the settings and of the
/// backup page, while it is true.
class BackupReminderBanner extends ConsumerWidget {
  const BackupReminderBanner({super.key, this.openPage = true});

  /// On the settings list the banner opens the backup page.
  final bool openPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (!featureOn(Feature.backup) ||
        ref.watch(backupReminderProvider).value != true) {
      return const SizedBox.shrink();
    }
    final never = ref.watch(lastBackupAtProvider).value == null;
    return Card(
      key: const ValueKey('backup-reminder'),
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: theme.colorScheme.errorContainer,
      child: ListTile(
        leading: Icon(Icons.warning_amber,
            color: theme.colorScheme.onErrorContainer),
        title: Text(
          never ? l10n.backupReminderNever : l10n.backupReminderOld,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        subtitle: Text(
          l10n.backupReminderHint,
          style: TextStyle(color: theme.colorScheme.onErrorContainer),
        ),
        onTap: openPage
            ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BackupScreen()),
                )
            : null,
      ),
    );
  }
}

/// Choose where the new backup goes. Pops a [BackupDestination] or null.
class BackupDestinationSheet extends StatelessWidget {
  const BackupDestinationSheet({super.key, this.folderName});

  /// The daily report's folder, when one is chosen.
  final String? folderName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        key: const ValueKey('backup-destination-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.backupWhereTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const ValueKey('backup-to-share'),
            leading: const Icon(Icons.share),
            title: Text(l10n.backupToShare),
            subtitle: Text(l10n.backupToShareHint),
            onTap: () => Navigator.of(context).pop(BackupDestination.share),
          ),
          ListTile(
            key: const ValueKey('backup-to-phone'),
            leading: const Icon(Icons.download_outlined),
            title: Text(l10n.backupToPhone),
            subtitle: Text(l10n.backupToPhoneHint),
            onTap: () => Navigator.of(context).pop(BackupDestination.phone),
          ),
          if (folderName != null)
            ListTile(
              key: const ValueKey('backup-to-folder'),
              leading: const Icon(Icons.folder_outlined),
              title: Text(l10n.backupToFolder),
              subtitle: Text(folderName!),
              onTap: () => Navigator.of(context).pop(BackupDestination.folder),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Settings → Backup & restore: make a backup file, restore one, and the
/// daily automatic backup.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _message(String title, String message) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BackupMessageDialog(title: title, message: message),
    );
  }

  // ---- Create ------------------------------------------------------------

  Future<void> _create() async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    if (!await requirePinIfSet(context, reason: l10n.pinReasonBackup)) return;
    if (!mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => BackupPasswordDialog(
        title: l10n.backupCreateTitle,
        intro: l10n.backupCreateIntro,
      ),
    );
    if (password == null || !mounted) return;
    final report = await container.read(debtReportSettingsProvider.future);
    if (!mounted) return;
    final destination = await showModalBottomSheet<BackupDestination>(
      context: context,
      showDragHandle: true,
      builder: (_) => BackupDestinationSheet(
        folderName: report.usesDownloads
            ? null
            : (report.folderName?.isNotEmpty ?? false)
                ? report.folderName
                : l10n.debtReportFolderLabel,
      ),
    );
    if (destination == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final CreatedBackup created;
      try {
        created = await runWithProgress(
          context,
          l10n.backupCreating,
          () => createBackupFile(
            container,
            password: password,
            record: false,
          ),
        );
      } on Object catch (error, stack) {
        reportError(error, stack, context: 'backup create');
        _say(l10n.backupCreateFailed);
        return;
      }
      // Logged, and counted as the last backup, only once the file is
      // where it was sent.
      if (await _deliver(container, created, destination, report)) {
        await recordBackupCreated(container, created);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// True when the file reached [destination] (for the share sheet: when
  /// the sheet opened — what the seller does in it cannot be seen).
  Future<bool> _deliver(
    ProviderContainer container,
    CreatedBackup created,
    BackupDestination destination,
    DebtReportSettings report,
  ) async {
    final l10n = AppLocalizations.of(context);
    final bridge = container.read(nativeBridgeProvider);
    try {
      switch (destination) {
        case BackupDestination.share:
          await bridge.shareFile(
            filePath: created.path,
            mimeType: backupMimeType,
          );
        case BackupDestination.phone:
          final where = await bridge.saveToDownloads(
            filePath: created.path,
            fileName: created.name,
            mimeType: backupMimeType,
            subfolder: backupDownloadsFolder,
          );
          _say(l10n.backupSavedTo(where));
        case BackupDestination.folder:
          final where = await container.read(reportPlatformProvider).writeFile(
                ReportDestination.folder(report.folderUri!),
                name: created.name,
                sourcePath: created.path,
                mimeType: backupMimeType,
              );
          _say(l10n.backupSavedTo(where));
      }
      return true;
    } on ReportDestinationUnavailable {
      _say(l10n.backupFolderUnavailable);
    } on OutputException catch (e) {
      _say(e.failure == OutputFailure.storagePermissionDenied
          ? l10n.backupStorageDenied
          : l10n.backupSaveFailed);
    } on Object catch (error, stack) {
      reportError(error, stack, context: 'backup deliver');
      _say(l10n.backupSaveFailed);
    }
    return false;
  }

  // ---- Restore -----------------------------------------------------------

  Future<void> _restore() async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    final bridge = container.read(nativeBridgeProvider);
    final service = container.read(backupServiceProvider);
    final PickedFile? picked;
    try {
      picked = await bridge.pickFile();
    } on Object {
      _say(l10n.restorePickFailed);
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    ExtractedBackup? extracted;
    try {
      try {
        extracted = await runWithProgress(
          context,
          l10n.restoreChecking,
          () => service.inspect(picked!.path),
        );
      } on NewerBackupException catch (e) {
        await _message(
          l10n.restoreNewerTitle,
          l10n.restoreNewerText(e.appVersion ?? '?'),
        );
        return;
      } on Object {
        await _message(l10n.restoreCorruptTitle, l10n.restoreCorruptText);
        return;
      }
      if (!mounted) return;

      final opened = await showDialog<Object>(
        context: context,
        builder: (_) => BackupUnlockDialog(
          manifest: extracted!.manifest,
          unlock: (password) => service.unlock(extracted!, password),
        ),
      );
      if (opened is CorruptBackupException) {
        await _message(l10n.restoreCorruptTitle, l10n.restoreTamperedText);
        return;
      }
      if (opened is! UnlockedBackup || !mounted) return;

      final sure = await showDialog<bool>(
        context: context,
        builder: (_) => RestoreConfirmDialog(manifest: opened.manifest),
      );
      if (sure != true || !mounted) return;
      if (!await requirePinIfSet(context, reason: l10n.pinReasonRestore)) {
        return;
      }
      if (!mounted) return;

      try {
        await runWithProgress(
          context,
          l10n.restoreRunning,
          () => restoreBackup(container, opened),
        );
        // The app has started over on the restored data; this screen is
        // gone and the new start says so.
        extracted = null;
      } on BackupBusyException {
        _say(l10n.restoreBusy);
      } on NewerBackupException catch (e) {
        await _message(
          l10n.restoreNewerTitle,
          l10n.restoreNewerText(e.appVersion ?? '?'),
        );
      } on RestoreCheckFailedException {
        await _message(l10n.restoreCorruptTitle, l10n.restoreCorruptText);
      } on RestoreFailedException<AppDatabase> {
        // The swap failed and was undone: the app has started over on its
        // own data, and that start says so. This screen is gone.
        extracted = null;
      } on Object {
        // Before the swap: nothing changed.
        await _message(l10n.restoreFailedTitle, l10n.restoreFailedText);
      }
    } finally {
      await extracted?.discard();
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---- The daily automatic backup -------------------------------------------

  Future<void> _log(AuditAction action, {Map<String, Object?>? details}) async {
    final container = _container;
    await container.read(auditRepositoryProvider).log(
          action,
          entityType: 'backup',
          details: details ?? const {},
        );
    container.invalidate(auditLogProvider);
  }

  /// Asks for a new password and keeps its key in the Keystore.
  Future<bool> _setAutoPassword({required bool change}) async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => BackupPasswordDialog(
        title: change ? l10n.backupAutoChangePassword : l10n.backupAutoSetPassword,
        intro: l10n.backupAutoPasswordIntro,
      ),
    );
    if (password == null || !mounted) return false;
    final iterations = container.read(backupIterationsProvider);
    final keys = container.read(secretKeyStoreProvider);
    try {
      await runWithProgress(context, l10n.backupPreparing, () async {
        final key = await newBackupKey(password, iterations: iterations);
        await keys.write(autoBackupKeyName, key.toStored());
      });
    } on Object {
      _say(l10n.backupKeystoreFailed);
      return false;
    }
    container.invalidate(autoBackupHasKeyProvider);
    return true;
  }

  Future<void> _setAuto(AutoBackupSettings s, bool on, bool hasKey) async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    if (!await requirePinIfSet(context, reason: l10n.pinReasonBackup)) return;
    if (!mounted) return;
    if (!on) {
      await container
          .read(autoBackupSettingsProvider.notifier)
          .save(s.copyWith(enabled: false));
      await replanDailyJob(container);
      await _log(AuditAction.backupAutoOff);
      return;
    }
    if (!hasKey && !await _setAutoPassword(change: false)) return;
    if (!mounted) return;
    try {
      await container
          .read(nativeBridgeProvider)
          .requestLegacyStoragePermission();
    } on Object {
      // Android 10+ needs none.
    }
    // Android 13+: without this the "backup could not be written" and
    // "saved to Downloads instead" notifications are dropped silently —
    // the only way the shop hears that its nightly backup is failing.
    try {
      await container.read(nativeBridgeProvider).requestNotificationPermission();
    } on Object {
      // Older Android has no such permission.
    }
    await container.read(autoBackupSettingsProvider.notifier).save(
          s.copyWith(enabled: true, enabledAt: container.read(clockProvider)()),
        );
    await replanDailyJob(container);
    await _log(AuditAction.backupAutoOn);
    final exempt = await container.read(batteryExemptProvider.future);
    if (exempt || !mounted) return;
    final wants = await showDialog<bool>(
      context: context,
      builder: (_) => const BatteryExemptionDialog(),
    );
    if (wants != true) return;
    try {
      await container.read(nativeBridgeProvider).requestBatteryExemption();
    } on Object {
      // The debt report page offers it again.
    }
    container.invalidate(batteryExemptProvider);
  }

  Future<void> _changeAutoPassword() async {
    final l10n = AppLocalizations.of(context);
    // Changing it asks for THE PIN (one is chosen first if there is none):
    // whoever sets it can open every backup made from then on.
    if (!await requirePin(context, reason: l10n.pinReasonBackupPassword)) {
      return;
    }
    if (!mounted) return;
    if (!await _setAutoPassword(change: true)) return;
    await _log(AuditAction.backupPasswordChange);
    _say(l10n.backupAutoPasswordChanged);
  }

  Future<void> _pickTime(DebtReportSettings report) async {
    final container = _container;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: report.minuteOfDay ~/ 60,
        minute: report.minuteOfDay % 60,
      ),
    );
    if (picked == null) return;
    await container.read(debtReportSettingsProvider.notifier).save(
          report.copyWith(minuteOfDay: picked.hour * 60 + picked.minute),
        );
    await replanDailyJob(container);
  }

  Future<void> _chooseFolder(DebtReportSettings report) async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    if (!await requirePinIfSet(context, reason: l10n.pinReasonBackup)) return;
    final PickedFolder? picked;
    try {
      picked = await container.read(nativeBridgeProvider).pickFolder();
    } on Object {
      _say(l10n.debtReportFolderPickFailed);
      return;
    }
    if (picked == null) return;
    final old = report.folderUri;
    final name = picked.name.isEmpty ? l10n.debtReportFolderLabel : picked.name;
    await container.read(debtReportSettingsProvider.notifier).save(
          report.copyWith(
            folderUri: picked.uri,
            folderName: name,
            folderKind: FolderKind.fromDb(picked.kind),
          ),
        );
    await container.read(auditRepositoryProvider).log(
      AuditAction.debtReportFolder,
      entityType: 'debt_report',
      details: {'folder': name},
    );
    container.invalidate(auditLogProvider);
    if (old != null && old != picked.uri) {
      try {
        await container.read(reportPlatformProvider).releaseFolder(old);
      } on Object {
        // An unused grant does no harm.
      }
    }
    _say(l10n.debtReportFolderChanged);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final now = ref.watch(clockProvider)();
    final auto =
        ref.watch(autoBackupSettingsProvider).value ?? const AutoBackupSettings();
    final hasKey = ref.watch(autoBackupHasKeyProvider).value ?? false;
    final report =
        ref.watch(debtReportSettingsProvider).value ?? const DebtReportSettings();
    final status =
        ref.watch(debtReportStatusProvider).value ?? const DebtReportStatus();
    final last = ref.watch(lastBackupAtProvider).value;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: report.minuteOfDay ~/ 60, minute: report.minuteOfDay % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final folder = report.usesDownloads
        ? l10n.debtReportFolderDownloads
        : (report.folderName?.isNotEmpty ?? false)
            ? report.folderName!
            : l10n.debtReportFolderLabel;
    String when(DateTime at) =>
        formatReportWhen(l10n, at, now: now, locale: locale);
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.backupTitle)),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          key: const ValueKey('backup-screen'),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            const BackupReminderBanner(openPage: false),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(
                last == null ? l10n.backupNever : l10n.backupLast(when(last)),
                key: const ValueKey('backup-last'),
              ),
            ),
            section(l10n.backupCreateSection),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.backupCreateHint, style: muted),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: FilledButton.icon(
                key: const ValueKey('backup-create'),
                onPressed: _busy ? null : _create,
                icon: const Icon(Icons.backup_outlined),
                label: Text(l10n.backupCreateButton),
              ),
            ),
            section(l10n.restoreSection),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.restoreHint, style: muted),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: OutlinedButton.icon(
                key: const ValueKey('backup-restore'),
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.settings_backup_restore),
                label: Text(l10n.restoreButton),
              ),
            ),
            const Divider(height: 32),
            SwitchListTile(
              key: const ValueKey('backup-auto'),
              secondary: const Icon(Icons.schedule),
              title: Text(l10n.backupAutoTitle),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.backupAutoIntro),
                  if (auto.enabled && status.lastBackupAt != null)
                    Text(
                      l10n.backupAutoLast(when(status.lastBackupAt!)),
                      key: const ValueKey('backup-auto-last'),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.primary),
                    ),
                  if (auto.enabled && hasKey)
                    Text(
                      l10n.debtReportNext(
                        when(nextScheduledRun(now, report.minuteOfDay)),
                      ),
                      style: muted,
                    ),
                ],
              ),
              value: auto.enabled && hasKey,
              onChanged: (on) => _setAuto(auto, on, hasKey),
            ),
            if (auto.enabled && !hasKey)
              ListTile(
                key: const ValueKey('backup-auto-no-key'),
                leading: Icon(Icons.key_off_outlined,
                    color: theme.colorScheme.error),
                title: Text(l10n.backupAutoNoKey),
                subtitle: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton(
                    onPressed: () => _setAuto(auto, true, false),
                    child: Text(l10n.backupAutoSetPassword),
                  ),
                ),
              ),
            ListTile(
              key: const ValueKey('backup-auto-time'),
              leading: const Icon(Icons.access_time),
              title: Text(l10n.debtReportTimeLabel),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(time, style: theme.textTheme.titleMedium),
                  Text(l10n.backupAutoSharedHint),
                ],
              ),
              onTap: () => _pickTime(report),
            ),
            ListTile(
              key: const ValueKey('backup-auto-folder'),
              leading: Icon(report.usesDownloads
                  ? Icons.download_outlined
                  : Icons.folder_outlined),
              title: Text(l10n.debtReportFolderLabel),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(folder, style: theme.textTheme.titleSmall),
                  if (report.staysOnPhone)
                    Text(
                      l10n.backupAutoOnPhoneWarning,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                ],
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _chooseFolder(report),
            ),
            ListTile(
              key: const ValueKey('backup-auto-keep'),
              leading: const Icon(Icons.layers_outlined),
              title: Text(l10n.backupAutoKeepLabel),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButton<int>(
                    key: const ValueKey('backup-auto-keep-dropdown'),
                    value: auto.keepDays,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    items: [
                      for (final days in {
                        ...AutoBackupSettings.keepChoices,
                        auto.keepDays,
                      }.toList()
                        ..sort())
                        DropdownMenuItem(
                          value: days,
                          child: Text(
                            l10n.daysCount(days),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (days) {
                      if (days == null) return;
                      ref
                          .read(autoBackupSettingsProvider.notifier)
                          .save(auto.copyWith(keepDays: days));
                    },
                  ),
                  Text(l10n.backupAutoKeepHint),
                ],
              ),
            ),
            if (hasKey)
              ListTile(
                key: const ValueKey('backup-auto-password'),
                leading: const Icon(Icons.password),
                title: Text(l10n.backupAutoChangePassword),
                onTap: _changeAutoPassword,
              ),
          ],
        ),
      ),
    );
  }
}
