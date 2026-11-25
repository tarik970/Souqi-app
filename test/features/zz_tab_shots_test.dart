// TEMPORARY: screenshots of the customer page tabs. Deleted after use.
import 'dart:io';

import 'package:flutter/services.dart';
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

void main() {
  final out = Platform.environment['SHOTS_DIR']!;

  setUpAll(() async {
    sqfliteFfiInit();
    Future<ByteData> bytes(String path) async =>
        ByteData.view((await File(path).readAsBytes()).buffer);
    final tajawal = FontLoader('Tajawal')
      ..addFont(bytes('assets/fonts/Tajawal-Regular.ttf'))
      ..addFont(bytes('assets/fonts/Tajawal-Medium.ttf'))
      ..addFont(bytes('assets/fonts/Tajawal-Bold.ttf'));
    await tajawal.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(bytes(
          r'C:\flutter\src\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf'));
    await icons.load();
  });

  Future<void> settle(WidgetTester tester, [int rounds = 12]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
    }
    await tester.pump();
  }

  for (final locale in ['ar', 'en']) {
    for (final system in Brightness.values) {
      testWidgets('shot $locale ${system.name}', (tester) async {
        final database = await tester.runAsync(openTestDb) as AppDatabase;
        addTearDown(database.close);
        final customer = await tester.runAsync(
          () => CustomerRepository(database.db).insert(
              const Customer(name: 'أحمد الحسن', phone: '0944 123 456')),
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
        await settle(tester, 40);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              Uri.file('$out\\tabs_${locale}_${system.name}_details.png')),
        );
        await tester.tap(find.byKey(const ValueKey('customer-tab-account')));
        await settle(tester, 40);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              Uri.file('$out\\tabs_${locale}_${system.name}_account.png')),
        );
      });
    }
  }
}
