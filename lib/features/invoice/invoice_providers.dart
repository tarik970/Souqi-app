import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/external_action_bridge.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice_settings.dart';
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
    return _writes = _writes.then((_) => repository.setMany(changed));
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
  final settings =
      ref.watch(debtFeatureProvider) ? stored : stored.withoutDebtLines();
  final currencies = await ref.watch(currenciesProvider.future);
  final logo = await ref.watch(invoiceLogoProvider.future);
  return InvoiceRenderContext(
    settings: settings,
    currencies: {for (final c in currencies) c.code: c},
    logo: logo,
  );
});
