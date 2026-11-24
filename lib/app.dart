import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'features/home/home_screen.dart';
import 'features/setup/setup_screen.dart';
import 'l10n/generated/app_localizations.dart';

const _primaryGreen = Color(0xFF12332B);
const _warmAccent = Color(0xFFE2A13B);
const _cream = Color(0xFFFAF6EC);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: _primaryGreen).copyWith(
    primary: _primaryGreen,
    secondary: _warmAccent,
    surface: _cream,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: _cream,
    fontFamily: 'Tajawal',
    appBarTheme: const AppBarTheme(
      backgroundColor: _primaryGreen,
      foregroundColor: Colors.white,
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _warmAccent,
      foregroundColor: _primaryGreen,
    ),
  );
}

class SouqiApp extends ConsumerWidget {
  const SouqiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    final setupDone = ref.watch(setupDoneProvider);
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
      theme: buildTheme(),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
    );
  }
}
