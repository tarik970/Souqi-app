import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../config/features.dart';
import '../../../core/platform/native_bridge.dart';
import '../../../core/platform/report_platform.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../invoice/invoice_providers.dart';
import '../debt_providers.dart';
import '../debtors_screen.dart';
import 'report_providers.dart';
import 'report_settings.dart';

/// What the report notification asks for, done inside the app.
///
/// "Share" and "Open folder" come back INTO the app first and are then
/// opened from here through `nativeBridgeProvider` — so they are announced
/// to the PIN locks like every other external action, and the seller gets
/// the usual two minutes to come back from the share sheet or the file
/// manager. Both go through the debt gate first: the files hold the same
/// names and balances as the debtors list.
Future<void> handleReportLaunch(
  BuildContext context,
  ReportLaunchAction action,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  // The debtors list and the report files belong to the debt ledger; the
  // folder is also where the daily BACKUP goes, with the ledger off.
  final debtOn = featureOn(Feature.debt);
  if (!debtOn &&
      !(action == ReportLaunchAction.openFolder &&
          featureOn(Feature.backup))) {
    return;
  }
  final messenger = ScaffoldMessenger.maybeOf(context);
  final l10n = AppLocalizations.of(context);
  void say(String text) => messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  switch (action) {
    case ReportLaunchAction.openDebtors:
      await openDebtors(context);
    case ReportLaunchAction.share:
      if (!await requireDebtAccess(context)) return;
      container.invalidate(debtReportStatusProvider);
      final status = await container.read(debtReportStatusProvider.future);
      final files = [
        for (final path in status.files)
          if (File(path).existsSync())
            ShareableFile(
              path: path,
              mimeType: path.endsWith('.pdf')
                  ? ReportFormat.pdf.mimeType
                  : ReportFormat.xlsx.mimeType,
            ),
      ];
      if (files.isEmpty) {
        say(l10n.debtReportFilesGone);
        return;
      }
      await container.read(nativeBridgeProvider).shareFiles(files);
    case ReportLaunchAction.openFolder:
      if (debtOn && !await requireDebtAccess(context)) return;
      container.invalidate(debtReportStatusProvider);
      final status = await container.read(debtReportStatusProvider.future);
      final opened = await container
          .read(nativeBridgeProvider)
          .openFolder(status.savedToFolderUri);
      if (!opened) say(l10n.debtReportFolderCannotOpen);
  }
}

/// Listens for the report notification being tapped — at launch, and while
/// the app is already running — and for the background job finishing (the
/// status under the setting is then refreshed).
///
/// Sits in `MaterialApp.builder`, above the Navigator: [navigatorKey] gives
/// it a context under it.
class ReportLaunchListener extends ConsumerStatefulWidget {
  const ReportLaunchListener({
    super.key,
    required this.navigatorKey,
    required this.enabled,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;

  /// False in widget tests, which have no Android side.
  final bool enabled;
  final Widget child;

  @override
  ConsumerState<ReportLaunchListener> createState() =>
      _ReportLaunchListenerState();
}

class _ReportLaunchListenerState extends ConsumerState<ReportLaunchListener> {
  bool _handling = false;

  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    final platform = ref.read(reportPlatformProvider);
    platform.setListener(
      onLaunchAction: _take,
      onJobFinished: () {
        if (mounted) ref.invalidate(debtReportStatusProvider);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _take());
  }

  Future<void> _take() async {
    if (_handling || !mounted) return;
    _handling = true;
    try {
      final ReportLaunchAction? action;
      try {
        action = await ref.read(reportPlatformProvider).takeLaunchAction();
      } on Object {
        return;
      }
      if (action == null || !mounted) return;
      // First launch: let the home screen come up under it.
      await WidgetsBinding.instance.endOfFrame;
      final context = widget.navigatorKey.currentState?.overlay?.context;
      if (context == null || !context.mounted) return;
      await handleReportLaunch(context, action);
    } finally {
      _handling = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
