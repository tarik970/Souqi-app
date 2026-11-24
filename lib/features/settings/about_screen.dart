import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/byte_size.dart';
import '../../data/dev/invoice_seeder.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/archive_providers.dart';
import 'storage_providers.dart';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

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
                const SizedBox(height: 8),
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snapshot) {
                    final info = snapshot.data;
                    if (info == null) return const SizedBox.shrink();
                    return Text(
                      l10n.versionLabel('${info.version}+${info.buildNumber}'),
                      style: theme.textTheme.bodyMedium,
                    );
                  },
                ),
              ],
            ),
          ),
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
          // Debug builds only: the seeder that fills the archive for
          // performance testing. Never compiled into a release.
          if (kDebugMode) ...[
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
          ],
        ],
      ),
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
