import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/platform/native_bridge.dart';
import '../../../core/providers.dart';
import '../../../domain/models/voucher.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../customers/customers_providers.dart';
import '../../invoice/invoice_providers.dart';
import '../../security/audit_providers.dart';
import '../../security/pin_dialogs.dart';
import 'daily_job.dart';
import 'report_providers.dart';
import 'report_schedule.dart';
import 'report_settings.dart';

/// "today 22:01", "yesterday 22:01", "24/11/2026 22:01".
String formatReportWhen(
  AppLocalizations l10n,
  DateTime at, {
  required DateTime now,
  required String locale,
}) {
  final local = at.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final time = DateFormat.Hm(locale).format(local);
  final days = DateTime.utc(day.year, day.month, day.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  return switch (days) {
    0 => l10n.debtReportToday(time),
    -1 => l10n.debtReportYesterday(time),
    1 => l10n.debtReportTomorrow(time),
    _ => '${DateFormat.yMd(locale).format(local)} $time',
  };
}

/// The line under the setting: "Last report: today 22:01 ✓",
/// "Failed: folder not available", "No report yet".
String debtReportStatusLine(
  AppLocalizations l10n,
  DebtReportStatus status, {
  required DateTime now,
  required String locale,
}) {
  String when(DateTime? at) =>
      at == null ? '' : formatReportWhen(l10n, at, now: now, locale: locale);
  return switch (status.outcome) {
    null => l10n.debtReportNever,
    ReportOutcome.ok => l10n.debtReportLastOk(when(status.lastSuccessAt)),
    ReportOutcome.fallback =>
      l10n.debtReportLastFallback(when(status.lastSuccessAt)),
    ReportOutcome.failed =>
      l10n.debtReportLastFailed(reportProblemText(l10n, status.problem)),
  };
}

/// Settings → Debts → "Daily debt report": the tile that opens the page,
/// with the state of the last run under it.
class DebtReportTile extends ConsumerWidget {
  const DebtReportTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(debtReportSettingsProvider).value;
    final status = ref.watch(debtReportStatusProvider).value;
    final locale = ref.watch(appLocaleProvider).languageCode;
    final now = ref.watch(clockProvider)();
    final on = settings?.enabled ?? false;
    return ListTile(
      key: const ValueKey('setting-debt-report'),
      leading: const Icon(Icons.summarize_outlined),
      title: Text(l10n.debtReportTitle),
      subtitle: Text(
        !on
            ? l10n.debtReportOff
            : debtReportStatusLine(
                l10n,
                status ?? const DebtReportStatus(),
                now: now,
                locale: locale,
              ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const DebtReportSettingsScreen(),
        ),
      ),
    );
  }
}

/// Explains why battery optimization matters and offers the exemption.
/// Returns true when the user wants it.
class BatteryExemptionDialog extends StatelessWidget {
  const BatteryExemptionDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('debt-report-battery-dialog'),
      title: Text(l10n.debtReportBatteryTitle),
      scrollable: true,
      content: Text(l10n.debtReportBatteryHint),
      actions: [
        TextButton(
          key: const ValueKey('debt-report-battery-later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.debtReportBatteryLater),
        ),
        FilledButton(
          key: const ValueKey('debt-report-battery-ok'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.debtReportBatteryButton),
        ),
      ],
    );
  }
}

/// The page itself: on/off, time, formats, folder, how many days to keep,
/// the notification, the battery exemption and "Create report now".
///
/// The report holds every customer's name, phone and balance: turning it on
/// and changing where it goes ask for the PIN when one is set, and both are
/// written to the audit log.
class DebtReportSettingsScreen extends ConsumerStatefulWidget {
  const DebtReportSettingsScreen({super.key});

  @override
  ConsumerState<DebtReportSettingsScreen> createState() =>
      _DebtReportSettingsScreenState();
}

