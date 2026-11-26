import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config/features.dart';
import '../../core/licensing/license_status.dart';
import '../../core/logging/error_log.dart';
import '../../core/logging/error_reporting.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/byte_size.dart';
import '../../data/dev/customer_seeder.dart';
import '../../data/dev/debt_seeder.dart';
import '../../data/dev/invoice_seeder.dart';
import '../../data/dev/voucher_seeder.dart';
import '../../data/db/app_database.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/archive_providers.dart';
import '../customers/customers_providers.dart';
import '../debts/debt_providers.dart';
import '../invoice/invoice_output.dart';
import '../license/license_providers.dart';
import '../license/license_screen.dart';
import '../license/license_text.dart';
import '../products/products_providers.dart';
import '../sale/sale_providers.dart';
import '../security/pin_dialogs.dart';
import '../vouchers/voucher_providers.dart';
import 'storage_providers.dart';

/// The installed app's version ("1.0.0") and build number ("1"), or null on
/// a platform that does not say (a widget test).
final appPackageInfoProvider = FutureProvider<PackageInfo?>((ref) async {
  try {
    return await PackageInfo.fromPlatform();
  } on Object {
    return null;
  }
});

/// Where the error log files are. Tests point it at a temporary folder.
final errorLogDirectoryProvider =
    Provider<Future<Directory> Function()>((ref) => errorLogDirectory);

/// How many errors the log holds, for the line under "Share error log";
/// null when the folder cannot be read.
final errorLogCountProvider = FutureProvider.autoDispose<int?>((ref) async {
  try {
    final directory = await ref.watch(errorLogDirectoryProvider)();
    return (await ErrorLog.export(directory)).entryCount;
  } on Object {
    return null;
  }
});

/// Settings → About: which build this is (version and build number), the
/// LICENSE STATE of this phone, what the data costs in storage, and "Share
/// error log" — the things the developer asks a shop for on the phone.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key, this.showDeveloperTools = true});

  /// The seeders that fill the database with test data. They exist in
  /// DEBUG builds only, whatever this says: the check below is on the
  /// compile-time constant, so a release build does not even contain their
  /// code. A test passes false to see the page a customer sees.
  final bool showDeveloperTools;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      // Scrolls: the logo, the version and the storage figures do not fit a
      // small phone at a large system font size.
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        children: [
          // Brand rule: the logo appears on cream/white surfaces only.
          Image.asset('assets/branding/souqi_logo.png', height: 180),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                Text(
                  l10n.aboutTagline,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const Divider(height: 32),
          const _BuildRows(),
          const _LicenseRow(),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              l10n.storageTitle,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          const _StorageRows(),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text(
              l10n.aboutSupportSection,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
          ),
          const _ShareErrorLogTile(),
          // DEVELOPER TOOLS — DEBUG BUILDS ONLY: the seeders that fill the
          // database for performance testing. kDebugMode is a compile-time
          // constant, false in release and profile builds, so none of this
          // (nor lib/data/dev/) is compiled into a release.
          if (kDebugMode && showDeveloperTools) ...[
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                l10n.debugTools,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            const _SeedInvoicesTile(),
            if (featureOn(Feature.customers)) const _SeedCustomersTile(),
            if (featureOn(Feature.vouchers)) const _SeedCardsTile(),
            if (featureOn(Feature.debt)) const _SeedDebtsTile(),
          ],
        ],
      ),
    );
  }
}

/// The version and the build number, each on its own row: what the
/// developer asks first ("which version do you have?").
class _BuildRows extends ConsumerWidget {
  const _BuildRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final info = ref.watch(appPackageInfoProvider).value;
    final style = Theme.of(context).textTheme.bodyLarge;
    return Column(
      children: [
        ListTile(
          key: const ValueKey('about-version'),
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.aboutVersion),
          trailing: Text(
            info?.version ?? '—',
            style: style,
            textDirection: TextDirection.ltr,
          ),
        ),
        ListTile(
          key: const ValueKey('about-build'),
          leading: const Icon(Icons.tag),
          title: Text(l10n.aboutBuildNumber),
          trailing: Text(
            info?.buildNumber ?? '—',
            style: style,
            textDirection: TextDirection.ltr,
          ),
        ),
      ],
    );
  }
}

