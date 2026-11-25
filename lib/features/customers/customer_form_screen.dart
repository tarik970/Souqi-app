import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import 'account_form_screen.dart';
import 'customers_providers.dart';

/// Add or edit a customer: name (required), phone and notes.
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
  bool _saving = false;

  Customer? get _initial => widget.customer;

  bool get _withAccount => _initial == null && accountsEnabled;

  @override
  void initState() {
    super.initState();
    final c = _initial;
    _name = TextEditingController(text: c?.name ?? widget.initialName);
    _phone = TextEditingController(text: c?.phone ?? widget.initialPhone);
    _notes = TextEditingController(text: c?.notes ?? '');
    _accountNumber = TextEditingController(text: widget.initialAccountNumber);
    _provider = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _notes.dispose();
    _accountNumber.dispose();
    _provider.dispose();
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
      ));
      refreshCustomerData(container);
      if (navigator.mounted) navigator.pop();
      return;
    }

    final hasAccount = normalizeCode(accountNumber).isNotEmpty;
    final (customerId, accountId) = await repository.insertWithAccount(
      Customer(name: name, phone: phone, notes: notes),
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
