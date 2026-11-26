import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/invoice_detail_screen.dart';
import '../debts/account_tab.dart';
import '../debts/debt_providers.dart';
import '../debts/debt_text.dart';
import '../debts/debt_widgets.dart';
import 'account_form_screen.dart';
import 'contact_actions.dart';
import 'customer_form_screen.dart';
import 'customer_widgets.dart';
import 'customers_providers.dart';
import 'renewal.dart';

/// The tabs of a customer's page (only with the debt ledger on; without it
/// the page is the details alone).
enum CustomerTab { details, account }

/// One customer: who they are, how to reach them, their cards / accounts and
/// everything they bought — and, with the debt ledger on, an "Account" tab
/// with their balance and their ledger.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({
    super.key,
    required this.customerId,
    this.initialTab = CustomerTab.details,
  });

  final int customerId;

  /// The tab the page opens on (the debtors list opens the Account tab).
  final CustomerTab initialTab;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  static const int _historyStep = 30;

  int _historyLimit = _historyStep;
  List<CustomerInvoice>? _history;

  int get _id => widget.customerId;

  void _edit(Customer customer) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CustomerFormScreen(customer: customer),
    ));
  }

  void _openAccount([CustomerAccount? account]) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AccountFormScreen(customerId: _id, account: account),
    ));
  }

  Future<void> _setActive(Customer customer, bool active) async {
    final l10n = AppLocalizations.of(context);
    // Taken before the dialog: a confirmed change is carried out even if
    // this page was closed meanwhile.
    final container = ProviderScope.containerOf(context, listen: false);
    final repository = ref.read(customerRepositoryProvider);
    if (!active) {
      // A customer with an open balance is not deactivated without the
      // balance being shown first: hiding someone who owes money (or is
      // owed some) must be a decision, not an accident.
      final balance = featureOn(Feature.debt)
          ? await ref.read(debtRepositoryProvider).balanceOf(customer.id!)
          : 0;
      if (!mounted) return;
      final money = ref.read(baseMoneyProvider);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          key: const ValueKey('deactivate-customer-dialog'),
          scrollable: true,
          title: Text(l10n.deactivateCustomerTitle),
          content: Text(
            balance == 0
                ? l10n.deactivateCustomerMessage(customer.name)
                : l10n.deactivateWithBalanceMessage(
                    customer.name,
                    balanceInWords(l10n, balance, money.call),
                  ),
            key: ValueKey(balance == 0
                ? 'deactivate-plain'
                : 'deactivate-with-balance'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.deactivate),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await repository.setActive(customer.id!, active);
    refreshCustomerData(container);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final customer = ref.watch(customerProvider(_id));
    final data = customer.value;
    final tabs = featureOn(Feature.debt);

    final page = Scaffold(
      appBar: AppBar(
        title: Text(data?.name ?? l10n.navCustomers),
        bottom: tabs
            ? TabBar(
                key: const ValueKey('customer-tabs'),
                tabs: [
                  Tab(
                    key: const ValueKey('customer-tab-details'),
                    text: l10n.customerDetailsTab,
                  ),
                  Tab(
                    key: const ValueKey('customer-tab-account'),
                    text: l10n.accountTab,
                  ),
                ],
              )
            : null,
        actions: [
          if (data != null) ...[
            IconButton(
              key: const ValueKey('customer-edit'),
              tooltip: l10n.edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _edit(data),
            ),
            PopupMenuButton<void>(
              key: const ValueKey('customer-menu'),
              itemBuilder: (context) => [
                PopupMenuItem<void>(
                  // The dialog must not open inside onTap (the menu is still
                  // closing); a post-frame callback is the documented way.
                  onTap: () => WidgetsBinding.instance.addPostFrameCallback(
                    (_) {
                      if (mounted) _setActive(data, !data.isActive);
                    },
                  ),
                  child:
                      Text(data.isActive ? l10n.deactivate : l10n.reactivate),
                ),
              ],
            ),
          ],
        ],
      ),
      body: customer.when(
        // An edit re-reads the customer: keep the page, not a spinner.
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const SizedBox.shrink(),
        error: (e, _) => Center(child: Text('$e')),
        data: (value) => value == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child:
                      Text(l10n.customerNotFound, textAlign: TextAlign.center),
                ),
              )
            : tabs
                ? TabBarView(
                    children: [
                      _body(context, value),
                      // Behind the PIN when the setting asks for it.
                      DebtLockGate(child: AccountTab(customer: value)),
                    ],
                  )
                : _body(context, value),
      ),
    );
    return tabs
        ? DefaultTabController(
            length: CustomerTab.values.length,
            initialIndex: widget.initialTab.index,
            child: page,
          )
        : page;
  }

  Widget _body(BuildContext context, Customer customer) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final accounts = ref.watch(customerAccountsProvider(_id)).value;
    final totals = ref.watch(customerTotalsProvider(_id)).value;
    // "Show more" asks for a longer list, which is a new query: the rows
    // already on screen stay there until it answers.
    final loaded = ref
        .watch(customerHistoryProvider((customerId: _id, limit: _historyLimit)))
        .value;
    if (loaded != null) _history = loaded;
    final history = _history;
    final base = ref.watch(baseCurrencyProvider).value;
    final currencies =
        ref.watch(currenciesProvider).value ?? const <Currency>[];
    final soonDays = ref.watch(dueSoonDaysProvider).value ?? 3;
    final now = ref.watch(clockProvider)();
    final dates = DateFormat.yMd(locale);

    Widget header(String text, {Widget? action}) => Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
              ?action,
            ],
          ),
        );

    String money(int minor, Currency? currency, String code) => formatMinor(
          minor,
          decimals: currency?.decimalPlaces ?? 0,
          locale: locale,
          symbol: currency == null || currency.symbol.isEmpty
              ? code
              : currency.symbol,
        );

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!customer.isActive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(
                    key: const ValueKey('customer-inactive'),
                    label: Text(l10n.inactiveBadge),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              if (customer.hasPhone)
                Text(
                  ltrIsolate(customer.phone!),
                  key: const ValueKey('customer-phone'),
                  style: theme.textTheme.titleMedium,
                ),
              if (customer.notes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child:
                      Text(customer.notes!, style: theme.textTheme.bodyMedium),
                ),
              if (customer.hasPhone)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      FilledButton.tonalIcon(
                        key: const ValueKey('customer-call'),
                        onPressed: () =>
                            callCustomer(context, customer.phone!),
                        icon: const Icon(Icons.call_outlined),
                        label: Text(l10n.callCustomer),
                      ),
                      FilledButton.tonalIcon(
                        key: const ValueKey('customer-whatsapp'),
                        onPressed: () =>
                            openCustomerChat(context, phone: customer.phone!),
                        icon: const Icon(Icons.chat_outlined),
                        label: Text(l10n.whatsAppCustomer),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (totals != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(
              key: const ValueKey('customer-totals'),
              spacing: 24,
              runSpacing: 8,
              children: [
                _Figure(
                  label: l10n.customerInvoiceCount,
                  value: formatMinor(
                    totals.invoiceCount,
                    decimals: 0,
                    locale: locale,
                  ),
                ),
                _Figure(
                  label: l10n.customerTotalSpent,
                  value:
                      money(totals.totalBaseMinor, base, base?.code ?? ''),
                ),
                if (totals.lastPurchaseAt != null)
                  _Figure(
                    label: l10n.customerLastPurchase,
                    value: dates.format(totals.lastPurchaseAt!.toLocal()),
                  ),
              ],
            ),
          ),
        if (featureOn(Feature.accounts)) ...[
          header(
            l10n.accountsTitle,
            action: TextButton.icon(
              key: const ValueKey('customer-add-account'),
              onPressed: _openAccount,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.add),
            ),
          ),
          if (accounts != null && accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                l10n.noAccounts,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          for (final hit in accounts ?? const <CustomerHit>[]) ...[
            CustomerHitTile(
              key: ValueKey('customer-account-${hit.account!.id}'),
              hit: hit,
              now: now,
              soonDays: soonDays,
              locale: locale,
              showCustomer: false,
              onTap: () => _openAccount(hit.account),
              actions: [
                if (hit.account!.isActive && customer.isActive)
                  RenewButton(onPressed: () => startRenewal(context, hit)),
              ],
            ),
            const Divider(height: 1),
          ],
        ],
        header(l10n.historyTitle),
        if (history != null && history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              l10n.noHistory,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
        for (final invoice in history ?? const <CustomerInvoice>[])
          ListTile(
            key: ValueKey('customer-invoice-${invoice.invoiceNo}'),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    invoice.firstItemName == null
                        ? l10n.invoiceNoLabel(formatMinor(
                            invoice.invoiceNo,
                            decimals: 0,
                            locale: locale,
                          ))
                        : [
                            invoice.firstItemName!,
                            if (invoice.itemCount > 1)
                              l10n.historyMoreItems(formatMinor(
                                invoice.itemCount - 1,
                                decimals: 0,
                                locale: locale,
                              )),
                          ].join(' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  money(
                    invoice.totalMinor,
                    currencies
                        .where((c) => c.code == invoice.currencyCode)
                        .firstOrNull,
                    invoice.currencyCode,
                  ),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              [
                DateFormat.yMd(locale)
                    .add_jm()
                    .format(invoice.createdAt.toLocal()),
                l10n.invoiceNoLabel(formatMinor(
                  invoice.invoiceNo,
                  decimals: 0,
                  locale: locale,
                )),
                if (featureOn(Feature.accounts) && invoice.accountNumber != null)
                  ltrIsolate(invoice.accountNumber!),
              ].join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => InvoiceDetailScreen(invoiceId: invoice.id),
            )),
          ),
        if (history != null && history.length >= _historyLimit)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: OutlinedButton(
              key: const ValueKey('customer-history-more'),
              onPressed: () =>
                  setState(() => _historyLimit += _historyStep),
              child: Text(l10n.showMore),
            ),
          ),
      ],
    );
  }
}

/// A small labelled number ("Invoices 12").
class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
        Text(
          value,
          style:
              theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
