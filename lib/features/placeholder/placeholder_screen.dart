import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';

/// Temporary screen for features that arrive in later phases.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text(
          AppLocalizations.of(context).comingSoon,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}
