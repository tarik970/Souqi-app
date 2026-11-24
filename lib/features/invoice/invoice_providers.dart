import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice_settings.dart';

/// The Android side (Bluetooth, WhatsApp intent, Downloads, share sheet).
/// Overridden with a fake in tests.
final nativeBridgeProvider = Provider<NativeBridge>(
  (ref) => const MethodChannelNativeBridge(),
);

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
  final settings = await ref.watch(invoiceSettingsProvider.future);
  final currencies = await ref.watch(currenciesProvider.future);
  final logo = await ref.watch(invoiceLogoProvider.future);
  return InvoiceRenderContext(
    settings: settings,
    currencies: {for (final c in currencies) c.code: c},
    logo: logo,
  );
});
