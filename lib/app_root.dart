import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'config/features.dart';
import 'core/constants/settings_keys.dart';
import 'core/licensing/license_service.dart';
import 'core/platform/license_platform.dart';
import 'core/providers.dart';
import 'core/security/code_cipher.dart';
import 'core/security/secure_key_store.dart';
import 'data/db/app_database.dart';
import 'data/repositories/settings_repository.dart';
import 'features/settings/storage_providers.dart';

/// What the app starts from: the open database, the LICENSE CHECK of this
/// start, and the two settings the first frame needs.
class AppStart {
  const AppStart({
    required this.database,
    required this.license,
    required this.locale,
    required this.setupDone,
    this.keys = const SecureStorageKeyStore(),
    this.platform = const MethodChannelLicensePlatform(),
  });

  final AppDatabase database;

  /// The license service of this database, already started: the stored
  /// activation code is verified, the trial and the clock are read, and
  /// `featureOn` answers by the result. There is no app without it.
  final LicenseService license;
  final Locale locale;
  final bool setupDone;

  /// What [license] reads the phone through — kept, so a start-over uses
  /// the same.
  final SecretKeyStore keys;
  final LicensePlatform platform;

  /// [keys] and [platform] are the phone's own; tests pass fakes.
  static Future<AppStart> load(
    AppDatabase database, {
    SecretKeyStore keys = const SecureStorageKeyStore(),
    LicensePlatform platform = const MethodChannelLicensePlatform(),
  }) async {
    // THE LICENSE CHECK OF EVERY APP START — and of every start-over after
    // a restore: a restored database never brings a license with it, so
    // this is where the phone's own is put back, or found missing.
    final license = LicenseService(
      db: database.db,
      keys: keys,
      platform: platform,
    );
    final status = await license.start();
    FeatureGate.apply(status.featureMask);

    final settings = SettingsRepository(database.db);
    return AppStart(
      database: database,
      license: license,
      locale: Locale(await settings.getString(SettingsKeys.appLanguage)),
      setupDone: await settings.getBool(SettingsKeys.setupDone),
      keys: keys,
      platform: platform,
    );
  }
}

/// The top of the app: one [ProviderScope] on one database — and the way to
/// START OVER on another one after a restore, or on the same one after an
/// activation.
///
/// [_restart] swaps in a new [ProviderScope] under a new key: every provider
/// is created again (the card-code cipher, which keeps the keys it loaded
/// for the life of its scope, reads the restored ones; every `featureOn` is
/// asked again with the new license), and the whole app below — navigator,
/// screens, PIN sessions — is built from nothing, as at a cold start.
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
    final next = await AppStart.load(
      database,
      keys: _start.keys,
      platform: _start.platform,
    );
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
        // Licensing is ON in the app: every repository and every output
        // asks this service before it sells, prints or writes a debt.
        licenseServiceProvider.overrideWithValue(_start.license),
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
