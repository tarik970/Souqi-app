/// Compile-time feature flags (see project brief).
///
/// When a flag is false, nothing related to it may appear anywhere in the UI
/// (menus, buttons, invoice lines, stats). The database tables always exist
/// from schema version 1, so enabling a flag later needs no migration.
library;

/// The customer debt ledger. UI code never reads this constant directly: it
/// asks `debtFeatureProvider` (lib/core/providers.dart), the one switch that
/// phase 5b will also tie to the license.
const bool debtEnabled = true;
const bool barcodeEnabled = true;
const bool discountEnabled = true;
const bool customersEnabled = true;
const bool accountsEnabled = true;
const bool voucherStockEnabled = true;

/// Accounts and debt both require customers. Asserted at startup.
const bool featureFlagsConsistent =
    customersEnabled || (!debtEnabled && !accountsEnabled);
