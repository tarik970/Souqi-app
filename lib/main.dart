import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/features.dart';
import 'core/constants/settings_keys.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';

Future<void> main() async {
  assert(featureFlagsConsistent,
      'accounts and debt feature flags require customersEnabled');
  WidgetsFlutterBinding.ensureInitialized();

  final appDb = await AppDatabase.open();
  final settings = SettingsRepository(appDb.db);
  final language = await settings.getString(SettingsKeys.appLanguage);

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(appDb),
        appLocaleProvider
            .overrideWith(() => AppLocaleNotifier(Locale(language))),
      ],
      child: const SouqiApp(),
    ),
  );
}
