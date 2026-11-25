import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/exchange.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/due_dates.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customer_picker_screen.dart';
import '../customers/customers_providers.dart';
import '../debts/debt_providers.dart';
import '../debts/debt_text.dart';
import '../debts/debt_widgets.dart';
import '../security/pin_dialogs.dart';

/// How the seller says the sale was paid.
enum PayMode {
  /// Everything is paid now.
  full,

  /// Part is paid now; the rest goes onto the customer's account.
  partial,

  /// Nothing is paid now; all of it goes onto the customer's account.
  credit,
}

/// What the payment sheet decided.
class PaymentChoice {
  const PaymentChoice({required this.payment, this.customer});

  final SalePayment payment;

  /// The customer the sale now belongs to — the one that was attached, or
  /// the one picked in the sheet.
  final SaleCustomer? customer;
}

/// The numbers of a payment, worked out from what the seller chose. Pure, so
/// the rules are unit-tested without the sheet.
class PaymentMath {
  PaymentMath({
    required this.totals,
    required this.mode,
    required this.balanceBaseMinor,
    required this.limitBaseMinor,
    required this.useCredit,
    required this.partialPaidMinor,
  });

  final CartTotals totals;
  final PayMode mode;

  /// The customer's balance (0 with no customer, or while loading).
  final int balanceBaseMinor;
  final int? limitBaseMinor;
  final bool useCredit;

  /// What was typed into "amount paid" (partial mode), or null.
  final int? partialPaidMinor;

  int get totalMinor => totals.totalMinor;

  int _toBase(int minor) => convertMinor(
        amountMinor: minor,
        fromDecimals: totals.currency.decimalPlaces,
        fromRate: totals.currency.rate,
        toDecimals: totals.baseCurrency.decimalPlaces,
        toRate: totals.baseCurrency.rate,
      );

  /// The customer's credit balance in the INVOICE currency (0 when they
  /// have none).
  late final int creditAvailableMinor = balanceBaseMinor >= 0
      ? 0
      : convertMinor(
          amountMinor: -balanceBaseMinor,
          fromDecimals: totals.baseCurrency.decimalPlaces,
          fromRate: totals.baseCurrency.rate,
          toDecimals: totals.currency.decimalPlaces,
          toRate: totals.currency.rate,
        );

  /// How much of the invoice the credit balance pays.
  late final int creditUsedMinor = useCredit
      ? (creditAvailableMinor < totalMinor ? creditAvailableMinor : totalMinor)
      : 0;

  /// What is left to settle once the credit is used.
  int get dueNowMinor => totalMinor - creditUsedMinor;

  /// The amount typed for a partial payment is usable: more than nothing
  /// would be "on credit", all of it would be "paid in full".
  bool get partialIsValid {
    final paid = partialPaidMinor;
    return paid != null && paid > 0 && paid < dueNowMinor;
  }

  /// Money received now.
  late final int paidMinor = switch (mode) {
    PayMode.full => dueNowMinor,
    PayMode.partial => partialIsValid ? partialPaidMinor! : 0,
    PayMode.credit => 0,
  };

  /// New debt beyond what the credit balance covers.
  int get remainingMinor => dueNowMinor - paidMinor;

  /// What the sale charges to the account in all (credit used + new debt),
  /// in base minor units — what the ledger entry will be.
  late final int chargedBaseMinor = _toBase(totalMinor - paidMinor);

  int get newBalanceBaseMinor => balanceBaseMinor + chargedBaseMinor;

  /// The sale needs a customer: something goes onto an account.
  bool get needsCustomer => totalMinor - paidMinor > 0;

  /// The sale would take the customer over their credit limit.
  bool get overLimit =>
      limitBaseMinor != null &&
      chargedBaseMinor > 0 &&
      newBalanceBaseMinor > limitBaseMinor!;