/// The license of this phone — activated (until when), on trial (how much
/// is left) or not activated (why) — and the way to the activation screen.
class _LicenseRow extends ConsumerWidget {
  const _LicenseRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final status = ref.watch(licenseProvider);
    final now = ref.watch(clockProvider)();
    final shop = status.shopName;
    return ListTile(
      key: const ValueKey('about-license'),
      leading: Icon(
        status.isLicensed ? Icons.verified_outlined : Icons.vpn_key_outlined,
      ),
      title: Text(l10n.licenseTitle),
      subtitle: Text(
        [
          licenseStateLine(l10n, status, locale, now),
          if (shop != null && shop.isNotEmpty) l10n.licenseShopLine(shop),
        ].join('\n'),
        key: const ValueKey('about-license-state'),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const LicenseScreen()),
      ),
    );
  }
}

/// The license as the error log's header says it — plain words for the
/// developer, not a sentence for the shop.
String describeLicenseForLog(LicenseStatus status, DateTime now) {
  final license = status.license;
  final id = license == null ? '' : ', license no. ${license.licenseId}';
  final expires = license?.expiresAt;
  return switch (status.mode) {
    LicenseMode.licensed => expires == null
        ? 'activated, lifetime$id'
        : 'activated until ${expires.toIso8601String()}$id',
    LicenseMode.trial => 'trial, ${status.trialDaysLeft(now)} days / '
        '${status.trialInvoicesLeft ?? 0} invoices left',
    LicenseMode.unlicensed =>
      'not activated (${status.reason?.name ?? 'unknown'})$id',
  };
}

/// "Share error log": every error the app wrote down on this phone, with
/// the version, the database version and the license state on top, as one
/// text file handed to the share sheet (WhatsApp, usually). The shop
/// decides to send it; the app sends nothing by itself.
class _ShareErrorLogTile extends ConsumerStatefulWidget {
  const _ShareErrorLogTile();

  @override
  ConsumerState<_ShareErrorLogTile> createState() => _ShareErrorLogTileState();
}

class _ShareErrorLogTileState extends ConsumerState<_ShareErrorLogTile> {
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // ref is only read before the first await.
    final output = ref.read(invoiceOutputProvider);
    final directory = ref.read(errorLogDirectoryProvider);
    final status = ref.read(licenseProvider);
    final requestCode = ref.read(requestCodeProvider);
    final info = ref.read(appPackageInfoProvider).value;
    final now = ref.read(clockProvider)();
    setState(() => _busy = true);
    try {
      await ErrorLog.instance.flush();
      final export = await ErrorLog.export(await directory());
      final header = errorLogHeader(
        appVersion: info == null
            ? ErrorLog.instance.appVersion
            : '${info.version}+${info.buildNumber}',
        createdAt: now,
        errorCount: export.entryCount,
        facts: {
          'Database': 'schema ${AppDatabase.schemaVersion}',
          'License': describeLicenseForLog(status, now),
          'Request code': ?requestCode,
        },
      );
      await output.shareTextFile(
        fileName: errorLogFileName(now),
        text: '$header\n${export.text}',
      );
    } on Object catch (error, stack) {
      reportError(error, stack, context: 'share error log');
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.errorLogShareFailed)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final count = ref.watch(errorLogCountProvider).value;
    return ListTile(
      key: const ValueKey('about-share-error-log'),
      leading: const Icon(Icons.bug_report_outlined),
      title: Text(l10n.errorLogShare),
      subtitle: Text(
        [
          l10n.errorLogShareHint,
          if (count != null)
            count == 0 ? l10n.errorLogNone : l10n.errorLogCount('$count'),
        ].join('\n'),
      ),
      trailing: _busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.ios_share),
      onTap: _busy ? null : _share,
    );
  }
}

/// How many invoices are kept and what the database file costs.
class _StorageRows extends ConsumerWidget {
  const _StorageRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final stats = ref.watch(storageStatsProvider).value;
    final style = Theme.of(context).textTheme.bodyLarge;

