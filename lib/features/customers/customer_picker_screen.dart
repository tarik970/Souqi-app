import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import 'customer_form_screen.dart';
import 'quick_search.dart';

/// How "New customer" pre-fills the form from the typed text.
enum NewCustomerPrefill { name, phone, accountNumber }

/// The "New customer" rows offered for [typed], in order.
///
/// Digits can be a phone or a card number and nothing in the digits says
/// which, so both are offered and the seller picks — a guess would file a
/// card number as a phone half of the time. Anything else is a name; text
/// with a digit and no space in it ("AB-1200") may also be a card number.
List<NewCustomerPrefill> newCustomerOptions(String typed) {
  final text = typed.trim();
  if (text.isEmpty) return const [NewCustomerPrefill.name];
  if (looksLikePhone(text)) {
    return const [
      NewCustomerPrefill.phone,
      if (accountsEnabled) NewCustomerPrefill.accountNumber,
    ];
  }
  final codeLike = accountsEnabled &&
      !text.contains(RegExp(r'\s')) &&
      normalizeDigits(text).contains(RegExp('[0-9]'));
  return [
    NewCustomerPrefill.name,
    if (codeLike) NewCustomerPrefill.accountNumber,
  ];
}

/// The sale screen's customer picker: the same quick search as the home
/// screen. Tapping a row attaches that customer — and that account, when
/// the row is an account — to the sale; "New customer" opens the form with
/// what was typed already filled in.
///
/// Pops with the chosen [SaleCustomer], or with nothing when closed.
class CustomerPickerScreen extends ConsumerStatefulWidget {
  const CustomerPickerScreen({super.key});

  @override
  ConsumerState<CustomerPickerScreen> createState() =>
      _CustomerPickerScreenState();
}

class _CustomerPickerScreenState extends ConsumerState<CustomerPickerScreen> {
  // Owned by this page for its whole life.
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _typed => _query.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _newCustomer(NewCustomerPrefill prefill) async {
    final navigator = Navigator.of(context);
    final typed = _typed;
    final created = await navigator.push(
      MaterialPageRoute<SaleCustomer>(
        builder: (_) => CustomerFormScreen(
          initialName: prefill == NewCustomerPrefill.name ? typed : '',
          initialPhone: prefill == NewCustomerPrefill.phone ? typed : '',
          initialAccountNumber:
              prefill == NewCustomerPrefill.accountNumber ? typed : '',
        ),
      ),
    );
    if (created == null || !navigator.mounted) return;
    navigator.pop(created);
  }

  Widget _newCustomerTile(NewCustomerPrefill prefill) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final typed = _typed;
    final label = typed.isEmpty
        ? l10n.newCustomer
        : switch (prefill) {
            NewCustomerPrefill.name => l10n.newCustomerNamed(typed),
            NewCustomerPrefill.phone =>
              l10n.newCustomerWithPhone(ltrIsolate(typed)),
            NewCustomerPrefill.accountNumber =>
              l10n.newCustomerWithAccount(ltrIsolate(typed)),
          };
    return ListTile(
      key: ValueKey('new-customer-${prefill.name}'),
      leading: Icon(Icons.person_add_alt, color: theme.colorScheme.primary),
      title: Text(
        label,
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      onTap: () => _newCustomer(prefill),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final newRows = [
      for (final option in newCustomerOptions(_typed)) _newCustomerTile(option),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(l10n.customerPickerTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: QuickSearchField(
              controller: _search,
              autofocus: true,
              onChanged: (text) => setState(() => _query = text),
            ),
          ),
          Expanded(
            child: _typed.isEmpty
                ? ListView(
                    children: [
                      ...newRows,
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.quickSearchPrompt,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    ],
                  )
                : QuickSearchResults(
                    query: _typed,
                    leading: newRows,
                    onTap: (hit) => Navigator.of(context).pop(hit.forSale),
                  ),
          ),
        ],
      ),
    );
  }
}
