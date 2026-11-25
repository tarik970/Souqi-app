import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/cart.dart';
import '../../l10n/generated/app_localizations.dart';
import 'sale_providers.dart';

/// What [CashReceivedDialog] answers: an amount, or "clear the field".
class CashReceivedChoice {
  const CashReceivedChoice(this.amountMinor);

  /// Null = clear it.
  final int? amountMinor;
}

/// The optional "cash received" line of the sale screen's totals panel
/// (Settings → Selling, off by default): what the customer handed over, and
/// the change to give back.
///
/// A line that opens a small dialog, NOT a text field in the panel: the
/// keyboard collapses the totals panel to one line so the search results
/// have room, and a field inside the panel would vanish the moment it got
/// the focus.
///
/// Only arithmetic for the till: nothing here is stored with the invoice,
/// and Save still saves the sale as paid in full. A customer who pays LESS
/// than the total is what the "Credit / Partial" button is for.
class CashReceivedLine extends ConsumerWidget {
  const CashReceivedLine({super.key, required this.totals, required this.locale});

  final CartTotals totals;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currency = totals.currency;
    final stored = ref.watch(cashReceivedProvider);
    // Typed for another invoice currency: it means nothing for this one.
    final received =
        stored?.currencyCode == currency.code ? stored!.amountMinor : null;
    String money(int minor) => formatMinor(
          minor,
          decimals: currency.decimalPlaces,
          locale: locale,
          symbol: currency.symbol.isEmpty ? currency.code : currency.symbol,
        );
    final change = received == null ? null : received - totals.totalMinor;

    return Row(
      key: const ValueKey('cash-received-line'),
      children: [
        // Flexible on both sides: amounts in the millions at a large system
        // font are wider than the row.
        Flexible(
          child: TextButton.icon(
            key: const ValueKey('cash-received-button'),
            // A SMALL line: the panel has no height to spare on a small
            // phone at a large font, where every row above it is already
            // there (customer, discount, total, the two buttons).
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: () async {
              // Taken before the dialog: the panel (and its `ref`) is
              // replaced by the one-line total while the keyboard is up.
              final notifier = ref.read(cashReceivedProvider.notifier);
              final choice = await showDialog<CashReceivedChoice>(
                context: context,
                builder: (_) => CashReceivedDialog(
                  totals: totals,
                  locale: locale,
                  initialMinor: received,
                ),
              );
              if (choice == null) return;
              final amount = choice.amountMinor;
              notifier.set(
                amount == null
                    ? null
                    : CashReceived(
                        amountMinor: amount,
                        currencyCode: currency.code,
                      ),
              );
            },
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: Text(
              received == null
                  ? l10n.cashReceivedTitle
                  : l10n.cashReceivedValue(money(received)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (change != null)
          // ONE line, scaled down when it is too wide — never a second
          // line: the row must stay as low as the button beside it.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                change >= 0 ? l10n.changeShort(money(change)) : l10n.cashShort,
                key: const ValueKey('cash-received-change'),
                maxLines: 1,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: change >= 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Asks what the customer handed over and shows the change as it is typed.
/// A StatefulWidget that owns its controller and answers through
/// [Navigator.pop]: a [CashReceivedChoice], or nothing when cancelled.
class CashReceivedDialog extends StatefulWidget {
  const CashReceivedDialog({
    super.key,
    required this.totals,
    required this.locale,
    this.initialMinor,
  });

  final CartTotals totals;
  final String locale;
  final int? initialMinor;

  @override
  State<CashReceivedDialog> createState() => _CashReceivedDialogState();
}

class _CashReceivedDialogState extends State<CashReceivedDialog> {
  late final _controller = TextEditingController(
    text: widget.initialMinor == null
        ? ''
        : minorToPlainText(
            widget.initialMinor!,
            decimals: widget.totals.currency.decimalPlaces,
          ),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int? get _typed => parseAmountMinor(
        _controller.text,
        decimals: widget.totals.currency.decimalPlaces,
      );

  void _submit() {
    final amount = _typed;
    if (amount == null || amount <= 0) {
      setState(() => _error = AppLocalizations.of(context).amountInvalid);
      return;
    }
    Navigator.of(context).pop(CashReceivedChoice(amount));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final currency = widget.totals.currency;
    final label = currency.symbol.isEmpty ? currency.code : currency.symbol;
    String money(int minor) => formatMinor(
          minor,
          decimals: currency.decimalPlaces,
          locale: widget.locale,
          symbol: label,
        );
    final typed = _typed;
    final change = typed == null ? null : typed - widget.totals.totalMinor;

    return AlertDialog(
      key: const ValueKey('cash-received-dialog'),
      // Scrolls: with the keyboard up on a small phone there is room for
      // the field or for the buttons, not both.
      scrollable: true,
      title: Text(l10n.cashReceivedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${l10n.totalLabel}: ${money(widget.totals.totalMinor)}'),
          const SizedBox(height: 12),
          SelectAllOnFocus(
            controller: _controller,
            child: TextField(
              key: const ValueKey('cash-received-field'),
              controller: _controller,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _error = null),
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                suffixText: label,
                errorText: _error,
                errorMaxLines: 3,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (change != null && typed! > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                change >= 0 ? l10n.changeDue(money(change)) : l10n.cashShort,
                key: const ValueKey('cash-received-dialog-change'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: change >= 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
      actions: [
        if (widget.initialMinor != null)
          TextButton(
            key: const ValueKey('cash-received-clear'),
            onPressed: () =>
                Navigator.of(context).pop(const CashReceivedChoice(null)),
            child: Text(l10n.cashReceivedClear),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('cash-received-ok'),
          onPressed: _submit,
          child: Text(l10n.done),
        ),
      ],
    );
  }
}
