import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'l10n/generated/app_localizations.dart';

class SouqiApp extends ConsumerWidget {
  const SouqiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      // The generated AppLocalizations.localizationsDelegates list carries the
      // flutter_localizations delegates, which provide the deprecated
      // package:flutter/material.dart localization types — material_ui
      // widgets cannot see those and crash with "No MaterialLocalizations
      // found". Use material_ui's own global delegates instead.
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2E7D32),
        fontFamily: 'Tajawal',
      ),
      home: const _HomePlaceholder(),
    );
  }
}

class _HomePlaceholder extends StatelessWidget {
  const _HomePlaceholder();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            l10n.homePlaceholder,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
