import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../domain/models/customer.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import 'debt_providers.dart';
import 'debt_widgets.dart';

/// Existing customers matching what is being typed into the name field —
/// by name or phone, never by account number: this screen is about people.
final _openingSuggestionsProvider = FutureProvider.autoDispose
    .family<List<Customer>, String>((ref, query) async {
  if (query.trim().length < 2) return const [];
  final countryCode = await ref.watch(defaultCountryCodeProvider.future);
  final hits = await ref.watch(customerRepositoryProvider).quickSearch(
        query,
        limit: 4,
        includeAccounts: false,
        countryCode: countryCode,
      );
  return [for (final hit in hits) hit.customer];
});

/// Opening balances in bulk, for a shop moving from a paper notebook: name
/// (or an existing customer picked from the suggestions), phone (optional),
/// amount, optional date — Add, and the form is empty again with the cursor
/// back in the name field for the next line of the notebook.
///
/// Every row is saved the moment it is added (customer and balance in one
/// transaction), so nothing is lost if the phone rings half way down the
/// page. A name that already exists is the same customer, not a second
/// one — the duplicate guard — unless a different phone says otherwise.
class OpeningBalancesScreen extends ConsumerStatefulWidget {
  const OpeningBalancesScreen({super.key});

  @override
  ConsumerState<OpeningBalancesScreen> createState() =>
      _OpeningBalancesScreenState();
}

class _OpeningBalancesScreenState extends ConsumerState<OpeningBalancesScreen> {
  // Owned by this page for its whole life.
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _nameFocus = FocusNode();
  final _amountFocus = FocusNode();

  /// An existing customer picked from the suggestions.
  Customer? _picked;
  bool _owes = true;

  /// Null = today. Kept between rows: a notebook is usually typed in with
  /// one "as of" date.
  DateTime? _date;
  String? _nameError;
  String? _amountError;
  bool _saving = false;

  /// What was added in this visit, newest first.
  final List<OpeningBalanceResult> _added = [];

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _amount.dispose();
    _nameFocus.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _pick(Customer customer) {
    setState(() {
      _picked = customer;
      _nameError = null;
    });
    _amountFocus.requestFocus();
  }

  Future<void> _add(int decimals) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final picked = _picked;
    final name = _name.text.trim();
    final amount = AmountField.parseAmount(_amount.text, decimals: decimals);
    setState(() {
      _nameError =
          picked == null && name.isEmpty ? l10n.openingNameRequired : null;
      _amountError = amount == null ? l10n.amountInvalid : null;
    });
    if ((picked == null && name.isEmpty) || amount == null) return;

    // Taken before the first await: a confirmed row is saved and shown
    // everywhere even if this page is closed meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    final now = DateTime.now();
    final day = _date;
    setState(() => _saving = true);
    final result =
        await container.read(debtRepositoryProvider).addOpeningBalanceFor(
              OpeningBalanceDraft(
                customerId: picked?.id,
                name: picked?.name ?? name,
                phone: picked == null ? _phone.text : null,
                amountBaseMinor: amount,
                customerOwes: _owes,
                // The picked day at this time of day, so rows of one day
                // keep the order they were typed in.
                date: day == null
                    ? null
                    : DateTime(day.year, day.month, day.day, now.hour,
                        now.minute, now.second, now.millisecond),
              ),
            );
    refreshDebtData(container);
    if (result.createdCustomer) refreshCustomerData(container);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _added.insert(0, result);
      _picked = null;
      _name.clear();
      _phone.clear();
      _amount.clear();
    });
    _nameFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(baseMoneyProvider);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final decimals = ref.watch(baseCurrencyProvider).value?.decimalPlaces ?? 0;
    final picked = _picked;
    final suggestions = picked != null
        ? const <Customer>[]
        : ref.watch(_openingSuggestionsProvider(_name.text)).value ??
            const <Customer>[];
    final pickedSummary = picked == null
        ? null
        : ref.watch(accountSummaryProvider(picked.id!)).value;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.openingBalancesTitle)),
      body: DebtLockGate(
        child: ListView(
        key: const ValueKey('opening-balances'),
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.openingBalancesIntro,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          const SizedBox(height: 12),
          if (picked != null)
            // An existing customer was picked: say who, and what they
            // already owe, where the name field was.
            InputChip(
              key: const ValueKey('opening-picked'),
              avatar: const Icon(Icons.person, size: 18),
              label: Text(
                pickedSummary == null
                    ? l10n.openingPickedCustomer(picked.name)
                    : '${l10n.openingPickedCustomer(picked.name)} · '
                        '${l10n.openingExistingBalance(money(pickedSummary.balanceBaseMinor))}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onDeleted: () => setState(() => _picked = null),
            )
          else ...[
            TextField(
              key: const ValueKey('opening-name'),
              controller: _name,
              focusNode: _nameFocus,
              autofocus: true,
              textInputAction: TextInputAction.next,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() => _nameError = null),
              decoration: InputDecoration(
                labelText: l10n.customerName,
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
            ),
            for (final customer in suggestions)
              ListTile(
                key: ValueKey('opening-suggestion-${customer.id}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(
                  customer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: customer.hasPhone
                    ? Text(ltrIsolate(customer.phone!))
                    : null,
                // No trailing text: a ListTile gives up ("trailing widget
                // consumes the entire tile width") on a small phone at a
                // large font — and every suggestion is an existing customer
                // anyway.
                onTap: () => _pick(customer),
              ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('opening-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.customerPhone,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 12),
          AmountField(
            key: const ValueKey('opening-amount'),
            controller: _amount,
            focusNode: _amountFocus,
            label: l10n.amountLabel,
            currencyLabel: money.label,
            errorText: _amountError,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() => _amountError = null),
            onSubmitted: (_) => _add(decimals),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: const ValueKey('opening-owes'),
                label: Text(l10n.openingOwesToggle),
                selected: _owes,
                onSelected: (_) => setState(() => _owes = true),
              ),
              ChoiceChip(
                key: const ValueKey('opening-credit'),
                label: Text(l10n.openingCreditToggle),
                selected: !_owes,
                onSelected: (_) => setState(() => _owes = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DateRow(
            key: const ValueKey('opening-date'),
            label: l10n.openingDateLabel,
            value: _date,
            placeholder: formatDay(today, locale),
            lastDate: today,
            onChanged: (day) => setState(() => _date = day),
            onCleared: () => setState(() => _date = null),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('opening-add'),
            onPressed: _saving ? null : () => _add(decimals),
            icon: const Icon(Icons.add),
            label: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(l10n.add),
            ),
          ),
          if (_added.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              l10n.openingSessionTotal(localizeCount(_added.length, locale)),
              key: const ValueKey('opening-session-count'),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            for (final row in _added)
              // A plain row, not a ListTile: a balance in the hundreds of
              // millions as a ListTile's trailing widget leaves no room for
              // the name, and the tile asserts.
              Padding(
                key: ValueKey('opening-row-${row.entry.id}'),
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.customerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            row.createdCustomer
                                ? l10n.openingAddedNew
                                : l10n.openingAddedExisting,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: BalanceText(
                          row.entry.signedBaseMinor,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
        ),
      ),
    );
  }
}

/// A count in the digits of [locale].
String localizeCount(int count, String locale) =>
    localizeDigits('$count', locale);