  SalePayment payment({DateTime? dueAt, bool overrideCreditLimit = false}) =>
      SalePayment(
        paidMinor: paidMinor,
        creditUsedMinor: creditUsedMinor,
        dueAt: remainingMinor > 0 ? dueAt : null,
        overrideCreditLimit: overrideCreditLimit,
      );
}

/// The payment sheet behind the sale screen's "Credit / Partial" button.
///
/// (Save itself never comes here: a cash sale is one tap and is saved as
/// paid in full at once.) "Partial" takes the amount paid and puts the rest
/// on the customer's account; "On credit" puts all of it there. Both need a
/// customer, who can be picked right here. "Paid in full" is here too, for
/// the seller who wants the change worked out or pays the sale from the
/// customer's credit balance — and it never waits for a balance to load.
///
/// Also here: an optional "cash received" that shows the change to give
/// back; "use credit balance" for a customer the shop owes money to; the due
/// date of the new debt; and the credit-limit warning, with the numbers and
/// an override (the PIN when one is set — logged either way).
///
/// A StatefulWidget that owns its controllers and returns its result through
/// [Navigator.pop]: a [PaymentChoice], or nothing when dismissed.
class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({
    super.key,
    required this.totals,
    this.customer,
    this.initialMode = PayMode.credit,
  });

  /// What is chosen when the sheet opens. "On credit" by default: the sheet
  /// is opened by the "Credit / Partial" button, and putting the whole sale
  /// on the account is then one more tap; "Partial" is one chip away.
  final PayMode initialMode;

  /// The cart, already priced into the invoice currency.
  final CartTotals totals;

  /// The customer attached to the sale, if any.
  final SaleCustomer? customer;

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  final _paid = TextEditingController();
  final _received = TextEditingController();
  final _paidFocus = FocusNode();

  late PayMode _mode = widget.initialMode;
  late SaleCustomer? _customer = widget.customer;
  bool _useCredit = false;

  /// Null = the customer's default number of days.
  DateTime? _dueDate;
  String? _error;
  bool _confirming = false;

  @override
  void dispose() {
    _paid.dispose();
    _received.dispose();
    _paidFocus.dispose();
    super.dispose();
  }

  CartTotals get _totals => widget.totals;

  String _money(int minor) {
    final currency = _totals.currency;
    return formatMinor(
      minor,
      decimals: currency.decimalPlaces,
      locale: ref.read(appLocaleProvider).languageCode,
      symbol: currency.symbol.isEmpty ? currency.code : currency.symbol,
    );
  }

  void _setMode(PayMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
    if (mode == PayMode.partial) _paidFocus.requestFocus();
  }

  Future<void> _pickCustomer() async {
    final picked = await Navigator.of(context).push(
      MaterialPageRoute<SaleCustomer>(
        builder: (_) => const CustomerPickerScreen(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _customer = picked;
      _useCredit = false;
      _dueDate = null;
      _error = null;
    });
  }

  Future<void> _confirm(PaymentMath math, {required bool balanceLoaded}) async {
    if (_confirming) return;
    final l10n = AppLocalizations.of(context);
    if (_mode == PayMode.partial && !math.partialIsValid) {
      setState(() => _error = l10n.partialInvalid);
      return;
    }
    if (math.needsCustomer && _customer == null) {
      setState(() => _error = l10n.customerRequiredForDebt);
      return;
    }
    // Something goes onto an account: wait for the balance, so the limit is
    // judged on real numbers. (A cash sale never gets here.)
    if (math.needsCustomer && !balanceLoaded) return;

    var override = false;
    if (math.overLimit) {
      final navigator = Navigator.of(context);
      final container = ProviderScope.containerOf(context, listen: false);
      setState(() => _confirming = true);
      // With a PIN set, the PIN; without one, a plain confirmation. Either
      // way the override is written to the audit log with the sale.
      final pinSet = await container.read(pinRepositoryProvider).isSet();
      if (!mounted) return;
      final bool ok;
      if (pinSet) {
        ok = await requirePin(context, reason: l10n.pinReasonCreditLimit);
      } else {
        ok = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                key: const ValueKey('credit-limit-confirm'),
                scrollable: true,
                title: Text(l10n.creditLimitConfirmTitle),
                content: Text(_limitText(l10n, math)),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.cancel),
                  ),
                  FilledButton(
                    key: const ValueKey('credit-limit-confirm-yes'),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(l10n.overrideAndSave),
                  ),
                ],
              ),
            ) ??
            false;
      }
      if (!mounted) return;
      setState(() => _confirming = false);
      if (!ok) return;
      override = true;
      if (!navigator.mounted) return;
    }
    Navigator.of(context).pop(PaymentChoice(
      payment: math.payment(dueAt: _dueDate, overrideCreditLimit: override),
      customer: _customer,
    ));
  }

  String _limitText(AppLocalizations l10n, PaymentMath math) {
    final base = ref.read(baseMoneyProvider);
    return l10n.creditLimitWarning(
      base(math.balanceBaseMinor),
      base(math.chargedBaseMinor),
      base(math.newBalanceBaseMinor),
      base(math.limitBaseMinor ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final baseMoney = ref.watch(baseMoneyProvider);
    final decimals = _totals.currency.decimalPlaces;
    final customer = _customer;

    // The customer's account: read in the background. The cash path never
    // waits for it.
    final record = customer == null
        ? null
        : ref.watch(customerProvider(customer.customerId)).value;
    final summary = customer == null
        ? null
        : ref.watch(accountSummaryProvider(customer.customerId)).value;
    final balanceLoaded = customer == null || (record != null && summary != null);
    final balance = summary?.balanceBaseMinor ?? 0;
    final dueDays = record?.defaultDueDays ??
        ref.watch(debtDefaultDueDaysProvider).value ??
        30;

    final math = PaymentMath(
      totals: _totals,
      mode: _mode,
      balanceBaseMinor: balance,
      limitBaseMinor: record?.creditLimitBaseMinor,
      useCredit: _useCredit,
      partialPaidMinor: parseAmountMinor(_paid.text, decimals: decimals),
    );
    final received = parseAmountMinor(_received.text, decimals: decimals);
    final dueDate = _dueDate ?? nextDueAfter(DateTime.now(), dueDays);
    final showCustomer = customer != null || _mode != PayMode.full;
    final blocked = math.needsCustomer && customer != null && !balanceLoaded;

    String modeLabel(PayMode mode) => switch (mode) {
          PayMode.full => l10n.payFull,
          PayMode.partial => l10n.payPartial,
          PayMode.credit => l10n.payCredit,
        };

    return Padding(
      // Above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        key: const ValueKey('payment-sheet'),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.paymentSheetTitle,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Text(
                      _money(math.totalMinor),
                      key: const ValueKey('payment-sheet-total'),
                      maxLines: 1,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Chips in a Wrap, not a segmented button: three labels do not
            // fit one row on a small phone at a large system font.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final mode in PayMode.values)
                  ChoiceChip(
                    key: ValueKey('pay-mode-${mode.name}'),
                    label: Text(modeLabel(mode)),
                    selected: _mode == mode,
                    onSelected: (_) => _setMode(mode),
                  ),
              ],
            ),
            if (showCustomer) ...[
              const SizedBox(height: 8),
              _CustomerRow(
                customer: customer,
                balance: customer != null && summary != null ? balance : null,
                limit: record?.creditLimitBaseMinor,
                onPick: _pickCustomer,
              ),
            ],
            if (math.creditAvailableMinor > 0)
              CheckboxListTile(
                key: const ValueKey('pay-use-credit'),
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: _useCredit,
                onChanged: (value) =>
                    setState(() => _useCredit = value ?? false),
                title: Text(
                  l10n.useCreditBalance(_money(math.creditAvailableMinor)),
                ),
                subtitle: _useCredit
                    ? Text(
                        l10n.toPayNow(_money(math.dueNowMinor)),
                        key: const ValueKey('pay-due-now'),
                      )
                    : null,
              ),
            if (_mode == PayMode.partial) ...[
              const SizedBox(height: 8),
              AmountField(
                key: const ValueKey('pay-amount-paid'),
                controller: _paid,
                focusNode: _paidFocus,
                label: l10n.amountPaidLabel,
                currencyLabel: _totals.currency.symbol.isEmpty
                    ? _totals.currency.code
                    : _totals.currency.symbol,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
            if (math.remainingMinor > 0) ...[
              const SizedBox(height: 8),
              Text(
                l10n.remainingAsDebt(_money(math.remainingMinor)),
                key: const ValueKey('pay-remaining'),
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('pay-due-date'),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: dueDate,
                      firstDate: DateTime(now.year, now.month, now.day),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null && mounted) {
                      setState(() => _dueDate = picked);
                    }
                  },
                  icon: const Icon(Icons.event, size: 18),
                  label: Text(l10n.dueOnLabel(formatDay(dueDate, locale))),
                ),
              ),
            ],
            if (math.paidMinor > 0) ...[
              const SizedBox(height: 8),
              AmountField(
                key: const ValueKey('pay-cash-received'),
                controller: _received,
                label: l10n.cashReceivedLabel,
                currencyLabel: _totals.currency.symbol.isEmpty
                    ? _totals.currency.code
                    : _totals.currency.symbol,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
              ),
              if (received != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    received >= math.paidMinor
                        ? l10n.changeDue(_money(received - math.paidMinor))
                        : l10n.cashShort,
                    key: const ValueKey('pay-change'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: received >= math.paidMinor
                          ? theme.colorScheme.primary
                          : theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
            if (math.overLimit && balanceLoaded) ...[
              const SizedBox(height: 8),
              DecoratedBox(
                key: const ValueKey('pay-limit-warning'),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.creditLimitWarningTitle,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        l10n.creditLimitWarning(
                          baseMoney(math.balanceBaseMinor),
                          baseMoney(math.chargedBaseMinor),
                          baseMoney(math.newBalanceBaseMinor),
                          baseMoney(math.limitBaseMinor ?? 0),
                        ),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  key: const ValueKey('pay-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('pay-save'),
              // Nothing to wait for on the cash path; a sale that goes onto
              // an account waits for that account.
              onPressed: _confirming || blocked
                  ? null
                  : () => _confirm(math, balanceLoaded: balanceLoaded),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  math.overLimit && balanceLoaded
                      ? l10n.overrideAndSave
                      : l10n.save,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The customer of the sale inside the payment sheet: who, what they owe,
/// their limit — or "choose a customer" when the sale has none yet.
class _CustomerRow extends ConsumerWidget {
  const _CustomerRow({
    required this.customer,
    required this.balance,
    required this.limit,
    required this.onPick,
  });

  final SaleCustomer? customer;

  /// Null while the account is loading.
  final int? balance;
  final int? limit;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(baseMoneyProvider);
    final current = customer;
    if (current == null) {
      return OutlinedButton.icon(
        key: const ValueKey('pay-choose-customer'),
        onPressed: onPick,
        icon: const Icon(Icons.person_add_alt),
        label: Text(l10n.chooseCustomer),
      );
    }
    return Row(
      key: const ValueKey('pay-customer'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(Icons.person, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              if (balance != null)
                Text(
                  [
                    balanceInWords(l10n, balance!, money.call),
                    if (limit != null)
                      '${l10n.creditLimitLabel}: ${money(limit!)}',
                  ].join(' · '),
                  key: const ValueKey('pay-customer-balance'),
                  style: theme.textTheme.bodySmall,
                ),
            ],
          ),
        ),
        TextButton(
          key: const ValueKey('pay-change-customer'),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          onPressed: onPick,
          child: Text(l10n.changeCustomer),
        ),
      ],
    );
  }
}
