import 'package:material_ui/material_ui.dart';

/// The small coloured heading of a group of invoice settings.
class SettingsSectionTitle extends StatelessWidget {
  const SettingsSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// A grey line of explanation under a setting.
class SettingsHint extends StatelessWidget {
  const SettingsHint(this.text, {super.key, this.warning = false});

  final String text;

  /// Said in the error colour: something will not work as the owner hopes.
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: warning ? theme.colorScheme.error : theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// A control on its own line, at the start edge.
class SettingsPadded extends StatelessWidget {
  const SettingsPadded({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: child,
        ),
      );
}
