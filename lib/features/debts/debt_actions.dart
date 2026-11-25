import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/invoice_detail_screen.dart';
import '../customers/contact_actions.dart';
import '../invoice/invoice_providers.dart';
import '../security/pin_dialogs.dart';
import 'debt_providers.dart';
import 'debt_text.dart';
import 'debt_widgets.dart';
import 'receipt_screen.dart';

/// Opens the customer's WhatsApp chat with the debt reminder typed in — the
/// shop's own text or the default in the invoice language, filled in for
/// this customer. Nothing is sent by the app: the seller reads the message,
/// edits it if needed and presses send in WhatsApp.
Future<void> sendDebtReminder(BuildContext context, int customerId) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final customer =
      await container.read(customerRepositoryProvider).getById(customerId);
  final phone = customer?.phone;
  if (customer == null || phone == null || phone.trim().isEmpty) {
    if (messenger.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.debtReminderNoPhone)));
    }
    return;
  }
  final summary = await container
      .read(debtRepositoryProvider)
      .accountSummary(customerId, now: DateTime.now());
  final settings = await container.read(invoiceSettingsProvider.future);
  final template = await container.read(debtReminderTemplateProvider.future);
  final base = await container.read(baseCurrencyProvider.future);
  if (!context.mounted) return;
  await openCustomerChat(
    context,
    phone: phone,
    text: buildDebtReminderText(
      template: template,
      name: customer.name,
      // The message is read by the customer: the invoice language, like the
      // invoice itself.
      balance: formatMinor(
        summary.balanceBaseMinor.abs(),
        decimals: base.decimalPlaces,
        locale: settings.language,
        symbol: base.symbol.isEmpty ? base.code : base.symbol,
      ),
      language: settings.language,
      shopName: settings.shopName,
      lastPaymentAt: summary.lastPaymentAt,
    ),
  );
}

/// Asks why an entry is being reversed. Owns its controller for its whole
/// life and returns the reason through [Navigator.pop]; nothing when
/// cancelled.
class ReverseEntryDialog extends StatefulWidget {
  const ReverseEntryDialog({super.key, required this.description});

  /// What is being reversed ("Receipt 37 · 5,000 SYP").
  final String description;

  @override
  State<ReverseEntryDialog> createState() => _ReverseEntryDialogState();
}

class _ReverseEntryDialogState extends State<ReverseEntryDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).reasonRequired);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('reverse-entry-dialog'),
      // Scrolls: with the keyboard up on a small phone there is room for
      // the field or for the buttons, not both.
      scrollable: true,
      title: Text(l10n.reverseTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.description,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Text(l10n.reverseMessage),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('reverse-reason'),
            controller: _reason,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: InputDecoration(
              labelText: l10n.reasonLabel,
              errorText: _error,
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
          key: const ValueKey('reverse-confirm'),
          onPressed: _submit,
          child: Text(l10n.reverseEntry),
        ),
      ],
    );
  }
}

/// Reverses [entry]: the reason, then the PIN, then the REVERSAL entry and
/// its line in the audit log (one transaction). Returns whether it was done.
Future<bool> reverseEntryFlow(BuildContext context, DebtEntry entry) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Taken before the first await: a reversal the user confirmed is written
  // and shown everywhere even if the screen is closed meanwhile.
  final container = ProviderScope.containerOf(context, listen: false);
  final locale = container.read(appLocaleProvider).languageCode;
  final money = container.read(baseMoneyProvider);
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => ClosesWithDebtSession(
      child: ReverseEntryDialog(
      description: '${describeEntry(l10n, entry, locale: locale)} · '
          '${money(entry.amountBaseMinor)}',
      ),
    ),
  );
  if (reason == null || !context.mounted) return false;
  if (!await requirePin(context, reason: l10n.pinReasonReverse)) return false;
  try {
    await container.read(debtRepositoryProvider).reverse(entry.id, reason: reason);
  } on NotReversibleException {
    // Reversed from another screen meanwhile: the list reloads and shows it.
    refreshDebtData(container);
    return false;
  }
  refreshDebtData(container);
  if (messenger.mounted) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.entryReversedSnack)));
  }
  return true;
}

/// One ledger entry in full, with what can be done with it: open its
/// invoice (or read that the invoice is gone and the debt is not), open its
/// receipt, follow the link between an entry and its reversal — and
/// reverse it.
Future<void> showEntrySheet(BuildContext context, LedgerLine line) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ClosesWithDebtSession(child: _EntrySheet(line: line)),
  );
}

class _EntrySheet extends ConsumerWidget {
  const _EntrySheet({required this.line});

