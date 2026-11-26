import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/voucher_format.dart';
import '../../core/vouchers/code_import.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/product.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';
import '../products/products_providers.dart';
import '../security/pin_dialogs.dart';
import 'code_scan_screen.dart';
import 'voucher_providers.dart';

/// How the codes of a batch are brought in.
enum LoadMethod { paste, file, scan }

/// "120 added, 3 duplicates skipped, 1 empty line" — the report of a load,
/// before saving ([added] = what would be added) and after it.
String importReportText(
  AppLocalizations l10n, {
  required String locale,
  required int added,
  required int duplicates,
  required int emptyLines,
  required int invalidLines,
  bool headerSkipped = false,
  bool saved = false,
}) {
  final count = formatMinor(added, decimals: 0, locale: locale);
  return [
    saved ? l10n.importAdded(count) : l10n.importToAdd(count),
    if (duplicates > 0) l10n.importDuplicates(duplicates),
    if (emptyLines > 0) l10n.importEmpty(emptyLines),
    if (invalidLines > 0) l10n.importInvalid(invalidLines),
    if (headerSkipped) l10n.importHeaderSkipped,
  ].join(locale == 'ar' ? '، ' : ', ');
}

/// Loads a new batch of codes for ONE product: paste a list, import a .txt
/// or .csv file, or scan the cards one by one — then check the masked
/// preview and the count, optionally give the batch an expiry date and a
/// cost per card, and save. Saving is one transaction.
class AddBatchScreen extends ConsumerStatefulWidget {
  const AddBatchScreen({super.key, required this.product});

  final Product product;

  @override
  ConsumerState<AddBatchScreen> createState() => _AddBatchScreenState();
}

class _AddBatchScreenState extends ConsumerState<AddBatchScreen> {
  final _paste = TextEditingController();
  final _cost = TextEditingController();

  LoadMethod _method = LoadMethod.paste;
  CodeColumns _columns = CodeColumns.codeOnly;
  String? _fileName;
  String _fileContent = '';
  bool _fileError = false;
  List<String> _scanned = const [];

  /// The last day the cards can be sold on; null = no expiry.
  DateTime? _expiry;
  String? _costError;

  CodeParseResult _parsed = CodeParseResult.empty;

