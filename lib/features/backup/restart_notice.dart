import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Says, once, over the first screen of a start that followed a restore,
/// how it went — the screen that started the restore is gone by then.
class RestartNoticeListener extends ConsumerStatefulWidget {
  const RestartNoticeListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<RestartNoticeListener> createState() =>
      _RestartNoticeListenerState();
}

class _RestartNoticeListenerState extends ConsumerState<RestartNoticeListener> {
  @override
  void initState() {
    super.initState();
    final notice = ref.read(appStartNoticeProvider);
    if (notice == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = widget.navigatorKey.currentContext;
      if (!mounted || context == null) return;
      showDialog<void>(
        context: context,
        builder: (_) => RestartNoticeDialog(notice: notice),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class RestartNoticeDialog extends StatelessWidget {
  const RestartNoticeDialog({super.key, required this.notice});

  final AppRestartNotice notice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final restored = notice == AppRestartNotice.restored;
    return AlertDialog(
      key: const ValueKey('restart-notice'),
      icon: Icon(restored ? Icons.check_circle_outline : Icons.error_outline),
      title: Text(restored ? l10n.restoreDoneTitle : l10n.restoreFailedTitle),
      scrollable: true,
      content: Text(restored ? l10n.restoreDoneText : l10n.restoreFailedText),
      actions: [
        FilledButton(
          key: const ValueKey('restart-notice-ok'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
