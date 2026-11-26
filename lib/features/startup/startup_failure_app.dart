import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../app.dart' show buildTheme;
import '../../core/logging/error_log.dart';
import '../../core/logging/error_reporting.dart';
import '../../core/platform/native_bridge.dart';
import '../../data/db/app_database.dart';
import '../../l10n/generated/app_localizations.dart';

/// What the app shows when it COULD NOT START: the database did not open, or
/// the first read from it failed. Without this the shop would look at a
/// white screen for ever and conclude that everything is gone.
///
/// It says three things — the data is still on the phone, try again, and how
/// to send the error log to the developer — and offers nothing destructive:
/// there is no "reset" here, on purpose. No database and no providers are
/// available at this point, so it stands on its own: the phone's language
/// (Arabic unless it is English), and the share sheet reached directly.
class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({
    super.key,
    required this.error,
    required this.onRetry,
    this.shareLog = shareErrorLogDirectly,
  });

  final Object error;

  /// Runs the app's start again.
  final Future<void> Function() onRetry;

  /// Hands the error log to the share sheet. Returns false when it could
  /// not be opened.
  final Future<bool> Function() shareLog;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      // The phone's language when it is one of the app's, Arabic otherwise
      // (the app's default) — the saved setting cannot be read here.
      localeResolutionCallback: (device, supported) =>
          device?.languageCode == 'en' ? const Locale('en') : const Locale('ar'),
      theme: buildTheme(),
      home: _StartupFailureScreen(
        error: error,
        onRetry: onRetry,
        shareLog: shareLog,
      ),
    );
  }
}

class _StartupFailureScreen extends StatefulWidget {
  const _StartupFailureScreen({
    required this.error,
    required this.onRetry,
    required this.shareLog,
  });

  final Object error;
  final Future<void> Function() onRetry;
  final Future<bool> Function() shareLog;

  @override
  State<_StartupFailureScreen> createState() => _StartupFailureScreenState();
}

class _StartupFailureScreenState extends State<_StartupFailureScreen> {
  bool _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    // On success the whole app replaces this one (runApp); on failure a
    // new copy of this screen does.
    await widget.onRetry();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _share() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final opened = await widget.shareLog();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!opened) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorLogShareFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final newer = widget.error is NewerDatabaseException;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.report_problem_outlined,
                  size: 64,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.startupFailedTitle,
                  key: const ValueKey('startup-failed-title'),
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  newer ? l10n.startupFailedNewerData : l10n.startupFailedBody,
                  key: const ValueKey('startup-failed-body'),
                  style: theme.textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  key: const ValueKey('startup-retry'),
                  onPressed: _busy ? null : _retry,
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.retry),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('startup-share-log'),
                  onPressed: _busy ? null : _share,
                  icon: const Icon(Icons.ios_share),
                  label: Text(l10n.errorLogShare),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Share error log" without a `ProviderScope`: writes the export into the
/// share staging folder and opens the share sheet through the bridge
/// itself. Returns false when nothing could be opened.
Future<bool> shareErrorLogDirectly() async {
  try {
    await ErrorLog.instance.flush();
    final now = DateTime.now();
    final export = await ErrorLog.export(await errorLogDirectory());
    final header = errorLogHeader(
      appVersion: ErrorLog.instance.appVersion,
      createdAt: now,
      errorCount: export.entryCount,
      facts: const {'State': 'the app could not start'},
    );
    final cache = await getTemporaryDirectory();
    final directory =
        await Directory(p.join(cache.path, 'share')).create(recursive: true);
    final file = await File(p.join(directory.path, errorLogFileName(now)))
        .writeAsBytes(
      Uint8List.fromList(utf8.encode('$header\n${export.text}')),
      flush: true,
    );
    await const MethodChannelNativeBridge().shareFile(
      filePath: file.path,
      mimeType: 'text/plain',
    );
    return true;
  } on Object catch (error, stack) {
    reportError(error, stack, context: 'share error log');
    return false;
  }
}
