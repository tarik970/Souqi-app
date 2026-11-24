import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/features.dart';
import 'core/constants/settings_keys.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'features/settings/storage_providers.dart';

Future<void> main() async {
  assert(featureFlagsConsistent,
      'accounts and debt feature flags require customersEnabled');
  WidgetsFlutterBinding.ensureInitialized();

  final appDb = await AppDatabase.open();
  final settings = SettingsRepository(appDb.db);
  final language = await settings.getString(SettingsKeys.appLanguage);
  final setupDone = await settings.getBool(SettingsKeys.setupDone);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(appDb),
        appLocaleProvider
            .overrideWith(() => AppLocaleNotifier(Locale(language))),
        setupDoneProvider.overrideWith(() => SetupDoneNotifier(setupDone)),
        // Only the real app sweeps old invoices and stale share files.
        housekeepingOnStartProvider.overrideWithValue(true),
      ],
      child: const SouqiApp(),
    ),
  );
}
