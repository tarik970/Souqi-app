import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/licensing/license_status.dart';
import '../../core/logging/error_log.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/widgets/load_error_view.dart';
import '../../core/widgets/number_pad.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_return.dart';
import '../../domain/models/product.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/archive_providers.dart';
import '../license/license_gate.dart';
import '../security/pin_dialogs.dart';
import 'return_paper.dart';
import 'return_screen.dart';
import 'returns_providers.dart';

/// "5,000 ل.س" in the currency of an invoice, for the app language.
String Function(int minor) invoiceMoney(WidgetRef ref, String currencyCode) {
  final locale = ref.watch(appLocaleProvider).languageCode;
  final currency = ref
      .watch(currenciesProvider)
      .value
      ?.where((c) => c.code == currencyCode)
      .firstOrNull;
  return (minor) => formatMinor(
        minor,
        decimals: currency?.decimalPlaces ?? 0,
        locale: locale,
        symbol: currency == null || currency.symbol.isEmpty
            ? currencyCode
            : currency.symbol,
      );
}

/// RETURN ITEMS ("مرتجع"), from an invoice: its lines with what is still
/// returnable of each (sold minus already returned), a quantity per line
/// typed on the number pad, "Return all", and the refund — worked out from
/// the original invoice — shown as it grows.
///
/// THE NUMBER PAD types into the line that was tapped, by the rule of every
/// numeric entry in the app: the first key REPLACES the value the line
/// shows, later keys append.
///
/// A CARD sold from code stock is not returned by a number: each returned
/// card is one of the codes of its line, ticked, with what becomes of it —
/// voided (the default: it was printed or handed over) or put back in
/// stock.
///
/// "Continue" asks how the refund is given back and why ([ReturnConfirmDialog]
/// — with the refund total, before anything is saved), then the PIN when
/// one is set, and saves the return in one transaction. The document it
/// made opens in place of this screen.
class ReturnItemsScreen extends ConsumerStatefulWidget {
  const ReturnItemsScreen({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  ConsumerState<ReturnItemsScreen> createState() => _ReturnItemsScreenState();
}

class _ReturnItemsScreenState extends ConsumerState<ReturnItemsScreen> {
  /// What was typed for each line, by invoice-item id ("2.5").
  final _text = <int, String>{};

  /// Lines whose value is still the one they were given — by "Return all"
  /// or by tapping them: the next key replaces it.
  final _pristine = <int>{};

  /// The line the number pad types into.
  int? _active;

  /// The ticked card codes: code id → what becomes of it.
  final _codes = <int, CodeDisposal>{};

  bool _saving = false;

  static const int _maxDigits = 9;

  /// A line of goods, or one that was sold in fractions, is returned in
  /// fractions too; a service sold whole is returned whole.
  static int _decimalsOf(ReturnableLine line) =>
      line.item.kind == ProductKind.goods ||
              line.item.qtyThousandths % 1000 != 0
          ? 3
          : 0;

  /// What is being returned of [line], in thousandths; -1 when what was
  /// typed is not a quantity.
  int _qtyOf(ReturnableLine line) {
    if (line.hasCodes) {
      return line.codes.where((c) => _codes.containsKey(c.id)).length * 1000;
    }
    final text = _text[line.item.id] ?? '';
    if (text.isEmpty) return 0;
    return parseQuantityThousandths(text) ?? -1;
  }

  bool _isInvalid(ReturnableLine line) {
    final qty = _qtyOf(line);
    return qty < 0 || qty > line.remainingThousandths;
  }

  /// The line the pad types into: the one that was tapped, else the first
  /// that takes a number.
  ReturnableLine? _activeLine(List<ReturnableLine> lines) {
    final typed = [
      for (final line in lines)
        if (!line.hasCodes && line.remainingThousandths > 0) line,
    ];
    if (typed.isEmpty) return null;
    return typed.where((l) => l.item.id == _active).firstOrNull ?? typed.first;
  }

  void _focus(int id) => setState(() {
        _active = id;
        // Tapping a line is restating its number.
        _pristine.add(id);
      });

  void _setText(int id, String value) => setState(() {
        _active = id;
        _pristine.remove(id);
        _text[id] = value;
      });

  String _buffer(int id) => _pristine.contains(id) ? '' : (_text[id] ?? '');

  void _tapDigit(ReturnableLine line, String digit) {
    final id = line.item.id!;
    var text = _buffer(id);
    if (text.contains('.')) {
      final decimals = text.length - text.indexOf('.') - 1;
      if (decimals >= _decimalsOf(line)) return;
    } else if (text == '0') {
      text = '';
    }
    if (text.replaceAll('.', '').length >= _maxDigits) return;
    _setText(id, '$text$digit');
  }

  void _tapSeparator(ReturnableLine line) {
    if (_decimalsOf(line) == 0) return;
    final id = line.item.id!;
    final text = _buffer(id);
    if (text.contains('.')) return;
    _setText(id, text.isEmpty ? '0.' : '$text.');
  }

  void _backspace(ReturnableLine line) {
    final id = line.item.id!;
    // On a value that is still selected, backspace clears it outright.
    if (_pristine.contains(id)) {
      _setText(id, '');
      return;
    }
    final text = _text[id] ?? '';
    _setText(id, text.isEmpty ? '' : text.substring(0, text.length - 1));
  }

  /// Everything that is still returnable: every line in full, every card.
  void _returnAll(List<ReturnableLine> lines) => setState(() {
        for (final line in lines) {
          if (line.hasCodes) {
            for (final code in line.codes) {
              _codes.putIfAbsent(code.id, () => CodeDisposal.voidCode);
            }
          } else if (line.remainingThousandths > 0) {
            final id = line.item.id!;
            _text[id] = quantityToPlainText(line.remainingThousandths);
            _pristine.add(id);
          }
        }
      });

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _continue(List<ReturnableLine> lines) async {
    if (_saving) return;
    // A return is blocked exactly where a sale is.
    if (!licenseAllows(context, LicensedAction.sell)) return;
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    // Taken before the first await: a return the user confirmed is saved
    // and shown everywhere even if this screen is closed meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = container.read(invoiceCorrectionRepositoryProvider);
    final requests = [
      for (final line in lines)
        if (_qtyOf(line) > 0)
          ReturnLineRequest(
            invoiceItemId: line.item.id!,
            qtyThousandths: _qtyOf(line),
            codes: {
              for (final code in line.codes)
                if (_codes.containsKey(code.id)) code.id: _codes[code.id]!,
            },
          ),
    ];
    if (requests.isEmpty) return;

    setState(() => _saving = true);
    try {
      final preview = await repository.previewReturn(
        widget.invoiceId,
        {for (final r in requests) r.invoiceItemId: r.qtyThousandths},
      );
      if (!mounted) return;
      final choice = await showDialog<ReturnChoice>(
        context: context,
        builder: (_) => ReturnConfirmDialog(
          preview: preview,
          cards: requests.fold(0, (sum, r) => sum + r.codes.length),
        ),
      );
      if (choice == null || !mounted) return;
      if (!await requirePinIfSet(context, reason: l10n.pinReasonReturn)) {
        return;
      }
      final saved = await repository.saveReturn(ReturnDraft(
        invoiceId: widget.invoiceId,
        lines: requests,
        method: choice.method,
        reason: choice.reason,
      ));
      refreshAfterCorrection(container);
      if (!navigator.mounted) return;
      // The document, in place of this screen: this output is the original.
      navigator.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => ReturnScreen(returnId: saved.id),
      ));
    } on LicenseRequiredException {
      if (mounted) showLicenseNeeded(context, LicensedAction.sell);
    } on ReturnQuantityException {
      // Returned from another screen meanwhile: read again what is left.
      refreshAfterCorrection(container);
      _snack(l10n.returnChanged);
    } on ReturnCodesException {
      refreshAfterCorrection(container);
      _snack(l10n.returnChanged);
    } on InvoiceVoidedException {
      refreshAfterCorrection(container);
      _snack(l10n.voidAlready);
    } on Object catch (error, stack) {
      reportError(error, stack, context: 'return');
      _snack(l10n.saveFailedGeneric);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final invoice = ref.watch(archivedInvoiceProvider(widget.invoiceId)).value;
    final lines = ref.watch(returnableLinesProvider(widget.invoiceId));
    final loaded = lines.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.returnItemsTitle),
        actions: [
          if (loaded != null && loaded.any((l) => l.remainingThousandths > 0))
            TextButton(
              key: const ValueKey('return-all'),
              onPressed: _saving ? null : () => _returnAll(loaded),
              child: Text(l10n.returnAll),
            ),
        ],
      ),
      body: lines.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, stack) => LoadErrorView(e, stack),
        data: (data) => invoice == null
            ? Center(child: Text(l10n.invoiceNotFound))
            : _body(context, invoice, data),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    Invoice invoice,
    List<ReturnableLine> lines,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = invoiceMoney(ref, invoice.currencyCode);
    final active = _activeLine(lines);
    final anyInvalid = lines.any(_isInvalid);
    final quantities = {
      for (final line in lines)
        if (_qtyOf(line) > 0) line.item.id!: _qtyOf(line),
    };
    // The refund, from the original invoice, as the quantities are typed.
    int? refund;
    if (!anyInvalid && quantities.isNotEmpty) {
      try {
        refund = computeRefund(
          invoice: invoice,
          returnedBefore: {
            for (final line in lines) line.item.id!: line.returnedThousandths,
          },
          returning: quantities,
        ).refundMinor;
      } on ReturnQuantityException {
        refund = null;
      }
    }
    final nothingLeft = lines.every((l) => l.remainingThousandths == 0);
    // The pad makes way for the system keyboard, should one ever be up.
    final keyboardUp = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Column(
      children: [
        Expanded(
          child: ListView(
            key: const ValueKey('return-lines'),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  nothingLeft
                      ? l10n.returnNothingLeft
                      : l10n.returnItemsHint(
                          formatMinor(
                            invoice.invoiceNo,
                            decimals: 0,
                            locale: locale,
                          ),
                        ),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
              for (final (index, line) in lines.indexed)
                _LineCard(
                  index: index,
                  line: line,
                  locale: locale,
                  text: _text[line.item.id] ?? '',
                  active: active?.item.id == line.item.id,
                  selected: _pristine.contains(line.item.id),
                  invalid: _isInvalid(line),
                  codes: _codes,
                  onTap: () => _focus(line.item.id!),
                  onCode: (codeId, disposal) => setState(() {
                    if (disposal == null) {
                      _codes.remove(codeId);
                    } else {
                      _codes[codeId] = disposal;
                    }
                  }),
                ),
            ],
          ),
        ),
        Material(
          elevation: 8,
          color: theme.colorScheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.returnRefundTotal,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Scaled down, never cut: a refund in the millions
                      // at a large system font.
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerEnd,
                          child: Text(
                            refund == null ? '—' : money(refund),
                            key: const ValueKey('return-refund-preview'),
                            maxLines: 1,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (active != null && !keyboardUp)
                    NumberPad(
                      locale: locale,
                      separatorEnabled: _decimalsOf(active) > 0,
                      onDigit: (digit) => _tapDigit(active, digit),
                      onSeparator: () => _tapSeparator(active),
                      onBackspace: () => _backspace(active),
                      onClear: () => _setText(active.item.id!, ''),
                    ),
                  const SizedBox(height: 4),
                  FilledButton(
                    key: const ValueKey('return-continue'),
                    onPressed: refund == null || _saving
                        ? null
                        : () => _continue(lines),
                    child: Text(l10n.continueAction),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One line of the invoice on the return screen.
class _LineCard extends StatelessWidget {
  const _LineCard({
    required this.index,
    required this.line,
    required this.locale,
    required this.text,
    required this.active,
    required this.selected,
    required this.invalid,
    required this.codes,
    required this.onTap,
    required this.onCode,
  });

  /// Its position on the invoice: names its keys (`return-line-0`).
  final int index;
  final ReturnableLine line;
  final String locale;

  /// What was typed for it.
  final String text;

  /// The number pad types into this line.
  final bool active;

  /// Its value is still selected: the next key replaces it.
  final bool selected;
  final bool invalid;
  final Map<int, CodeDisposal> codes;
  final VoidCallback onTap;
  final void Function(int codeId, CodeDisposal? disposal) onCode;

  String _qty(int thousandths) {
    final qty = formatQuantity(thousandths, locale: locale);
    final unit = line.item.unitName;
    return unit == null || unit.isEmpty ? qty : '$qty $unit';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final left = line.remainingThousandths;
    final takesNumber = !line.hasCodes && left > 0;

    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          line.item.productName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 2),
        Text(
          left == 0
              ? l10n.returnLineDone(_qty(line.item.qtyThousandths))
              : l10n.returnLineLeft(
                  _qty(line.item.qtyThousandths),
                  _qty(left),
                ),
          key: ValueKey('return-left-$index'),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );

    return Card(
      key: ValueKey('return-line-$index'),
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: takesNumber ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: summary),
                  if (takesNumber) ...[
                    const SizedBox(width: 8),
                    _QtyBox(
                      index: index,
                      value: text.isEmpty
                          ? localizeDigits('0', locale)
                          : localizeDigits(text, locale),
                      muted: text.isEmpty,
                      active: active,
                      selected: active && selected && text.isNotEmpty,
                      invalid: invalid,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (line.hasCodes)
            for (final code in line.codes)
              _CodeRow(
                code: code,
                disposal: codes[code.id],
                onChanged: (disposal) => onCode(code.id, disposal),
              ),
          if (line.hasCodes) const SizedBox(height: 4),
        ],
      ),
    );
  }
}

/// The quantity of a line, as the number pad types it.
class _QtyBox extends StatelessWidget {
  const _QtyBox({
    required this.index,
    required this.value,
    required this.muted,
    required this.active,
    required this.selected,
    required this.invalid,
  });

  final int index;
  final String value;

  /// Nothing typed yet: the 0 is a placeholder.
  final bool muted;
  final bool active;

  /// Drawn like selected text: the next key replaces it.
  final bool selected;
  final bool invalid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = invalid
        ? theme.colorScheme.error
        : active
            ? theme.colorScheme.primary
            : theme.dividerColor;
    return Container(
      width: 96,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: border, width: active ? 2 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          key: selected ? ValueKey('return-qty-selected-$index') : null,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: selected
              ? BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Text(
            value,
            key: ValueKey('return-qty-$index'),
            maxLines: 1,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: invalid
                  ? theme.colorScheme.error
                  : selected
                      ? theme.colorScheme.onPrimaryContainer
                      : muted
                          ? theme.colorScheme.outline
                          : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// One card of a line: ticked = it comes back; then what becomes of it.
class _CodeRow extends StatelessWidget {
  const _CodeRow({
    required this.code,
    required this.disposal,
    required this.onChanged,
  });

  final VoucherCodeView code;

  /// Null = the card stays with the customer.
  final CodeDisposal? disposal;
  final ValueChanged<CodeDisposal?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final chosen = disposal != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => onChanged(chosen ? null : CodeDisposal.voidCode),
          child: Row(
            children: [
              Checkbox(
                key: ValueKey('return-code-${code.id}'),
                value: chosen,
                onChanged: (on) =>
                    onChanged(on == true ? CodeDisposal.voidCode : null),
              ),
              Expanded(
                // A code is one left-to-right run in both app languages.
                child: Text(
                  code.masked,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(letterSpacing: 1),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        if (chosen)
          // Sideways scroll: two chips with long words at a large font are
          // wider than a small phone.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.fromSTEB(48, 0, 12, 4),
            child: Row(
              children: [
                ChoiceChip(
                  key: ValueKey('return-code-void-${code.id}'),
                  label: Text(l10n.codeVoid),
                  selected: disposal == CodeDisposal.voidCode,
                  onSelected: (_) => onChanged(CodeDisposal.voidCode),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  key: ValueKey('return-code-stock-${code.id}'),
                  label: Text(l10n.codeReturn),
                  selected: disposal == CodeDisposal.returnToStock,
                  onSelected: (_) => onChanged(CodeDisposal.returnToStock),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// How a return is refunded, and why — what [ReturnConfirmDialog] pops.
class ReturnChoice {
  const ReturnChoice({required this.method, this.reason});

  final RefundMethod method;
  final String? reason;
}

/// THE REFUND, BEFORE IT IS CONFIRMED: the total, how it is given back —
/// cash; off the customer's debt (the rest in cash); or kept as their credit
/// — and an optional reason. The two account methods are only there for an
/// invoice with a customer, with the debt ledger on.
///
/// It opens on what the sale suggests: a sale on credit to a customer who
/// still owes reduces the debt first, everything else is cash. The seller
/// can change it.
///
/// Owns its controller for its whole life and returns the choice through
/// [Navigator.pop]; nothing when cancelled.
class ReturnConfirmDialog extends ConsumerStatefulWidget {
  const ReturnConfirmDialog({
    super.key,
    required this.preview,
    this.cards = 0,
  });

  final ReturnPreview preview;

  /// Card codes that come back with this return.
  final int cards;

  @override
  ConsumerState<ReturnConfirmDialog> createState() =>
      _ReturnConfirmDialogState();
}

class _ReturnConfirmDialogState extends ConsumerState<ReturnConfirmDialog> {
  final _reason = TextEditingController();

  bool get _ledger => featureOn(Feature.debt) && widget.preview.hasCustomer;

  late RefundMethod _method = defaultRefundMethod(
    invoice: widget.preview.invoice,
    owedMinor: widget.preview.owedMinor,
    ledgerOn: _ledger,
  );

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = widget.preview;
    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = invoiceMoney(ref, preview.invoice.currencyCode);
    final split = preview.split(_method);
    final methods = [
      RefundMethod.cash,
      // Nothing to reduce when nothing is owed.
      if (_ledger && preview.owedMinor > 0) RefundMethod.debt,
      if (_ledger) RefundMethod.credit,
    ];

    Widget part(String label, int amount, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              const SizedBox(width: 8),
              // Scaled down, never cut: amounts run into the millions.
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerEnd,
                  child: Text(
                    money(amount),
                    key: key,
                    maxLines: 1,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );

    return AlertDialog(
      key: const ValueKey('return-confirm-dialog'),
      // Scrolls: with the keyboard up on a small phone at a large font the
      // total, the methods, the reason and the buttons do not all fit.
      scrollable: true,
      title: Text(l10n.returnConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.returnRefundTotal,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              money(preview.refund.refundMinor),
              key: const ValueKey('return-confirm-total'),
              maxLines: 1,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          if (widget.cards > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.cardsCount(
                  formatMinor(widget.cards, decimals: 0, locale: locale),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 12),
          Text(l10n.returnRefundMethod, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            children: [
              for (final method in methods)
                ChoiceChip(
                  key: ValueKey('refund-method-${method.name}'),
                  label: Text(refundMethodLabel(l10n, method)),
                  selected: _method == method,
                  onSelected: (_) => setState(() => _method = method),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // What that comes to, part by part.
          if (split.debtMinor > 0)
            part(
              l10n.refundMethodDebt,
              split.debtMinor,
              key: const ValueKey('refund-part-debt'),
            ),
          if (split.creditMinor > 0)
            part(
              l10n.refundMethodCredit,
              split.creditMinor,
              key: const ValueKey('refund-part-credit'),
            ),
          if (split.cashMinor > 0)
            part(
              l10n.refundCashBack,
              split.cashMinor,
              key: const ValueKey('refund-part-cash'),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('return-reason'),
            controller: _reason,
            maxLength: 120,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.returnReasonOptional,
              counterText: '',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('return-confirm'),
          onPressed: () => Navigator.of(context).pop(
            ReturnChoice(method: _method, reason: _reason.text.trim()),
          ),
          child: Text(l10n.returnConfirmAction),
        ),
      ],
    );
  }
}
