import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/app_database.dart';
import '../data/repositories/settings_repository.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('databaseProvider must be overridden in main()'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider).db),
);

class AppLocaleNotifier extends Notifier<Locale> {
  AppLocaleNotifier([this._initial = const Locale('ar')]);

  final Locale _initial;

  @override
  Locale build() => _initial;

  void set(Locale locale) => state = locale;
}

/// Current UI locale. Seeded from settings in main(), persisted on change.
final appLocaleProvider =
    NotifierProvider<AppLocaleNotifier, Locale>(AppLocaleNotifier.new);
