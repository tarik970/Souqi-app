import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/features.dart';
import '../../core/platform/external_action_bridge.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice_settings.dart';
import '../../domain/models/voucher.dart';
import '../license/license_providers.dart';
import '../security/pin_session.dart';

/// The Android side itself (Bluetooth, WhatsApp intent, Downloads, share
/// sheet). Screens do NOT use this one: they use [nativeBridgeProvider].
final platformBridgeProvider = Provider<NativeBridge>(
  (ref) => const MethodChannelNativeBridge(),
);

/// The Android side as the app uses it: [platformBridgeProvider], with the
/// PIN locks told of every external action before it starts — which is what
/// gives the seller two minutes to come back from the share sheet or
/// WhatsApp without the PIN (see `PinBackgroundGuard`).
///
/// Tests replace either one with a fake: this one to leave the locks out,
/// [platformBridgeProvider] to keep them in.
final nativeBridgeProvider = Provider<NativeBridge>((ref) {
  final guard = ref.watch(pinBackgroundGuardProvider);
  return ExternalActionBridge(
    ref.watch(platformBridgeProvider),
    onStarting: guard.externalActionStarting,
    onNotStarted: guard.externalActionFailed,
  );
});

/// The invoice settings, loaded from the `settings` table.
///
/// [set] applies a change to the state FIRST, so the live preview repaints in
/// the same frame, and then writes only the keys that changed. Writes are
/// chained, so quick successive edits reach the database in order.
class InvoiceSettingsNotifier extends AsyncNotifier<InvoiceSettings> {
  Future<void> _writes = Future<void>.value();

  @override
  Future<InvoiceSettings> build() async {
    final stored = await ref.watch(settingsRepositoryProvider).getAll();
    return InvoiceSettings.fromMap(stored);
  }

  Future<void> set(InvoiceSettings next) {
    final before = state.value?.toMap() ?? const <String, String>{};
    state = AsyncData(next);
    final changed = <String, String>{
      for (final entry in next.toMap().entries)
        if (before[entry.key] != entry.value) entry.key: entry.value,
    };
    if (changed.isEmpty) return _writes;
    final repository = ref.read(settingsRepositoryProvider);
    // One failed write must not stop every later one: the chain carries
    // the ORDER of the writes, not their errors (the caller of the failed
    // write still gets its error).
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => repository.setMany(changed));
  }

  /// [set] for a change that is written to the audit log: the changed keys
  /// and the log line land in ONE transaction — a change that failed leaves
  /// no line saying it happened, and one that went through cannot lose its
  /// line. Used for the payment QR (where customers send money).
  ///
  /// [update] is applied to the settings as they are NOW, so a change made
  /// elsewhere while a PIN dialog or a picker was open is not undone.
  Future<void> changeAudited(
    InvoiceSettings Function(InvoiceSettings current) update, {
    required AuditAction action,
    Map<String, Object?> details = const {},
  }) {
    final current = state.value;
    if (current == null) return _writes;
    final before = current.toMap();
    final next = update(current);
    state = AsyncData(next);
    final changed = <String, String>{
      for (final entry in next.toMap().entries)
        if (before[entry.key] != entry.value) entry.key: entry.value,
    };
    final db = ref.read(databaseProvider).db;
    final write = _writes.catchError((Object _) {}).then(
          (_) => db.transaction((txn) async {
            await SettingsRepository(txn).setMany(changed);
            await AuditRepository(txn).log(action, details: details);
          }),
        );
    _writes = write;
    return write.catchError((Object error, StackTrace stack) {
      // Nothing was written: the screen goes back to what IS stored.
      if (identical(state.value, next)) state = AsyncData(current);
      Error.throwWithStackTrace(error, stack);
    });
  }

  /// Convenience for `set(update(current))`. No-op until the first load.
  Future<void> change(InvoiceSettings Function(InvoiceSettings current) update) {
    final current = state.value;
    if (current == null) return _writes;
    return set(update(current));
  }
}

final invoiceSettingsProvider =
    AsyncNotifierProvider<InvoiceSettingsNotifier, InvoiceSettings>(
  InvoiceSettingsNotifier.new,
);

/// The shop logo decoded once, ready to paint synchronously. Null when no
/// logo is set (or the stored bytes cannot be decoded).
final invoiceLogoProvider = FutureProvider<ui.Image?>((ref) async {
  final bytes = await ref.watch(
    invoiceSettingsProvider.selectAsync((settings) => settings.logoPng),
  );
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } on Exception {
    return null;
  }
});

/// Everything [InvoiceView] needs besides the invoice itself.
class InvoiceRenderContext {
  const InvoiceRenderContext({
    required this.settings,
    required this.currencies,
    required this.logo,
  });

  final InvoiceSettings settings;
  final Map<String, Currency> currencies;
  final ui.Image? logo;
}

final invoiceRenderContextProvider =
    FutureProvider<InvoiceRenderContext>((ref) async {
  final stored = await ref.watch(invoiceSettingsProvider.future);
  // With the debt ledger off, nothing of it reaches the paper — not even on
  // an invoice that was saved while it was on.
  var settings = featureOn(Feature.debt) ? stored : stored.withoutDebtLines();
  // THE LICENSE ON THE PAPER: the shop name is the license's (the header
  // text under it stays the shop's own), and an invoice made on the trial
  // carries the small "trial version" line.
  final license = ref.watch(licenseProvider);
  settings = settings.copyWith(
    shopName: license.shopName,
    trialNotice: license.isTrial,
  );
  final currencies = await ref.watch(currenciesProvider.future);
  final logo = await ref.watch(invoiceLogoProvider.future);
  return InvoiceRenderContext(
    settings: settings,
    currencies: {for (final c in currencies) c.code: c},
    logo: logo,
  );
});
