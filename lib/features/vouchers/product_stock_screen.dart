import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/widgets/load_error_view.dart';
import '../../core/money/money_format.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_output.dart';
import '../invoice/invoice_providers.dart';
import '../invoice/output_messages.dart';
import '../products/products_providers.dart';
import '../security/pin_dialogs.dart';
import 'add_batch_screen.dart';
import 'card_stock_screen.dart';
import 'code_widgets.dart';
import 'voucher_providers.dart';

enum _BatchAction { codes, expiry, delete }

enum _ExportTarget { share, save }

/// The card stock of ONE product: its counts and its batches (date, count,
/// cost per card, expiry), with "Load codes" to add a batch.
class ProductStockScreen extends ConsumerWidget {
  const ProductStockScreen({super.key, required this.productId});

  final int productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final stock = ref
        .watch(stockOverviewProvider)
        .value
        ?.where((s) => s.product.id == productId)
        .firstOrNull;
    final batches = ref.watch(productBatchesProvider(productId)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(stock?.product.name ?? l10n.navCardStock),
        actions: [
          PopupMenuButton<void>(
            key: const ValueKey('product-stock-menu'),
            itemBuilder: (context) => [
              PopupMenuItem<void>(
                key: const ValueKey('product-stock-export'),
                onTap: () => _export(context),
                child: Text(l10n.exportCodes),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: stock == null
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('batch-add'),
              heroTag: null,
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AddBatchScreen(product: stock.product),
                ),
              ),
              icon: const Icon(Icons.playlist_add),
              label: Text(l10n.batchAdd),
            ),
      body: stock == null || batches == null
          ? const SizedBox.shrink()
          : ListView(
              // Room under the last batch for the floating button.
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 96),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StockCounts(
                    locale: locale,
                    available: stock.available,
                    sold: stock.sold,
                    voided: stock.voided,
                    expired: stock.expired,
                    highlightAvailable: stock.needsAttention,
                    labels: l10n,
                  ),
                ),
                if (stock.needsAttention)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      stock.isOut
                          ? l10n.stockOut
                          : l10n.stockLowWarning(
                              stock.product.name,
                              formatMinor(stock.available,
                                  decimals: 0, locale: locale),
                            ),
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                  child: Text(
                    l10n.batchesTitle,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.primary),
                  ),
                ),
                if (batches.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.batchEmpty,
                      key: const ValueKey('batch-empty'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final batch in batches)
                  _BatchTile(batch: batch, productName: stock.product.name),
              ],
            ),
    );
  }

  /// Unsold codes to a text file, shared or saved: warning, PIN, then the
  /// file. Logged by the repository.
  Future<void> _export(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final locale = container.read(appLocaleProvider).languageCode;
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    final target = await showDialog<_ExportTarget>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('export-dialog'),
        scrollable: true,
        title: Text(l10n.exportCodes),
        content: Text(l10n.exportWarning),
        // Stacked: three labels do not fit side by side on a small phone.
        actionsOverflowAlignment: OverflowBarAlignment.end,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          OutlinedButton(
            key: const ValueKey('export-save'),
            onPressed: () => Navigator.of(context).pop(_ExportTarget.save),
            child: Text(l10n.exportSave),
          ),
          FilledButton(
            key: const ValueKey('export-share'),
            onPressed: () => Navigator.of(context).pop(_ExportTarget.share),
            child: Text(l10n.exportShare),
          ),
        ],
      ),
    );
    if (target == null || !context.mounted) return;
    if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;

    final export = await container
        .read(voucherRepositoryProvider)
        .exportAvailable(productId: productId);
    refreshVoucherData(container);
    if (export.lines.isEmpty) {
      say(l10n.exportNothing);
      return;
    }
    final name = 'souqi-codes-$productId-'
        '${DateTime.now().millisecondsSinceEpoch}.txt';
    final directory = await container.read(outputDirectoryProvider)();
    final file = await File(p.join(directory.path, name)).writeAsString(
      '${export.lines.join('\n')}\n',
      encoding: utf8,
      flush: true,
    );
    final bridge = container.read(nativeBridgeProvider);
    try {
      switch (target) {
        case _ExportTarget.share:
          // The staged copy has to outlive the share sheet; the launch
          // housekeeping removes it within a day.
          await bridge.shareFile(filePath: file.path, mimeType: 'text/plain');
        case _ExportTarget.save:
          final shown = await bridge.saveToDownloads(
            filePath: file.path,
            fileName: name,
            mimeType: 'text/plain',
          );
          say(l10n.savedToPhone(shown));
      }
    } on OutputException catch (e) {
      say(outputFailureMessage(l10n, e));
      return;
    } finally {
      if (target == _ExportTarget.save) {
        // Saved to the phone: no reason to keep a second copy in the cache.
        try {
          await file.delete();
        } on FileSystemException {
          // Swept on the next launch.
        }
      }
    }
    if (target == _ExportTarget.share) {
      say(l10n.exportDone(
        formatMinor(export.lines.length, decimals: 0, locale: locale),
      ));
    }
  }
}

