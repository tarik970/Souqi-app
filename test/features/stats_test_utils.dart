import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/features/debts/debt_providers.dart';
import 'package:souqi/features/stats/stats_providers.dart';
import 'package:souqi/features/stats/stats_screen.dart';

/// THE STATISTICS HAVE FINISHED LOADING: the sales report is on screen, and
/// the debt card under it — where it is built — has read what it shows.
///
/// Call it after pumping a [StatsScreen], instead of a fixed number of
/// frames. The report is nine queries, and how long they take depends on
/// what else the machine is doing: a fixed wait that is enough for one file
/// alone is not always enough in the whole suite. Until the report is there
/// the page is a spinner — there is no list to scroll, "is not shown" is
/// true of everything, and a test that ends there leaves its queries to find
/// the database closed.
///
/// Nothing is read here that the screen did not ask for itself: a provider
/// the page never touched (the debt figures behind the PIN, or with the
/// ledger off) is not started by waiting for it.
Future<void> statsLoaded(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(StatsScreen)),
  );
  // Built is enough: on a small screen with the keyboard up the headline
  // may be under the fold.
  final headline = find.byKey(
    const ValueKey('stats-total-value'),
    skipOffstage: false,
  );

  bool idle<T>(FutureProvider<T> provider) =>
      !container.read(provider.exists) || !container.read(provider).isLoading;

  bool loaded() =>
      headline.evaluate().isNotEmpty &&
      idle(statsReportProvider) &&
      idle(debtRequirePinProvider) &&
      idle(debtStatsProvider);

  // A few rounds in a row: the debt card asks whether it is locked first,
  // and only reads its figures on the frame after that answer.
  var calm = 0;
  for (var i = 0; i < 1500 && calm < 3; i++) {
    await tester.pump(const Duration(milliseconds: 16));
    // The database only moves in real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    calm = loaded() ? calm + 1 : 0;
  }
  if (calm < 3) {
    final report = container.read(statsReportProvider.exists)
        ? '${container.read(statsReportProvider)}'
        : 'never asked for';
    fail('The statistics did not finish loading. The report: $report');
  }
  await tester.pump();
}