    String? size;
    if (stats != null) {
      final bytes = formatByteSize(stats.databaseBytes, locale: locale);
      size = switch (bytes.unit) {
        ByteUnit.bytes => l10n.sizeInBytes(bytes.value),
        ByteUnit.kilobytes => l10n.sizeInKilobytes(bytes.value),
        ByteUnit.megabytes => l10n.sizeInMegabytes(bytes.value),
      };
    }

    return Column(
      children: [
        ListTile(
          key: const ValueKey('about-invoice-count'),
          leading: const Icon(Icons.receipt_long),
          title: Text(l10n.storageInvoiceCount),
          trailing: Text(
            stats == null
                ? '—'
                : formatMinor(stats.invoiceCount, decimals: 0, locale: locale),
            style: style,
          ),
        ),
        ListTile(
          key: const ValueKey('about-database-size'),
          leading: const Icon(Icons.storage),
          title: Text(l10n.storageDatabaseSize),
          trailing: Text(size ?? '—', style: style),
        ),
      ],
    );
  }
}

/// Debug-only: fills the archive with test invoices.
///
/// The brief asks the archive and the statistics screens to stay smooth at
/// 50,000 invoices; this is how that is checked on a real phone rather than
/// hoped for.
class _SeedInvoicesTile extends ConsumerWidget {
  const _SeedInvoicesTile();

  static const List<int> counts = [100, 1000, 10000, 50000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('about-seed-invoices'),
      leading: const Icon(Icons.science_outlined),
      title: Text(l10n.debugSeedInvoices),
      subtitle: Text(l10n.debugSeedHint),
      trailing: PopupMenuButton<int>(
        key: const ValueKey('about-seed-count'),
        icon: const Icon(Icons.add),
        itemBuilder: (context) => [
          for (final count in counts)
            PopupMenuItem(value: count, child: Text('$count')),
        ],
        onSelected: (count) => _seed(context, ref, count),
      ),
    );
  }

  Future<void> _seed(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final database = container.read(databaseProvider);
    final navigator = Navigator.of(context);

    // Deliberately not disposed: the dialog below can outlive this method
    // while it animates out, and a text field rebuilding on a disposed
    // listenable is exactly the crash this app has been bitten by before.
    // With no listeners left it is collected like any other object.
    final progress = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('about-seeding-dialog'),
          title: Text(l10n.debugSeedingTitle),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.progressCount(
                  formatMinor(done, decimals: 0, locale: locale),
                  formatMinor(count, decimals: 0, locale: locale),
                )),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: count == 0 ? null : done / count),
              ],
            ),
          ),
        ),
      ),
    );

    final created = await seedTestInvoices(
      database.db,
      count: count,
      onProgress: (done) => progress.value = done,
    );
    container
      ..invalidate(storageStatsProvider)
      ..invalidate(archiveListProvider)
      ..invalidate(archiveRangeSummaryProvider);
    navigator.pop();
    // The result only once the rows are actually there.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.debugSeedDone(
          formatMinor(created, decimals: 0, locale: locale),
        )),
      ));
  }
}

/// Debug-only: fills the customer list with test customers, each with two
/// cards / accounts.
///
/// The brief asks the quick search to stay instant with 5,000 customers and
/// 10,000 accounts; this is how that is tried on a real phone.
class _SeedCustomersTile extends ConsumerWidget {
  const _SeedCustomersTile();

  static const List<int> counts = [100, 1000, 5000];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('about-seed-customers'),
      leading: const Icon(Icons.science_outlined),
      title: Text(l10n.debugSeedCustomers),
      subtitle: Text(l10n.debugSeedCustomersHint),
      trailing: PopupMenuButton<int>(
        key: const ValueKey('about-seed-customers-count'),
        icon: const Icon(Icons.add),
        itemBuilder: (context) => [
          for (final count in counts)
            PopupMenuItem(value: count, child: Text('$count')),
        ],
        onSelected: (count) => _seed(context, ref, count),
      ),
    );
  }

  Future<void> _seed(BuildContext context, WidgetRef ref, int count) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final database = container.read(databaseProvider);
    final navigator = Navigator.of(context);

    // Deliberately not disposed, for the same reason as in the invoice
    // seeder above: the dialog can outlive this method while it animates
    // out.
    final progress = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('about-seeding-customers-dialog'),
          title: Text(l10n.debugSeedingCustomersTitle),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.progressCount(
                  formatMinor(done, decimals: 0, locale: locale),
                  formatMinor(count, decimals: 0, locale: locale),
                )),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: count == 0 ? null : done / count),
              ],
            ),
          ),
        ),
      ),
    );

    final created = await seedTestCustomers(
      database.db,
      customers: count,
      onProgress: (done) => progress.value = done,
    );
    refreshCustomerData(container);
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.debugSeedCustomersDone(
          formatMinor(created, decimals: 0, locale: locale),
        )),
      ));
  }
}

