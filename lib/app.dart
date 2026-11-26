import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/money/money_format.dart';
import 'core/providers.dart';
import 'features/backup/restart_notice.dart';
import 'features/debts/report/report_launch.dart';
import 'features/debts/report/report_providers.dart';
import 'features/home/home_screen.dart';
import 'features/security/pin_session.dart';
import 'features/settings/storage_providers.dart';
import 'features/setup/setup_screen.dart';
import 'l10n/generated/app_localizations.dart';

const _primaryGreen = Color(0xFF12332B);
const _warmAccent = Color(0xFFE2A13B);
const _cream = Color(0xFFFAF6EC);

/// What is written on the green app bar: the title, its icons, its tabs.
const _onGreen = Colors.white;

/// The gold line under the selected tab: 3 px, as wide as the tab.
const _tabIndicator = UnderlineTabIndicator(
  borderSide: BorderSide(color: _warmAccent, width: 3),
);

/// Tabs in the green app bar — where every TabBar of the app sits, so this is
/// the app-wide [ThemeData.tabBarTheme].
///
/// Material 3 would write the selected label in `primary`, which here is the
/// colour of the bar itself. White is 13.7:1 against the green and the
/// unselected 70 % white 7.5:1.
const _appBarTabs = TabBarThemeData(
  labelColor: _onGreen,
  unselectedLabelColor: Colors.white70,
  indicator: _tabIndicator,
  indicatorSize: TabBarIndicatorSize.tab,
);

/// Tabs on the cream surface instead of the app bar. A theme cannot see what
/// a TabBar is painted on, so such a TabBar has to ask for this one:
///
///     TabBarTheme(data: surfaceTabBarTheme, child: TabBar(...))
///
/// Green on cream is 12.6:1, the gray 5.7:1.
const surfaceTabBarTheme = TabBarThemeData(
  labelColor: _primaryGreen,
  unselectedLabelColor: Color(0xFF616161),
  indicator: _tabIndicator,
  indicatorSize: TabBarIndicatorSize.tab,
);

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
      foregroundColor: _onGreen,
    ),
    tabBarTheme: _appBarTabs,
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _warmAccent,
      foregroundColor: _primaryGreen,
    ),
  );
}

/// The app's Navigator, for what is opened from outside any screen: the
/// daily debt report's notification. One per ProviderScope, so a test that
/// pumps the app twice never hands the old Navigator to the new app.
final appNavigatorKeyProvider =
    Provider<GlobalKey<NavigatorState>>((ref) => GlobalKey<NavigatorState>());

class SouqiApp extends ConsumerWidget {
  const SouqiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider);
    final setupDone = ref.watch(setupDoneProvider);
    final navigatorKey = ref.watch(appNavigatorKeyProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
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
      // "optimizing…" indicator it (or a delete) may raise — and the watch
      // that locks everything the PIN opened when the app is left.
      builder: (context, child) => PinSessionObserver(
        child: ReportLaunchListener(
          navigatorKey: navigatorKey,
          // Like the housekeeping: only the real app has an Android side.
          enabled: ref.watch(housekeepingOnStartProvider),
          // After a restore the app starts over; this says how it went.
          child: RestartNoticeListener(
            navigatorKey: navigatorKey,
            child: _Housekeeping(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final container = ProviderScope.containerOf(context, listen: false);
      await ref.read(housekeepingProvider.notifier).runOnAppStart();
      // Then the daily debt report: re-plan it, and make the one that was
      // missed (the catch-up rule).
      try {
        await debtReportOnAppStart(container);
      } on Object {
        // The next start tries again; the status line says what happened.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final optimizing = ref.watch(housekeepingProvider).optimizing;
    final retention = ref.watch(retentionNoticeProvider);
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
          )
        // One or the other: the VACUUM that may follow the sweep is the
        // more urgent thing to say while it is running.
        else if (retention != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 32),
            child: _RetentionNotice(),
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

/// The one line the retention sweep gets: how many old invoices it dropped.
///
/// A pill rather than a SnackBar, because the sweep finishes before any
/// screen is settled and it must not depend on which Scaffold happens to be
/// up. It clears itself after a few seconds, or on a tap.
class _RetentionNotice extends ConsumerStatefulWidget {
  const _RetentionNotice();

  @override
  ConsumerState<_RetentionNotice> createState() => _RetentionNoticeState();
}

class _RetentionNoticeState extends ConsumerState<_RetentionNotice> {
  static const Duration _visible = Duration(seconds: 6);

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_visible, _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    ref.read(retentionNoticeProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final deleted = ref.watch(retentionNoticeProvider) ?? 0;
    final days = ref.watch(retentionDaysProvider).value ?? 0;
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primary,
      shape: const StadiumBorder(),
      elevation: 4,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _dismiss,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_delete_outlined,
                  size: 16, color: scheme.onPrimary),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  l10n.retentionNotice(
                    formatMinor(deleted, decimals: 0, locale: locale),
                    formatMinor(days, decimals: 0, locale: locale),
                  ),
                  style: TextStyle(color: scheme.onPrimary, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