  /// How many of the parsed codes the product already has — found by hash,
  /// a moment after the text changes.
  int _existing = 0;
  int _generation = 0;
  Timer? _debounce;
  bool _saving = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _paste.dispose();
    _cost.dispose();
    super.dispose();
  }

  String get _source => switch (_method) {
        LoadMethod.paste => _paste.text,
        LoadMethod.file => _fileContent,
        LoadMethod.scan => _scanned.join('\n'),
      };

  /// A scanned card is one code: there are no columns to choose.
  CodeColumns get _effectiveColumns =>
      _method == LoadMethod.scan ? CodeColumns.codeOnly : _columns;

  /// Re-reads the source and, a moment later, asks the database how many of
  /// those codes are already there.
  void _refresh() {
    final parsed = parseCodeList(_source, columns: _effectiveColumns);
    final generation = ++_generation;
    setState(() {
      _parsed = parsed;
      _existing = 0;
    });
    _debounce?.cancel();
    if (parsed.codes.isEmpty) return;
    final repository = ref.read(voucherRepositoryProvider);
    final productId = widget.product.id!;
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      int existing;
      try {
        existing = await repository.countExisting(productId, parsed.codes);
      } on Exception {
        // The save checks again inside its transaction; the preview simply
        // shows no "already loaded" count.
        return;
      }
      if (!mounted || generation != _generation) return;
      setState(() => _existing = existing);
    });
  }

  Future<void> _pickFile() async {
    final bridge = ref.read(nativeBridgeProvider);
    PickedTextFile? picked;
    try {
      picked = await bridge.pickTextFile();
    } on OutputException {
      if (!mounted) return;
      setState(() {
        _fileName = null;
        _fileContent = '';
        _fileError = true;
      });
      _refresh();
      return;
    }
    if (picked == null || !mounted) return;
    _fileName = picked.name;
    _fileContent = picked.content;
    _fileError = false;
    _refresh();
  }

  Future<void> _scan() async {
    final scanned = await Navigator.of(context).push(
      MaterialPageRoute<List<String>>(
        builder: (_) => CodeScanScreen(initial: _scanned),
      ),
    );
    if (scanned == null || !mounted) return;
    _scanned = scanned;
    _refresh();
  }

  Future<void> _pickExpiry() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 20),
    );
    if (picked == null || !mounted) return;
    setState(() => _expiry = picked);
  }

  Future<void> _save(Currency? currency) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The batch is saved even if this page is closed meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    final locale = container.read(appLocaleProvider).languageCode;
    final product = widget.product;

    int? cost;
    final costText = _cost.text.trim();
    if (costText.isNotEmpty) {
      cost = parseAmountMinor(costText, decimals: currency?.decimalPlaces ?? 0);
      if (cost == null) {
        setState(() => _costError = l10n.invalidPrice);
        return;
      }
    }
    setState(() => _costError = null);

    // Codes never sit in stock without a PIN to guard them.
    if (!await ensurePinIsSet(context, reason: l10n.pinReasonCodes)) return;
    if (!mounted) return;

    final parsed = _parsed;
    final expiry = _expiry;
    setState(() => _saving = true);
    final ImportReport report;
    try {
      report = await container.read(voucherRepositoryProvider).addBatch(
            productId: product.id!,
            parsed: parsed,
            expiryAt: expiry == null ? null : expiryFromDate(expiry),
            costPerCardMinor: cost,
            costCurrencyCode: cost == null ? null : product.currencyCode,
            source: _method.name,
          );
    } on Exception {
      // The transaction rolled back. The error itself is not shown: a
      // database message can quote what was being written.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.batchSaveFailed)));
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    refreshVoucherData(container);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        content: Text(importReportText(
          l10n,
          locale: locale,
          added: report.added,
          duplicates: report.duplicates,
          emptyLines: report.emptyLines,
          invalidLines: report.invalidLines,
          saved: true,
        )),
      ));
    if (report.added > 0 && navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final product = widget.product;
    final currency = ref.watch(currencyMapProvider).value?[product.currencyCode];
    final toAdd = _parsed.codes.length - _existing;
    final hasSource = _source.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.addBatchTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(product.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          SegmentedButton<LoadMethod>(
            key: const ValueKey('load-method'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: LoadMethod.paste,
                label: Text(l10n.loadMethodPaste),
              ),
              ButtonSegment(
                value: LoadMethod.file,
                label: Text(l10n.loadMethodFile),
              ),
              // The camera is part of the barcode feature.
              if (featureOn(Feature.barcode))
                ButtonSegment(
                  value: LoadMethod.scan,
                  label: Text(l10n.loadMethodScan),
                ),
            ],
            selected: {_method},
            onSelectionChanged: (selection) {
              _method = selection.first;
              _refresh();
            },
          ),
          const SizedBox(height: 12),
          switch (_method) {
            LoadMethod.paste => TextField(
                key: const ValueKey('paste-field'),
                controller: _paste,
                minLines: 4,
                maxLines: 6,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                textDirection: TextDirection.ltr,
                onChanged: (_) => _refresh(),
                decoration: InputDecoration(
                  labelText: l10n.pasteLabel,
                  hintText: l10n.pasteHint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            LoadMethod.file => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('pick-file'),
                    onPressed: _pickFile,
                    icon: const Icon(Icons.attach_file),
                    label: Text(
                      l10n.pickFile,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_fileName != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        ltrIsolate(_fileName!),
                        key: const ValueKey('picked-file-name'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  if (_fileError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        l10n.fileReadFailed,
                        key: const ValueKey('file-error'),
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                ],
              ),
            LoadMethod.scan => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    key: const ValueKey('scan-start'),
                    onPressed: _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(
                      l10n.scanStart,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (_scanned.isNotEmpty)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.scannedCards(formatMinor(
                              _scanned.length,
                              decimals: 0,
                              locale: locale,
                            )),
                            key: const ValueKey('scanned-count'),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            _scanned = const [];
                            _refresh();
                          },
                          child: Text(l10n.clearScanned),
                        ),
                      ],
                    ),
                ],
              ),
          },
          if (_method != LoadMethod.scan) ...[
            const SizedBox(height: 12),
            Text(l10n.columnsLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            // Chosen once, by the user: nothing is guessed from the data.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (value, label) in [
                  (CodeColumns.codeOnly, l10n.columnsCodeOnly),
                  (CodeColumns.serialThenCode, l10n.columnsSerialCode),
                  (CodeColumns.codeThenSerial, l10n.columnsCodeSerial),
                ])
                  ChoiceChip(
                    key: ValueKey('columns-${value.name}'),
                    label: Text(label),
                    selected: _columns == value,
                    onSelected: (_) {
                      _columns = value;
                      _refresh();
                    },
                  ),
              ],
            ),
          ],
          if (hasSource) ...[
            const SizedBox(height: 16),
            _Preview(parsed: _parsed),
            const SizedBox(height: 8),
            Text(
              importReportText(
                l10n,
                locale: locale,
                added: toAdd,
                duplicates: _parsed.duplicateLines + _existing,
                emptyLines: _parsed.emptyLines,
                invalidLines: _parsed.invalidLines,
                headerSkipped: _parsed.headerSkipped,
              ),
              key: const ValueKey('import-summary'),
              style: theme.textTheme.titleSmall,
            ),
          ],
          const SizedBox(height: 8),
          ListTile(
            key: const ValueKey('batch-expiry'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(l10n.batchExpiryLabel),
            subtitle: Text(
              _expiry == null
                  ? l10n.noExpiry
                  : DateFormat.yMd(locale).format(_expiry!),
            ),
            trailing: _expiry == null
                ? null
                : IconButton(
                    tooltip: l10n.noExpiry,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _expiry = null),
                  ),
            onTap: _pickExpiry,
          ),
          SelectAllOnFocus(
            controller: _cost,
            child: TextField(
              key: const ValueKey('batch-cost'),
              controller: _cost,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.batchCostLabel(product.currencyCode),
                errorText: _costError,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('batch-save'),
            onPressed: toAdd > 0 && !_saving ? () => _save(currency) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                hasSource && toAdd <= 0 ? l10n.nothingToAdd : l10n.saveBatch,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The first five cards as they were understood — serial in full, code
/// masked — so a wrong column order is seen before anything is saved.
class _Preview extends StatelessWidget {
  const _Preview({required this.parsed});

  final CodeParseResult parsed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rows = parsed.codes.take(5).toList();
    if (rows.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      key: const ValueKey('import-preview'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.importPreviewTitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            for (final (index, row) in rows.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                // Codes and serials are left-to-right in both languages.
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  // A Wrap, not a Row: at a large system font the masked
                  // code alone is as wide as the box, and the serial then
                  // takes the next line instead of overflowing.
                  child: Wrap(
                    spacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        maskCode(row.code),
                        key: ValueKey('preview-code-$index'),
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(letterSpacing: 1),
                      ),
                      Text(
                        row.serial ?? '',
                        key: ValueKey('preview-serial-$index'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