/// Debug builds only: two card products with made-up codes — a batch near
/// its expiry, one already expired and one under its low-stock threshold —
/// for trying card sales, the warnings and the expired list on a phone.
class _SeedCardsTile extends ConsumerWidget {
  const _SeedCardsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('about-seed-cards'),
      leading: const Icon(Icons.science_outlined),
      title: Text(l10n.debugSeedCards),
      subtitle: Text(l10n.debugSeedCardsHint),
      trailing: const Icon(Icons.add),
      onTap: () => _seed(context),
    );
  }

  Future<void> _seed(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final locale = container.read(appLocaleProvider).languageCode;
    // Like a real batch: codes never sit in stock without a PIN.
    if (!await ensurePinIsSet(context, reason: l10n.pinReasonCodes)) return;

    final added = await seedTestCards(
      products: container.read(productRepositoryProvider),
      vouchers: container.read(voucherRepositoryProvider),
      currencyCode: await container.read(baseCurrencyCodeProvider.future),
    );
    container
      ..invalidate(productsListProvider)
      ..invalidate(favoriteProductsProvider);
    refreshVoucherData(container);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.debugSeedCardsDone(
          formatMinor(added, decimals: 0, locale: locale),
        )),
      ));
  }
}

/// Debug builds only: 5,000 customers and 200,000 ledger entries — the size
/// the debtors list, the aging summary and the debt statistics have to stay
/// fast at — for trying them on a real phone.
class _SeedDebtsTile extends ConsumerWidget {
  const _SeedDebtsTile();

  static const int customers = 5000;
  static const int entries = 200000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      key: const ValueKey('about-seed-debts'),
      leading: const Icon(Icons.science_outlined),
      title: Text(l10n.seedDebtsTitle),
      subtitle: Text(l10n.seedDebtsSubtitle),
      trailing: const Icon(Icons.add),
      onTap: () => _seed(context, ref),
    );
  }

  Future<void> _seed(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final locale = ref.read(appLocaleProvider).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final database = container.read(databaseProvider);
    final navigator = Navigator.of(context);

    // Deliberately not disposed, for the same reason as in the seeders
    // above: the dialog can outlive this method while it animates out.
    final progress = ValueNotifier<int>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          key: const ValueKey('about-seeding-debts-dialog'),
          scrollable: true,
          title: Text(l10n.seedDebtsTitle),
          content: ValueListenableBuilder<int>(
            valueListenable: progress,
            builder: (context, done, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.seedingDebts(
                  formatMinor(done, decimals: 0, locale: locale),
                  formatMinor(entries, decimals: 0, locale: locale),
                )),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: done / entries),
              ],
            ),
          ),
        ),
      ),
    );

    // The ledger is spread over the customers that exist: make sure there
    // are enough of them first.
    final existing = (await database.db.rawQuery(
      'SELECT COUNT(*) AS n FROM customers WHERE is_active = 1',
    ))
            .first['n'] as int? ??
        0;
    if (existing < customers) {
      await seedTestCustomers(
        database.db,
        customers: customers - existing,
        accountsPerCustomer: 0,
      );
    }
    final written = await seedTestDebts(
      database.db,
      entries: entries,
      onProgress: (done) => progress.value = done,
    );
    refreshCustomerData(container);
    refreshDebtData(container);
    navigator.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(l10n.seedingDebts(
          formatMinor(written, decimals: 0, locale: locale),
          formatMinor(entries, decimals: 0, locale: locale),
        )),
      ));
  }
}
