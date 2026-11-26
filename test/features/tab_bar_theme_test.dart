import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/app.dart';
import 'package:souqi/core/providers.dart';
import 'package:souqi/data/db/app_database.dart';
import 'package:souqi/data/repositories/customer_repository.dart';
import 'package:souqi/domain/models/customer.dart';
import 'package:souqi/features/customers/customer_detail_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../data/db_test_utils.dart';

/// The tabs of the app, as the phone draws them: the real [SouqiApp] with its
/// own theme, in Arabic and in English, with the system in light and in dark
/// mode.
///
/// The customer page is the only screen with a TabBar. Its labels were once
/// written in the colour of the app bar they sit on; these tests read the
/// colours that are actually painted and hold them to WCAG AA (4.5:1).
void main() {
  setUpAll(sqfliteFfiInit);

  const green = Color(0xFF12332B);
  const gold = Color(0xFFE2A13B);
  const cream = Color(0xFFFAF6EC);
  const details = ValueKey('customer-tab-details');
  const account = ValueKey('customer-tab-account');

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  /// Long enough for a page to slide in or the indicator to cross the bar.
  Future<void> animated(WidgetTester tester) async {
    await settle(tester, 28);
    for (var i = 0; i < 20 && tester.binding.transientCallbackCount > 0; i++) {
      await settle(tester, 4);
    }
  }

  /// WCAG contrast of [foreground] written on [background]; a translucent
  /// foreground is blended first, as the screen does.
  double contrast(Color foreground, Color background) {
    final a = Color.alphaBlend(foreground, background).computeLuminance();
    final b = background.computeLuminance();
    return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
  }

  /// The colour the label of the tab with [key] is painted in.
  Color labelColor(WidgetTester tester, Key key) => tester
      .widget<RichText>(
        find.descendant(of: find.byKey(key), matching: find.byType(RichText)),
      )
      .text
      .style!
      .color!;

  /// The line under the selected tab, as painted: its colour, its thickness
  /// and the stretch of screen it covers.
  ({Color color, double thickness, double left, double right}) indicator(
    WidgetTester tester,
  ) {
    final paint = find.descendant(
      of: find.byType(TabBar),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            '${widget.painter.runtimeType}'.contains('IndicatorPainter'),
      ),
    );
    final box = tester.renderObject<RenderBox>(paint);
    Offset? from;
    Offset? to;
    Paint? stroke;
    // The same painter draws the hairline along the bottom of the bar first
    // and the indicator over it: the indicator is the last line.
    expect(
      box,
      paints
        ..everything((method, arguments) {
          if (method == #drawLine) {
            from = arguments[0] as Offset;
            to = arguments[1] as Offset;
            stroke = arguments[2] as Paint;
          }
          return true;
        }),
    );
    final a = box.localToGlobal(from!).dx;
    final b = box.localToGlobal(to!).dx;
    // A square cap: the line reaches half its thickness past both ends.
    final cap = stroke!.strokeWidth / 2;
    return (
      color: stroke!.color,
      thickness: stroke!.strokeWidth,
      left: math.min(a, b) - cap,
      right: math.max(a, b) + cap,
    );
  }

  /// Checks the gold line: 3 px, and exactly as wide as the tab with [key] —
  /// half the bar, there being two tabs.
  void expectIndicatorUnder(WidgetTester tester, Key key) {
    final line = indicator(tester);
    final bar = tester.getRect(find.byType(TabBar));
    final center = tester.getCenter(find.byKey(key)).dx;
    // The painted colour may be a different Color type (another colour
    // space or float precision) from the constant: compare the 8-bit ARGB.
    expect(line.color.toARGB32(), gold.toARGB32());
    expect(line.thickness, 3);
    expect(line.left, moreOrLessEquals(center - bar.width / 4, epsilon: 0.5));
    expect(line.right, moreOrLessEquals(center + bar.width / 4, epsilon: 0.5));
  }

  for (final locale in ['ar', 'en']) {
    for (final system in Brightness.values) {
      testWidgets(
          'the customer page: white labels and a gold line on the green bar '
          '($locale, system ${system.name})', (tester) async {
        final database = await tester.runAsync(openTestDb) as AppDatabase;
        addTearDown(database.close);
        final customer = await tester.runAsync(
          () => CustomerRepository(database.db)
              .insert(const Customer(name: 'Ahmad Hasan')),
        );
        tester.view.physicalSize = const Size(720, 1280);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        tester.platformDispatcher.platformBrightnessTestValue = system;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              databaseProvider.overrideWithValue(database),
              appLocaleProvider
                  .overrideWith(() => AppLocaleNotifier(Locale(locale))),
              setupDoneProvider.overrideWith(() => SetupDoneNotifier(true)),
            ],
            child: const SouqiApp(),
          ),
        );
        await settle(tester);
        tester.state<NavigatorState>(find.byType(Navigator).first).push(
              MaterialPageRoute<void>(
                builder: (_) => CustomerDetailScreen(customerId: customer!),
              ),
            );
        await animated(tester);
        expect(tester.takeException(), isNull);

        // What the tabs are painted on: the green app bar.
        final bar = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(AppBar),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(bar.color, green);

        void expectSelected(Key selected, Key other) {
          expect(labelColor(tester, selected), Colors.white);
          expect(labelColor(tester, other), Colors.white70);
          for (final key in [selected, other]) {
            expect(
              contrast(labelColor(tester, key), green),
              greaterThanOrEqualTo(4.5),
            );
          }
          expectIndicatorUnder(tester, selected);
        }

        expectSelected(details, account);
        await tester.tap(find.byKey(account));
        await animated(tester);
        expect(tester.takeException(), isNull);
        expectSelected(account, details);
      });
    }
  }

  testWidgets(
      'a TabBar on the cream surface: green and gray labels, the same gold '
      'line', (tester) async {
    const first = ValueKey('first');
    const second = ValueKey('second');
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const DefaultTabController(
          length: 2,
          child: Scaffold(
            body: TabBarTheme(
              data: surfaceTabBarTheme,
              child: TabBar(
                tabs: [
                  Tab(key: first, text: 'One'),
                  Tab(key: second, text: 'Two'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor ??
          Theme.of(tester.element(find.byType(Scaffold)))
              .scaffoldBackgroundColor,
      cream,
    );
    expect(labelColor(tester, first), green);
    expect(labelColor(tester, second), isNot(green));
    for (final key in [first, second]) {
      expect(
        contrast(labelColor(tester, key), cream),
        greaterThanOrEqualTo(4.5),
      );
    }
    expectIndicatorUnder(tester, first);
  });
}
