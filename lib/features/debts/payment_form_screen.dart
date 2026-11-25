import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/exchange.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../sale/sale_providers.dart';
import 'debt_providers.dart';
import 'debt_text.dart';
import 'debt_widgets.dart';
import 'receipt_screen.dart';

/// Records a payment from a customer: amount (with a "pay full balance"
/// shortcut), currency — converted to the base currency with the rate shown,
/// which can be changed for this payment and is stored with it — method and
/// note. Saving opens the receipt ("سند قبض"), ready to print or send.
///
/// Reached from the customer's Account tab and from the debtors list.
class RecordPaymentScreen extends ConsumerStatefulWidget {
  const RecordPaymentScreen({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<RecordPaymentScreen> createState() =>
      _RecordPaymentScreenState();
}

class _RecordPaymentScreenState extends ConsumerState<RecordPaymentScreen> {
  // Owned by this page for its whole life.
  final _amount = TextEditingController();
  final _rate = TextEditingController();
  final _note = TextEditingController();

  /// Null = the base currency.
  String? _currencyCode;
  PaymentMethod _method = PaymentMethod.cash;
  String? _amountError;
  String? _rateError;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _rate.dispose();
    _note.dispose();
    super.dispose();
  }

  void _selectCurrency(Currency currency, Currency base) {
    setState(() {
      _currencyCode = currency.code == base.code ? null : currency.code;
      _rate.text =
          currency.code == base.code ? '' : rateToPlainText(currency.rate);
      _amountError = null;
      _rateError = null;
    });
  }

  /// The rate typed for this payment, or null when it is not a rate.
  RateFraction? _typedRate() {
    try {
      return parseRateFraction(_rate.text);
    } on FormatException {
      return null;
    }
  }

  /// What the typed amount is worth in base minor units; null while the
  /// amount or the rate cannot be read.
  int? _baseValue(Currency currency, Currency base) {
    final amount =
        AmountField.parseAmount(_amount.text, decimals: currency.decimalPlaces);
    if (amount == null) return null;
    if (currency.code == base.code) return amount;
    final rate = _typedRate();
    if (rate == null) return null;
    return toBaseMinor(
      amountMinor: amount,
      fromDecimals: currency.decimalPlaces,
      fromRate: rate,
      baseDecimals: base.decimalPlaces,
    );
  }

  Future<void> _save(Currency currency, Currency base) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final amount =
        AmountField.parseAmount(_amount.text, decimals: currency.decimalPlaces);
    final foreign = currency.code != base.code;
    final rate = foreign ? _typedRate() : RateFraction.one;
    final value = _baseValue(currency, base);
    setState(() {
      _amountError = amount == null || (value != null && value <= 0)
          ? l10n.amountInvalid
          : null;
      _rateError = rate == null ? l10n.invalidNumber : null;
    });
    if (amount == null || rate == null || value == null || value <= 0) return;

    // Taken before the first await: a payment the user confirmed is recorded
    // and shown everywhere even if this page is closed meanwhile.
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _saving = true);
    final entry = await container.read(debtRepositoryProvider).recordPayment(
          customerId: widget.customerId,
          amountMinor: amount,
          currencyCode: currency.code,
          currencyDecimals: currency.decimalPlaces,
          rate: rate,
          baseCode: base.code,
          baseDecimals: base.decimalPlaces,
          method: _method,
          note: _note.text,
        );
    refreshDebtData(container);
    if (!navigator.mounted) return;
    navigator.pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ReceiptScreen(entryId: entry.id),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(baseMoneyProvider);
    final customer = ref.watch(customerProvider(widget.customerId)).value;
    final summary = ref.watch(accountSummaryProvider(widget.customerId)).value;
    final base = ref.watch(baseCurrencyProvider).value;
    final sellable = ref.watch(sellableCurrenciesProvider);
    final locale = ref.watch(appLocaleProvider).languageCode;

    if (base == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.recordPayment)));
    }
    final currencies = [
      base,
      for (final c in sellable)
        if (c.code != base.code) c,
    ];
    final currency = currencies.firstWhere(
      (c) => c.code == _currencyCode,
      orElse: () => base,
    );
    final foreign = currency.code != base.code;
    final value = _baseValue(currency, base);
    final balance = summary?.balanceBaseMinor;
    String label(Currency c) => c.symbol.isEmpty ? c.code : c.symbol;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recordPayment)),
      body: DebtLockGate(
        child: ListView(
        key: const ValueKey('payment-form'),
        padding: const EdgeInsets.all(16),
        children: [
          if (customer != null)
            Text(customer.name, style: theme.textTheme.titleLarge),
          if (balance != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BalanceText(balance, key: const ValueKey('payment-balance')),
            ),
          const SizedBox(height: 16),
          AmountField(
            key: const ValueKey('payment-amount'),
            controller: _amount,
            label: l10n.amountLabel,
            currencyLabel: label(currency),
            errorText: _amountError,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _amountError = null),
          ),
          if (balance != null && balance > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const ValueKey('payment-full-balance'),
                onPressed: () => setState(() {
                  // The balance is in the base currency, so is the shortcut.
                  _currencyCode = null;
                  _rate.text = '';
                  _amount.text =
                      minorToPlainText(balance, decimals: base.decimalPlaces);
                  _amountError = null;
                }),
                icon: const Icon(Icons.done_all, size: 18),
                label: Text(
                  '${l10n.payFullBalance} (${money(balance)})',
                  textAlign: TextAlign.start,
                ),
              ),
            ),
          if (currencies.length > 1) ...[
            const SizedBox(height: 8),
            Text(l10n.paymentCurrencyLabel, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in currencies)
                  ChoiceChip(
                    key: ValueKey('payment-currency-${c.code}'),
                    label: Text(c.code),
                    selected: c.code == currency.code,
                    onSelected: (_) => _selectCurrency(c, base),
                  ),
              ],
            ),
          ],
          if (foreign) ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('payment-rate'),
              controller: _rate,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              onChanged: (_) => setState(() => _rateError = null),
              decoration: InputDecoration(
                labelText:
                    l10n.paymentRateLabel(label(base), currency.code),
                errorText: _rateError,
                border: const OutlineInputBorder(),
              ),
            ),
            if (value != null && value > 0)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  l10n.paymentCountsAs(money(value)),
                  key: const ValueKey('payment-base-value'),
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
          ],
          if (value != null && balance != null && value > balance)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                // Whatever the balance was, what is left over is theirs.
                l10n.paymentOverBalance(money(value - balance)),
                key: const ValueKey('payment-over-balance'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.tertiary),
              ),
            ),
          const SizedBox(height: 16),
          Text(l10n.paymentMethodLabel, style: theme.textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final method in PaymentMethod.values)
                ChoiceChip(
                  key: ValueKey('payment-method-${method.name}'),
                  label: Text(paymentMethodLabel(l10n, method)),
                  selected: _method == method,
                  onSelected: (_) => setState(() => _method = method),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('payment-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: l10n.noteOptional,
              border: const OutlineInputBorder(),
            ),
          ),
          if (summary?.lastPaymentAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                l10n.lastPaymentOn(formatDay(summary!.lastPaymentAt!, locale)),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('payment-save'),
            onPressed: _saving ? null : () => _save(currency, base),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.save),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
