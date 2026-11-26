import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/constants/settings_keys.dart';
import 'core/providers.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'features/settings/storage_providers.dart';

/// What the app starts from: the open database and the two settings the
/// first frame needs.
class AppStart {
  const AppStart({
    required this.database,
    required this.locale,
    required this.setupDone,
  });

  final AppDatabase database;
  final Locale locale;
  final bool setupDone;

  static Future<AppStart> load(AppDatabase database) async {
    final settings = SettingsRepository(database.db);
    return AppStart(
      database: database,
      locale: Locale(await settings.getString(SettingsKeys.appLanguage)),
      setupDone: await settings.getBool(SettingsKeys.setupDone),
    );
  }
}

/// The top of the app: one [ProviderScope] on one database — and the way to
/// START OVER on another one after a restore.
///
/// [_restart] swaps in a new [ProviderScope] under a new key: every provider
/// is created again (the card-code cipher, which keeps the keys it loaded
/// for the life of its scope, reads the restored ones), and the whole app
/// below — navigator, screens, PIN sessions — is built from nothing, as at
/// a cold start.
class SouqiRoot extends StatefulWidget {
  const SouqiRoot({super.key, required this.start});

  final AppStart start;

  @override
  State<SouqiRoot> createState() => _SouqiRootState();
}

class _SouqiRootState extends State<SouqiRoot> {
  late AppStart _start = widget.start;
  Key _scope = UniqueKey();
  AppRestartNotice? _notice;

  Future<void> _restart(AppDatabase database, AppRestartNotice? notice) async {
    final next = await AppStart.load(database);
    if (!mounted) return;
    setState(() {
      _start = next;
      _notice = notice;
      _scope = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: _scope,
      overrides: [
        databaseProvider.overrideWithValue(_start.database),
        appLocaleProvider.overrideWith(() => AppLocaleNotifier(_start.locale)),
        setupDoneProvider
            .overrideWith(() => SetupDoneNotifier(_start.setupDone)),
        // Only the real app sweeps old invoices and stale share files.
        housekeepingOnStartProvider.overrideWithValue(true),
        appRestartProvider.overrideWithValue(_restart),
        appStartNoticeProvider.overrideWithValue(_notice),
      ],
      child: const SouqiApp(),
    );
  }
}
