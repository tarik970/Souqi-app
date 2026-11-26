import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import '../debts/debt_providers.dart';
import 'account_form_screen.dart';
import 'customers_providers.dart';

/// Add or edit a customer: name (required), phone and notes — and, with the
/// debt ledger on, an optional credit limit and number of days to pay.
///
/// When ADDING, the form can also take the customer's first card / account
/// number and provider, so "this card is not registered yet" at the till is
/// one page: name, number, Save. The rest of the account (package, renewal
/// period) is filled in on the customer's page afterwards.
///
/// Pops with the new customer as a [SaleCustomer] when one was created, so
/// the sale screen's picker can attach it straight away; with nothing after
/// an edit or when cancelled.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({
    super.key,
    this.customer,
    this.initialName = '',
    this.initialPhone = '',
    this.initialAccountNumber = '',
  });

  /// Null when adding.
  final Customer? customer;

  /// What was typed into the search box before "New customer" was tapped.
  final String initialName;
  final String initialPhone;
  final String initialAccountNumber;

  @override
  ConsumerState<CustomerFormScreen> createState() =>
      _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _notes;
  late final TextEditingController _accountNumber;
  late final TextEditingController _provider;
  late final TextEditingController _creditLimit;
  late final TextEditingController _dueDays;
  bool _saving = false;

  Customer? get _initial => widget.customer;

  bool get _withAccount => _initial == null && featureOn(Feature.accounts);

  @override
  void initState() {
    super.initState();
    final c = _initial;
    _name = TextEditingController(text: c?.name ?? widget.initialName);
    _phone = TextEditingController(text: c?.phone ?? widget.initialPhone);
    _notes = TextEditingController(text: c?.notes ?? '');
    _accountNumber = TextEditingController(text: widget.initialAccountNumber);
    _provider = TextEditingController();
    // The limit is prefilled once the base currency (its decimals) is known.
    _creditLimit = TextEditingController();
    _dueDays = TextEditingController(text: c?.defaultDueDays?.toString() ?? '');
    final limit = c?.creditLimitBaseMinor;
    if (limit != null) {
      ref.read(baseCurrencyProvider.future).then((base) {
        if (mounted && _creditLimit.text.isEmpty) {
          _creditLimit.text =
              minorToPlainText(limit, decimals: base.decimalPlaces);
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _accountNumber.dispose();
    _provider.dispose();
    _creditLimit.dispose();
    _dueDays.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final navigator = Navigator.of(context);
    // The lists are refreshed through the container: the save must show up
    // even if this page was closed while it ran.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(customerRepositoryProvider);
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final notes = _notes.text.trim();
    final accountNumber = _withAccount ? _accountNumber.text.trim() : '';
    final provider = _provider.text.trim();
    // Debt ledger: both optional, both already checked by their validators.
    final debtOn = featureOn(Feature.debt);
    final base = await ref.read(baseCurrencyProvider.future);
    if (!mounted) return;
    final creditLimit = _creditLimit.text.trim().isEmpty
        ? null
        : parseAmountMinor(_creditLimit.text, decimals: base.decimalPlaces);
    final dueDays = int.tryParse(normalizeDigits(_dueDays.text.trim()));

    if (normalizeCode(accountNumber).isNotEmpty) {
      final duplicates = await repository.findDuplicateAccounts(
        accountNumber,
        provider: provider,
      );
      if (!mounted) return;
      if (duplicates.isNotEmpty) {
        final proceed = await confirmDuplicateAccount(
          context,
          accountNumber: accountNumber,
          duplicates: duplicates,
        );
        if (!proceed || !mounted) return;
      }
    }

    setState(() => _saving = true);
    final initial = _initial;
    if (initial != null) {
      await repository.update(initial.copyWith(
        name: name,
        phone: () => phone,
        notes: () => notes,
        // With the ledger off the fields are not shown: keep what is stored.
        creditLimitBaseMinor: debtOn ? () => creditLimit : null,
        defaultDueDays: debtOn ? () => dueDays : null,
      ));
      refreshCustomerData(container);
      if (navigator.mounted) navigator.pop();
      return;
    }

    final hasAccount = normalizeCode(accountNumber).isNotEmpty;
    final (customerId, accountId) = await repository.insertWithAccount(
      Customer(
        name: name,
        phone: phone,
        notes: notes,
        creditLimitBaseMinor: debtOn ? creditLimit : null,
        defaultDueDays: debtOn ? dueDays : null,
      ),
      account: hasAccount
          ? CustomerAccount(
              customerId: 0, // replaced by the new customer's id
              accountNumber: accountNumber,
              provider: provider,
            )
          : null,
    );
    refreshCustomerData(container);
    if (!navigator.mounted) return;
    navigator.pop(SaleCustomer(
      customerId: customerId,
      name: name,
      phone: phone.isEmpty ? null : phone,
      accountId: accountId,
      accountNumber: accountId == null ? null : accountNumber,
      accountProvider: accountId == null || provider.isEmpty ? null : provider,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final debtOn = featureOn(Feature.debt);
    final base = ref.watch(baseCurrencyProvider).value;
    final shopDueDays = ref.watch(debtDefaultDueDaysProvider).value ?? 30;

    return Scaffold(
      appBar: AppBar(
        title: Text(_initial == null ? l10n.addCustomer : l10n.editCustomer),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const ValueKey('customer-name-field'),
              controller: _name,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: l10n.customerName),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('customer-phone-field'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.customerPhone,
                hintText: l10n.whatsAppPhoneHint,
              ),
              // Optional — but text with no digit in it is not a phone.
              validator: (v) {
                final text = v?.trim() ?? '';
                return text.isEmpty || normalizePhone(text).isNotEmpty
                    ? null
                    : l10n.invalidPhone;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('customer-notes-field'),
              controller: _notes,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.notesLabel),
            ),
            if (debtOn) ...[
              const SizedBox(height: 12),
              SelectAllOnFocus(
                controller: _creditLimit,
                child: TextFormField(
                  key: const ValueKey('customer-credit-limit-field'),
                  controller: _creditLimit,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.customerCreditLimitLabel,
                    suffixText: base == null
                        ? null
                        : (base.symbol.isEmpty ? base.code : base.symbol),
                  ),
                  validator: (v) {
                    final text = v?.trim() ?? '';
                    if (text.isEmpty) return null;
                    final minor = parseAmountMinor(
                      text,
                      decimals: base?.decimalPlaces ?? 0,
                    );
                    return minor == null ? l10n.invalidNumber : null;
                  },
                ),
              ),
              const SizedBox(height: 12),
              SelectAllOnFocus(
                controller: _dueDays,
                child: TextFormField(
                  key: const ValueKey('customer-due-days-field'),
                  controller: _dueDays,
                  keyboardType: TextInputType.number,
                  textDirection: TextDirection.ltr,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: l10n.customerDueDaysLabel,
                    helperText: l10n.customerDueDaysHint(
                      localizeDigits('$shopDueDays',
                          Localizations.localeOf(context).languageCode),
                    ),
                    helperMaxLines: 2,
                  ),
                  validator: (v) {
                    final text = normalizeDigits(v?.trim() ?? '');
                    if (text.isEmpty) return null;
                    final days = int.tryParse(text);
                    return days == null || days < 0 || days > 3650
                        ? l10n.invalidNumber
                        : null;
                  },
                ),
              ),
            ],
            if (_withAccount) ...[
              const SizedBox(height: 24),
              Text(
                l10n.firstAccountSection,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 8),
              TextFormField(
                key: const ValueKey('customer-account-number-field'),
                controller: _accountNumber,
                // Text, not a number: leading zeros and letters are kept.
                keyboardType: TextInputType.visiblePassword,
                autocorrect: false,
                textDirection: TextDirection.ltr,
                textInputAction: TextInputAction.next,
                decoration:
                    InputDecoration(labelText: l10n.accountNumberLabel),
              ),
              const SizedBox(height: 12),
              ProviderField(controller: _provider),
            ],
            const SizedBox(height: 24),
            FilledButton(
              key: const ValueKey('customer-save'),
              onPressed: _saving ? null : _save,
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
