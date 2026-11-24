import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:souqi/app.dart';
import 'package:souqi/core/providers.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/db_test_utils.dart';

/// Pumps the real [SouqiApp] so missing localization delegates or theme
/// misconfiguration crash `flutter test` instead of the phone.
void main() {
  setUpAll(sqfliteFfiInit);

  Future<void> pumpApp(WidgetTester tester, Locale locale) async {
    final db = await tester.runAsync(openTestDb);
    addTearDown(() => db!.close());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db!),
          appLocaleProvider.overrideWith(() => AppLocaleNotifier(locale)),
        ],
        child: const SouqiApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders in Arabic, RTL, without exceptions', (tester) async {
    await pumpApp(tester, const Locale('ar'));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('سوقي'), findsOneWidget);
    final scaffoldContext = tester.element(find.byType(Scaffold));
    expect(Directionality.of(scaffoldContext), TextDirection.rtl);
  });

  testWidgets('renders in English, LTR, without exceptions', (tester) async {
    await pumpApp(tester, const Locale('en'));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('Souqi'), findsOneWidget);
    final scaffoldContext = tester.element(find.byType(Scaffold));
    expect(Directionality.of(scaffoldContext), TextDirection.ltr);
  });
}