  final LedgerLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final money = ref.watch(baseMoneyProvider);
    final currencies = ref.watch(currenciesProvider).value ?? const [];
    final entry = line.entry;
    final method = entry.paymentMethod;
    final origCode = entry.origCurrencyCode;
    final origAmount = entry.origAmountMinor;
    final note = entry.note?.trim() ?? '';
    final invoiceNo = entry.invoiceNo;
    final navigator = Navigator.of(context);

    Widget fact(String label, String value, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label: ',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              Expanded(child: Text(value, key: key)),
            ],
          ),
        );

    String origText() {
      final currency =
          currencies.where((c) => c.code == origCode).firstOrNull;
      return formatMinor(
        origAmount!,
        decimals: currency?.decimalPlaces ?? 0,
        locale: locale,
        symbol: currency == null || currency.symbol.isEmpty
            ? origCode!
            : currency.symbol,
      );
    }

    return SingleChildScrollView(
      key: const ValueKey('entry-sheet'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            describeEntry(l10n, entry, locale: locale),
            style: theme.textTheme.titleLarge?.copyWith(
              decoration:
                  entry.isReversed ? TextDecoration.lineThrough : null,
            ),
          ),
          if (entry.isReversed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: DebtBadge(l10n.entryReversed),
              ),
            ),
          const SizedBox(height: 8),
          fact(
            entry.isDebit ? l10n.ledgerDebit : l10n.ledgerCredit,
            money(entry.amountBaseMinor),
          ),
          fact(
            l10n.dateLabel,
            DateFormat.yMd(locale).add_jm().format(entry.createdAt.toLocal()),
          ),
          if (origCode != null && origAmount != null)
            fact(
              l10n.receiptPaidAs,
              entry.origRate == null
                  ? origText()
                  : '${origText()}  ·  1 $origCode = '
                      '${formatRateValue(entry.origRate!, locale: locale)} '
                      '${money.label}',
            ),
          if (method != null)
            fact(l10n.paymentMethodLabel, paymentMethodLabel(l10n, method)),
          if (entry.dueAt != null && entry.isEffective)
            fact(l10n.dueDateLabel, formatDay(entry.dueAt!, locale)),
          if (note.isNotEmpty)
            fact(
              entry.isReversal || entry.type == DebtEntryType.adjustment
                  ? l10n.reasonLabel
                  : l10n.receiptNoteLabel,
              note,
            ),
          fact(
            l10n.balanceLabel,
            balanceInWords(l10n, line.balanceAfterBaseMinor, money.call),
          ),
          if (entry.type == DebtEntryType.debt &&
              entry.invoiceId == null &&
              invoiceNo != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.invoiceDeletedNote(localizeDigits('$invoiceNo', locale)),
                key: const ValueKey('entry-invoice-deleted'),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          const SizedBox(height: 12),
          if (entry.invoiceId != null)
            OutlinedButton.icon(
              key: const ValueKey('entry-open-invoice'),
              onPressed: () {
                navigator.pop();
                navigator.push(MaterialPageRoute<void>(
                  builder: (_) =>
                      InvoiceDetailScreen(invoiceId: entry.invoiceId!),
                ));
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: Text(l10n.openInvoice),
            ),
          if (entry.type == DebtEntryType.payment)
            OutlinedButton.icon(
              key: const ValueKey('entry-open-receipt'),
              onPressed: () {
                navigator.pop();
                navigator.push(MaterialPageRoute<void>(
                  // Opened again from the ledger: every output is a copy.
                  builder: (_) => ReceiptScreen(entryId: entry.id, copy: true),
                ));
              },
              icon: const Icon(Icons.receipt_outlined),
              label: Text(l10n.viewReceipt),
            ),
          // The link between a cancelled entry and its reversal, both ways.
          if (entry.reversedById != null || entry.reversesId != null)
            OutlinedButton.icon(
              key: const ValueKey('entry-linked'),
              onPressed: () async {
                final page = navigator.context;
                final other = await ref
                    .read(debtRepositoryProvider)
                    .lineById(entry.reversedById ?? entry.reversesId!);
                navigator.pop();
                if (other != null && page.mounted) {
                  await showEntrySheet(page, other);
                }
              },
              icon: const Icon(Icons.link),
              label: Text(
                entry.isReversal
                    ? describeReversedOriginal(l10n, entry, locale: locale)
                    : l10n.entryReversalOf(
                        describeEntry(l10n, entry, locale: locale),
                      ),
                textAlign: TextAlign.center,
              ),
            ),
          if (entry.canBeReversed)
            TextButton.icon(
              key: const ValueKey('entry-reverse'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () async {
                // The sheet closes first; the dialogs open over the page.
                final page = navigator.context;
                navigator.pop();
                if (page.mounted) await reverseEntryFlow(page, entry);
              },
              icon: const Icon(Icons.undo),
              label: Text(l10n.reverseEntry),
            ),
        ],
      ),
    );
  }
}
