import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../logging/error_log.dart';

/// What a screen shows when the data behind it could not be loaded.
///
/// The shop gets a sentence it can act on — go back, open the page again,
/// send the error log — and the error itself goes to the local error log
/// (once per error, not once per frame). The raw exception text is shown
/// under it in DEBUG builds only: on a customer's phone it is noise, and it
/// may quote rows of the database.
class LoadErrorView extends StatefulWidget {
  const LoadErrorView(this.error, [this.stackTrace]) : super(key: null);

  final Object error;
  final StackTrace? stackTrace;

  @override
  State<LoadErrorView> createState() => _LoadErrorViewState();
}

class _LoadErrorViewState extends State<LoadErrorView> {
  @override
  void initState() {
    super.initState();
    _report();
  }

  @override
  void didUpdateWidget(LoadErrorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.error, widget.error)) _report();
  }

  void _report() =>
      reportError(widget.error, widget.stackTrace, context: 'page load');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.loadErrorMessage,
              key: const ValueKey('load-error'),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 12),
              Text(
                '${widget.error}',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
