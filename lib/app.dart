import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/providers.dart';
import 'features/home/home_screen.dart';
import 'features/settings/storage_providers.dart';
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
      // Above every screen: the one-off startup housekeeping and the
      // "optimizing…" indicator it (or a delete) may raise.
      builder: (context, child) =>
          _Housekeeping(child: child ?? const SizedBox.shrink()),
      home: setupDone ? const HomeScreen() : const SetupScreen(),
    );
  }
}

/// Starts the per-launch housekeeping and shows a small pill while the
/// database is being rewritten.
///
/// It sits in [MaterialApp.builder] so the pill survives navigation: the
/// VACUUM that follows a big delete outlives the screen that started it.
class _Housekeeping extends ConsumerStatefulWidget {
  const _Housekeeping({required this.child});

  final Widget child;

  @override
  ConsumerState<_Housekeeping> createState() => _HousekeepingState();
}

class _HousekeepingState extends ConsumerState<_Housekeeping> {
  @override
  void initState() {
    super.initState();
    if (!ref.read(housekeepingOnStartProvider)) return;
    // After the first frame: the seller sees the app, not a white screen,
    // while old invoices and stale share files are cleared out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(housekeepingProvider.notifier).runOnAppStart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final optimizing = ref.watch(housekeepingProvider);
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        widget.child,
        if (optimizing)
          Padding(
            padding: const EdgeInsets.only(bottom: 32),
            child: _OptimizingPill(
              label: AppLocalizations.of(context).optimizingStorage,
            ),
          ),
      ],
    );
  }
}

class _OptimizingPill extends StatelessWidget {
  const _OptimizingPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      shape: const StadiumBorder(),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(color: scheme.onPrimary, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
