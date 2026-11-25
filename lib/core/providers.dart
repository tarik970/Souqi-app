import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/features.dart';
import '../data/db/app_database.dart';
import '../data/repositories/archive_repository.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/currency_repository.dart';
import '../data/repositories/customer_repository.dart';
import '../data/repositories/invoice_repository.dart';
import '../data/repositories/pin_repository.dart';
import '../data/repositories/product_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/stats_repository.dart';
import '../data/repositories/unit_repository.dart';
import '../data/repositories/voucher_repository.dart';
import '../domain/models/currency.dart';
import '../domain/models/unit.dart';
import 'constants/settings_keys.dart';
import 'money/exchange.dart';
import 'security/code_cipher.dart';
import 'security/secure_key_store.dart';

/// Overridden in main() with the opened database.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw StateError('databaseProvider must be overridden in main()'),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(databaseProvider).db),
);

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => ProductRepository(ref.watch(databaseProvider).db),
);

final unitRepositoryProvider = Provider<UnitRepository>(
  (ref) => UnitRepository(ref.watch(databaseProvider).db),
);

/// Where the card-code keys are kept: the Android Keystore. Tests override
/// it with an in-memory store.
final secretKeyStoreProvider = Provider<SecretKeyStore>(
  (ref) => const SecureStorageKeyStore(),
);

/// One cipher for the life of the app — it holds the loaded keys.
final codeCipherProvider = Provider<CodeCipher>(
  (ref) => CodeCipher(ref.watch(secretKeyStoreProvider)),
);

final invoiceRepositoryProvider = Provider<InvoiceRepository>(
  (ref) => InvoiceRepository(
    ref.watch(databaseProvider).db,
    // With the flag off no code is ever taken: a product marked "sold from
    // code stock" then sells like any other service.
    codeCipher: voucherStockEnabled ? ref.watch(codeCipherProvider) : null,
  ),
);

final voucherRepositoryProvider = Provider<VoucherRepository>(
  (ref) => VoucherRepository(
    ref.watch(databaseProvider).db,
    ref.watch(codeCipherProvider),
  ),
);

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => AuditRepository(ref.watch(databaseProvider).db),
);

final pinRepositoryProvider = Provider<PinRepository>(
  (ref) => PinRepository(ref.watch(settingsRepositoryProvider)),
);

final archiveRepositoryProvider = Provider<ArchiveRepository>(
  (ref) => ArchiveRepository(ref.watch(databaseProvider).db),
);

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(databaseProvider).db),
);

final statsRepositoryProvider = Provider<StatsRepository>(
  (ref) => StatsRepository(ref.watch(databaseProvider).db),
);

final currencyRepositoryProvider = Provider<CurrencyRepository>(
  (ref) => CurrencyRepository(
    ref.watch(databaseProvider).db,
    ref.watch(settingsRepositoryProvider),
  ),
);

class AppLocaleNotifier extends Notifier<Locale> {
  AppLocaleNotifier([this._initial = const Locale('ar')]);

  final Locale _initial;

  @override
  Locale build() => _initial;

  /// Applies the locale instantly and persists it.
  Future<void> set(Locale locale) async {
    state = locale;
    await ref
        .read(settingsRepositoryProvider)
        .setString(SettingsKeys.appLanguage, locale.languageCode);
  }
}

/// Current UI locale. Seeded from settings in main(), persisted on change.
final appLocaleProvider =
    NotifierProvider<AppLocaleNotifier, Locale>(AppLocaleNotifier.new);

class SetupDoneNotifier extends Notifier<bool> {
  SetupDoneNotifier([this._initial = false]);

  final bool _initial;

  @override
  bool build() => _initial;

  void complete() => state = true;
}

/// Whether first-launch setup has been completed. Seeded in main().
final setupDoneProvider =
    NotifierProvider<SetupDoneNotifier, bool>(SetupDoneNotifier.new);

/// Active units, presets first.
final unitsProvider = FutureProvider<List<Unit>>(
  (ref) => ref.watch(unitRepositoryProvider).list(),
);

/// All currencies including disabled ones (screens filter as needed).
final currenciesProvider = FutureProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).list(includeInactive: true),
);

final baseCurrencyCodeProvider = FutureProvider<String>(
  (ref) => ref.watch(currencyRepositoryProvider).baseCode(),
);

/// The base currency itself — statistics need its decimal places to turn
/// stored rate snapshots into base minor units.
final baseCurrencyProvider = FutureProvider<Currency>((ref) async {
  final currencies = await ref.watch(currenciesProvider.future);
  final code = await ref.watch(baseCurrencyCodeProvider.future);
  return currencies.firstWhere(
    (c) => c.code == code,
    // The base currency cannot be deleted, but a 0-decimal stand-in is a
    // better answer than a crashed statistics screen.
    orElse: () => Currency(
      code: code,
      nameAr: code,
      nameEn: code,
      decimalPlaces: 0,
      rate: RateFraction.one,
    ),
  );
});