class _BatchTile extends ConsumerWidget {
  const _BatchTile({required this.batch, required this.productName});

  final VoucherBatch batch;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final currencies =
        ref.watch(currencyMapProvider).value ?? const <String, Currency>{};
    final dates = DateFormat.yMd(locale);
    String count(int value) => formatMinor(value, decimals: 0, locale: locale);

    final cost = batch.costPerCardMinor;
    final costCurrency = currencies[batch.costCurrencyCode];
    final facts = <String>[
      l10n.cardsCount(count(batch.codeCount)),
      if (cost != null && batch.costCurrencyCode != null)
        l10n.batchCostEach(formatMinor(
          cost,
          decimals: costCurrency?.decimalPlaces ?? 0,
          locale: locale,
          symbol: costCurrency == null || costCurrency.symbol.isEmpty
              ? batch.costCurrencyCode!
              : costCurrency.symbol,
        )),
      if (batch.expiryAt != null)
        l10n.batchExpires(dates.format(expiryLastDay(batch.expiryAt!))),
    ];
    final left = <String>[
      '${l10n.stockAvailable} ${count(batch.available)}',
      '${l10n.stockSold} ${count(batch.sold)}',
      if (batch.voided > 0) '${l10n.stockVoid} ${count(batch.voided)}',
      if (batch.expired > 0) '${l10n.stockExpired} ${count(batch.expired)}',
    ];

    return Card(
      key: ValueKey('batch-${batch.id}'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ListTile(
        title: Text(dates.add_jm().format(batch.createdAt.toLocal())),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(facts.join(' · ')),
            Text(
              left.join(' · '),
              style: batch.expired > 0
                  ? TextStyle(color: theme.colorScheme.error)
                  : null,
            ),
          ],
        ),
        onTap: () => _showCodes(context),
        trailing: PopupMenuButton<_BatchAction>(
          key: ValueKey('batch-menu-${batch.id}'),
          onSelected: (action) => switch (action) {
            _BatchAction.codes => _showCodes(context),
            _BatchAction.expiry => _changeExpiry(context),
            _BatchAction.delete => _delete(context),
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: _BatchAction.codes,
              child: Text(l10n.batchShowCodes),
            ),
            PopupMenuItem(
              key: const ValueKey('batch-action-expiry'),
              value: _BatchAction.expiry,
              child: Text(l10n.batchChangeExpiry),
            ),
            PopupMenuItem(
              key: const ValueKey('batch-action-delete'),
              value: _BatchAction.delete,
              child: Text(l10n.batchDelete),
            ),
          ],
        ),
      ),
    );
  }

  void _showCodes(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BatchCodesScreen(
          batchId: batch.id,
          productName: productName,
        ),
      ),
    );
  }

  /// A new expiry for the unsold codes of the batch. It can put expired
  /// cards back on sale, so it is behind the PIN and logged.
  Future<void> _changeExpiry(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final today = DateTime.now();
    final current =
        batch.expiryAt == null ? today : expiryLastDay(batch.expiryAt!);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 20),
      helpText: l10n.batchChangeExpiry,
    );
    if (picked == null || !context.mounted) return;
    if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;
    await container
        .read(voucherRepositoryProvider)
        .setBatchExpiry(batch.id, expiryFromDate(picked));
    refreshVoucherData(container);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.expiryChanged)));
  }

  /// Deletes the batch when nothing of it was sold; sold codes are never
  /// deleted, and the repository refuses a batch that has any.
  Future<void> _delete(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final locale = container.read(appLocaleProvider).languageCode;
    void say(String message) => messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

    if (!batch.isUnsold) {
      say(l10n.batchDeleteBlocked);
      return;
    }
    final unsold = batch.available + batch.expired + batch.voided;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const ValueKey('batch-delete-dialog'),
        scrollable: true,
        title: Text(l10n.batchDeleteTitle),
        content: Text(l10n.batchDeleteMessage(
          formatMinor(unsold, decimals: 0, locale: locale),
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('batch-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;

    final deleted = await container
        .read(voucherRepositoryProvider)
        .deleteUnsoldBatch(batch.id);
    refreshVoucherData(container);
    say(deleted == null
        ? l10n.batchDeleteBlocked
        : l10n.batchDeleted(formatMinor(deleted, decimals: 0, locale: locale)));
  }
}

/// The codes of one batch, masked, each with its menu (show / void / return
/// to stock). This is where a sold code stays reachable after its invoice
/// was deleted from the archive.
class BatchCodesScreen extends ConsumerWidget {
  const BatchCodesScreen({
    super.key,
    required this.batchId,
    required this.productName,
  });

  final int batchId;
  final String productName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final codes = ref.watch(batchCodesProvider(batchId));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.batchCodesTitle)),
      body: codes.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, stack) => LoadErrorView(e, stack),
        data: (items) => ListView.separated(
          key: const ValueKey('batch-codes'),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: items.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) => index == 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    productName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                )
              : CodeTile(code: items[index - 1]),
        ),
      ),
    );
  }
}
