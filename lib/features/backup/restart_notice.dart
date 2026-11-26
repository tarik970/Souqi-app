import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';

/// Says, once, over the first screen of a start that followed a restore —
/// or an activation — how it went: the screen that started it is gone by
/// then.
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
    final (icon, title, text) = switch (notice) {
      AppRestartNotice.restored => (
          Icons.check_circle_outline,
          l10n.restoreDoneTitle,
          l10n.restoreDoneText,
        ),
      AppRestartNotice.restoreFailed => (
          Icons.error_outline,
          l10n.restoreFailedTitle,
          l10n.restoreFailedText,
        ),
      AppRestartNotice.activated => (
          Icons.verified_outlined,
          l10n.licenseActivatedTitle,
          l10n.licenseActivatedText,
        ),
    };
    return AlertDialog(
      key: const ValueKey('restart-notice'),
      icon: Icon(icon),
      title: Text(title),
      scrollable: true,
      content: Text(text),
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
