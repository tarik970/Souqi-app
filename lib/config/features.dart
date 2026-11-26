/// WHAT THE APP MAY SHOW AND DO: the compile-time flags, the license, and
/// the one question the rest of the code asks — [featureOn].
///
/// When a feature is off, nothing related to it may appear anywhere in the
/// UI (menus, buttons, invoice lines, stats). The database tables always
/// exist from schema version 1, so turning a feature on later needs no
/// migration — and turning one off deletes nothing.
library;

import '../core/licensing/license_codec.dart';

// ---- Compile-time flags: the UPPER LIMIT ---------------------------------
//
// A flag that is false here is off in this build whatever a license says.
// Nothing outside this file reads these constants: everything asks
// [featureOn].
const bool debtEnabled = true;
const bool barcodeEnabled = true;
const bool discountEnabled = true;
const bool customersEnabled = true;
const bool accountsEnabled = true;
const bool voucherStockEnabled = true;
const bool multiCurrencyEnabled = true;
const bool dailyReportEnabled = true;
const bool backupEnabled = true;

/// Accounts and debt both require customers. Asserted at startup.
const bool featureFlagsConsistent =
    customersEnabled || (!debtEnabled && !accountsEnabled);

/// The parts of the app a license can turn on or off. Each has a bit in the
/// license's feature mask ([licenseFeatureBits], by [wire] name) and a
/// compile-time flag above.
enum Feature {
  /// The customer debt ledger.
  debt('debt', debtEnabled),

  /// Customers (and attaching one to a sale).
  customers('customers', customersEnabled),

  /// Cards / accounts and renewals.
  accounts('accounts', accountsEnabled),

  /// Prepaid card codes sold from stock.
  vouchers('vouchers', voucherStockEnabled),

  /// Product barcodes and scanning them.
  barcode('barcode', barcodeEnabled),

  /// A discount on an invoice.
  discount('discount', discountEnabled),

  /// Prices, invoices and payments in more than the base currency.
  multiCurrency('multiCurrency', multiCurrencyEnabled),

  /// The daily automatic debt report.
  dailyReport('dailyReport', dailyReportEnabled),

  /// Backup and restore (by hand and the daily automatic one).
  backup('backup', backupEnabled);

  const Feature(this.wire, this.compiledIn);

  /// Its name in a license and in the key generator's `--features`.
  final String wire;

  /// The compile-time flag: false = not in this build at all.
  final bool compiledIn;

  /// Its bit in a license's feature mask.
  int get bit => licenseFeatureBits[wire]!;

  /// What it cannot work without (accounts and debt need customers, the
  /// daily report needs the ledger).
  List<Feature> get requires => [
        for (final name in licenseFeatureRequires[wire] ?? const <String>[])
          Feature.values.firstWhere((f) => f.wire == name),
      ];
}

/// THE question: is [feature] on — compiled into this build, allowed by the
/// license (or the trial), and so is everything it requires?
///
/// Used everywhere, with or without a `ref`: screens, providers, the invoice
/// renderer, and the background engine of the daily job. Nothing reads the
/// flags above or the license's mask directly.
///
/// The answer changes only when a license is activated; the app then starts
/// its state over (`appRestartProvider`), so no widget keeps an old answer.
bool featureOn(Feature feature) => FeatureGate.isOn(feature);

/// What the license allows, as [featureOn] reads it.
///
/// Set from the checked license on every app start, on activation, and by
/// the background engine before it runs the daily job (`LicenseService`).
/// Until then — and in tests that do not care — everything the build has is
/// on. This is only the switchboard of what is SHOWN: selling, printing and
/// the ledger each check the license itself again (`LicenseGuard`).
abstract final class FeatureGate {
  static int _licensed = allLicenseFeatures;

  /// The mask in force.
  static int get mask => _licensed;

  /// Puts a license's feature mask in force.
  static void apply(int mask) => _licensed = mask;

  /// Everything on except [off] (tests of a feature that is turned off).
  static void applyWithout(Iterable<Feature> off) =>
      _licensed = allLicenseFeatures & ~maskOf(off);

  /// Back to "everything the build has" (tests).
  static void reset() => _licensed = allLicenseFeatures;

  /// For each feature: itself and everything it requires, all the way down —
  /// worked out once, because [isOn] is asked in every build.
  static final Map<Feature, ({int mask, bool compiledIn})> _needs = {
    for (final feature in Feature.values) feature: _closure(feature),
  };

  static ({int mask, bool compiledIn}) _closure(Feature feature) {
    var mask = feature.bit;
    var compiledIn = feature.compiledIn;
    for (final needed in feature.requires) {
      final below = _closure(needed);
      mask |= below.mask;
      compiledIn = compiledIn && below.compiledIn;
    }
    return (mask: mask, compiledIn: compiledIn);
  }

  static bool isOn(Feature feature) {
    final needs = _needs[feature]!;
    return needs.compiledIn && _licensed & needs.mask == needs.mask;
  }

  /// The mask of [features] (tests and the key generator's own table).
  static int maskOf(Iterable<Feature> features) =>
      features.fold(0, (mask, feature) => mask | feature.bit);
}