class _DebtReportSettingsScreenState
    extends ConsumerState<DebtReportSettingsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from the battery or notification settings: look again.
    _lifecycle = AppLifecycleListener(onResume: _recheck);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _recheck() {
    if (!mounted) return;
    ref
      ..invalidate(batteryExemptProvider)
      ..invalidate(reportNotificationsAllowedProvider);
  }

  ProviderContainer get _container =>
      ProviderScope.containerOf(context, listen: false);

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// The PIN, when one is set. With no PIN there is nothing to ask — the
  /// report never forces the shop to choose one.
  Future<bool> _pinIfSet() async {
    final l10n = AppLocalizations.of(context);
    final pins = _container.read(pinRepositoryProvider);
    if (!await pins.isSet()) return true;
    if (!mounted) return false;
    return requirePin(context, reason: l10n.pinReasonDebtReport);
  }

  Future<void> _save(DebtReportSettings next) =>
      _container.read(debtReportSettingsProvider.notifier).save(next);

  String _folderLabel(AppLocalizations l10n, DebtReportSettings s) =>
      s.usesDownloads
          ? l10n.debtReportFolderDownloads
          : (s.folderName?.isNotEmpty ?? false)
              ? s.folderName!
              : l10n.debtReportFolderLabel;

  Future<void> _log(AuditAction action, {String? folder}) async {
    final container = _container;
    await container.read(auditRepositoryProvider).log(
          action,
          entityType: 'debt_report',
          details: {'folder': folder},
        );
    container.invalidate(auditLogProvider);
  }

  Future<void> _setEnabled(DebtReportSettings s, bool on) async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    final bridge = container.read(nativeBridgeProvider);
    final platform = container.read(reportPlatformProvider);
    if (!on) {
      await _save(s.copyWith(enabled: false));
      try {
        await platform.cancelSchedule();
      } on Object {
        // Nothing planned on this platform.
      }
      await _log(AuditAction.debtReportOff);
      return;
    }
    if (!await _pinIfSet()) return;
    // Asked here, while the seller is looking: the background job cannot.
    if (s.notify) {
      try {
        await bridge.requestNotificationPermission();
      } on Object {
        // Shown as a banner below if still off.
      }
    }
    try {
      await bridge.requestLegacyStoragePermission();
    } on Object {
      // Android 10+ needs none.
    }
    final next = s.copyWith(
      enabled: true,
      enabledAt: container.read(clockProvider)(),
    );
    await _save(next);
    try {
      await platform.schedule(next.minuteOfDay, replace: true);
    } on Object {
      // Not on Android.
    }
    await _log(AuditAction.debtReportOn, folder: _folderLabel(l10n, next));
    container.invalidate(reportNotificationsAllowedProvider);
    final exempt = await container.read(batteryExemptProvider.future);
    if (exempt || !mounted) return;
    final wants = await showDialog<bool>(
      context: context,
      builder: (_) => const BatteryExemptionDialog(),
    );
    if (wants == true) await _askBatteryExemption();
  }

  Future<void> _askBatteryExemption() async {
    final container = _container;
    try {
      await container.read(nativeBridgeProvider).requestBatteryExemption();
    } on Object {
      // The tile stays and can be tapped again.
    }
    container.invalidate(batteryExemptProvider);
  }

  Future<void> _pickTime(DebtReportSettings s) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: s.minuteOfDay ~/ 60,
        minute: s.minuteOfDay % 60,
      ),
    );
    if (picked == null) return;
    final minute = picked.hour * 60 + picked.minute;
    final container = _container;
    await _save(s.copyWith(minuteOfDay: minute));
    if (!s.enabled) return;
    try {
      await container.read(reportPlatformProvider).schedule(
            minute,
            replace: true,
          );
    } on Object {
      // Not on Android.
    }
  }

  Future<void> _toggleFormat(
    DebtReportSettings s,
    ReportFormat format,
    bool on,
  ) async {
    final formats = {...s.formats};
    on ? formats.add(format) : formats.remove(format);
    if (formats.isEmpty) {
      _say(AppLocalizations.of(context).debtReportFormatNeedOne);
      return;
    }
    await _save(s.copyWith(formats: formats));
  }

  Future<void> _chooseFolder(DebtReportSettings s) async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    if (!await _pinIfSet()) return;
    final PickedFolder? picked;
    try {
      picked = await container.read(nativeBridgeProvider).pickFolder();
    } on Object {
      _say(l10n.debtReportFolderPickFailed);
      return;
    }
    if (picked == null) return;
    final old = s.folderUri;
    final name = picked.name.isEmpty ? l10n.debtReportFolderLabel : picked.name;
    await _save(s.copyWith(
      folderUri: picked.uri,
      folderName: name,
      folderKind: FolderKind.fromDb(picked.kind),
    ));
    await _log(AuditAction.debtReportFolder, folder: name);
    if (old != null && old != picked.uri) {
      try {
        await container.read(reportPlatformProvider).releaseFolder(old);
      } on Object {
        // An unused grant does no harm.
      }
    }
    _say(l10n.debtReportFolderChanged);
  }

  Future<void> _useDownloads(DebtReportSettings s) async {
    final l10n = AppLocalizations.of(context);
    final container = _container;
    final old = s.folderUri;
    if (old == null) return;
    if (!await _pinIfSet()) return;
    await _save(s.copyWith(clearFolder: true));
    await _log(AuditAction.debtReportFolder, folder: l10n.debtReportFolderDownloads);
    try {
      await container.read(reportPlatformProvider).releaseFolder(old);
    } on Object {
      // An unused grant does no harm.
    }
    _say(l10n.debtReportFolderChanged);
  }

  Future<void> _setNotify(DebtReportSettings s, bool on) async {
    final container = _container;
    await _save(s.copyWith(notify: on));
    if (!on) return;
    try {
      await container.read(nativeBridgeProvider).requestNotificationPermission();
    } on Object {
      // The banner says so.
    }
    container.invalidate(reportNotificationsAllowedProvider);
  }

  Future<void> _allowNotifications() async {
    final container = _container;
    final bridge = container.read(nativeBridgeProvider);
    var allowed = false;
    try {
      allowed = await bridge.requestNotificationPermission();
      // Refused for good: only the app's settings page can turn them on.
      if (!allowed) await bridge.openAppSettings();
    } on Object {
      // Nothing more to try.
    }
    container.invalidate(reportNotificationsAllowedProvider);
  }

  Future<void> _runNow() async {
    final l10n = AppLocalizations.of(context);
    final result = await runDebtReport(_container, ReportTrigger.manual);
    if (!mounted) return;
    if (result.busy) {
      _say(l10n.debtReportBusy);
      return;
    }
    final location = result.location ?? '';
    switch (result.outcome) {
      case ReportOutcome.ok:
        _say(l10n.debtReportRunDone(location));
      case ReportOutcome.fallback:
        _say(l10n.debtReportRunFallback(location));
      case ReportOutcome.failed:
        _say(l10n.debtReportRunFailed(reportProblemText(l10n, result.problem)));
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(debtReportSettingsProvider).value ??
        const DebtReportSettings();
    final status =
        ref.watch(debtReportStatusProvider).value ?? const DebtReportStatus();
    final locale = ref.watch(appLocaleProvider).languageCode;
    final now = ref.watch(clockProvider)();
    final running = ref.watch(reportRunningProvider);
    final exempt = ref.watch(batteryExemptProvider).value ?? true;
    final notificationsOn =
        ref.watch(reportNotificationsAllowedProvider).value ?? true;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final warning = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.error);
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: s.minuteOfDay ~/ 60, minute: s.minuteOfDay % 60),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final kindLabel = switch (s.folderKind) {
      FolderKind.phone => l10n.debtReportFolderKindPhone,
      FolderKind.removable => l10n.debtReportFolderKindRemovable,
      FolderKind.cloud => l10n.debtReportFolderKindCloud,
      FolderKind.other => null,
    };
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            title,
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.debtReportTitle)),
      body: ListView(
        key: const ValueKey('debt-report-settings'),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          SwitchListTile(
            key: const ValueKey('debt-report-enabled'),
            secondary: const Icon(Icons.summarize_outlined),
            title: Text(l10n.debtReportTitle),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.debtReportIntro),
                const SizedBox(height: 4),
                Text(
                  debtReportStatusLine(l10n, status, now: now, locale: locale),
                  key: const ValueKey('debt-report-status'),
                  style: status.outcome == ReportOutcome.ok
                      ? theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.primary)
                      : status.outcome == null
                          ? null
                          : theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.error),
                ),
                if (s.enabled)
                  Text(
                    l10n.debtReportNext(formatReportWhen(
                      l10n,
                      nextScheduledRun(now, s.minuteOfDay),
                      now: now,
                      locale: locale,
                    )),
                    style: muted,
                  ),
              ],
            ),
            value: s.enabled,
            onChanged: (on) => _setEnabled(s, on),
          ),
          ListTile(
            key: const ValueKey('debt-report-time'),
            leading: const Icon(Icons.schedule),
            title: Text(l10n.debtReportTimeLabel),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(time, style: theme.textTheme.titleMedium),
                Text(l10n.debtReportTimeHint),
              ],
            ),
            onTap: () => _pickTime(s),
          ),
          section(l10n.debtReportFormatsLabel),
          CheckboxListTile(
            key: const ValueKey('debt-report-xlsx'),
            secondary: const Icon(Icons.table_chart_outlined),
            title: Text(l10n.debtReportFormatXlsx),
            value: s.formats.contains(ReportFormat.xlsx),
            onChanged: (on) => _toggleFormat(s, ReportFormat.xlsx, on ?? false),
          ),
          CheckboxListTile(
            key: const ValueKey('debt-report-pdf'),
            secondary: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.debtReportFormatPdf),
            value: s.formats.contains(ReportFormat.pdf),
            onChanged: (on) => _toggleFormat(s, ReportFormat.pdf, on ?? false),
          ),
          const Divider(),
          ListTile(
            key: const ValueKey('debt-report-folder'),
            leading: Icon(
              s.usesDownloads ? Icons.download_outlined : Icons.folder_outlined,
            ),
            title: Text(l10n.debtReportFolderLabel),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kindLabel == null || s.usesDownloads
                      ? _folderLabel(l10n, s)
                      : '${_folderLabel(l10n, s)} · $kindLabel',
                  style: theme.textTheme.titleSmall,
                ),
                if (s.staysOnPhone)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      l10n.debtReportFolderOnPhone,
                      key: const ValueKey('debt-report-on-phone-warning'),
                      style: warning,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(l10n.debtReportFolderWhy, style: muted),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('debt-report-choose-folder'),
                  onPressed: () => _chooseFolder(s),
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: Text(l10n.debtReportChooseFolder),
                ),
                if (!s.usesDownloads)
                  TextButton(
                    key: const ValueKey('debt-report-use-downloads'),
                    onPressed: () => _useDownloads(s),
                    child: Text(l10n.debtReportUseDownloads),
                  ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey('debt-report-keep'),
            leading: const Icon(Icons.history),
            title: Text(l10n.debtReportKeepLabel),
            // Under the explanation, like the other day pickers: beside it,
            // it squeezes the text on a small phone at a large font.
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<int>(
                  key: const ValueKey('debt-report-keep-dropdown'),
                  value: s.keepDays,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final days in {
                      ...DebtReportSettings.keepChoices,
                      s.keepDays,
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
                    if (days != null) _save(s.copyWith(keepDays: days));
                  },
                ),
                Text(l10n.debtReportKeepHint),
              ],
            ),
          ),
          SwitchListTile(
            key: const ValueKey('debt-report-notify'),
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(l10n.debtReportNotifyLabel),
            subtitle: Text(l10n.debtReportNotifyHint),
            value: s.notify,
            onChanged: (on) => _setNotify(s, on),
          ),
          if (s.enabled && !notificationsOn)
            ListTile(
              key: const ValueKey('debt-report-notifications-blocked'),
              leading: Icon(
                Icons.notifications_off_outlined,
                color: theme.colorScheme.error,
              ),
              title: Text(l10n.debtReportNotificationsBlocked),
              subtitle: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _allowNotifications,
                  child: Text(l10n.debtReportAllowNotifications),
                ),
              ),
            ),
          if (s.enabled)
            ListTile(
              key: const ValueKey('debt-report-battery'),
              leading: Icon(
                exempt
                    ? Icons.battery_charging_full_outlined
                    : Icons.battery_alert_outlined,
              ),
              title: Text(
                exempt
                    ? l10n.debtReportBatteryOk
                    : l10n.debtReportBatteryTitle,
              ),
              subtitle: exempt
                  ? null
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.debtReportBatteryHint),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const ValueKey('debt-report-battery-button'),
                            onPressed: _askBatteryExemption,
                            child: Text(l10n.debtReportBatteryButton),
                          ),
                        ),
                      ],
                    ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.icon(
              key: const ValueKey('debt-report-run-now'),
              onPressed: running ? null : _runNow,
              icon: running
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(
                running ? l10n.debtReportRunning : l10n.debtReportRunNow,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
