import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/licensing/license_status.dart';
import '../../core/logging/error_log.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_return.dart';
import '../../l10n/generated/app_localizations.dart';
import '../debts/debt_providers.dart';
import '../license/license_gate.dart';
import '../security/pin_dialogs.dart';
import 'return_items_screen.dart' show invoiceMoney;
import 'returns_providers.dart';

/// The quick reasons of a void. "Other" is typed.
enum VoidReason { wrongItems, wrongPrice, customerCancelled, duplicate, other }

String voidReasonLabel(AppLocalizations l10n, VoidReason reason) =>
    switch (reason) {
      VoidReason.wrongItems => l10n.voidReasonWrongItems,
      VoidReason.wrongPrice => l10n.voidReasonWrongPrice,
      VoidReason.customerCancelled => l10n.voidReasonCustomerCancelled,
      VoidReason.duplicate => l10n.voidReasonDuplicate,
      VoidReason.other => l10n.voidReasonOther,
    };

/// Why an invoice is voided and what becomes of its card codes — what
/// [VoidReasonDialog] pops.
class VoidChoice {
  const VoidChoice({required this.reason, this.codes = CodeDisposal.voidCode});

  final String reason;
  final CodeDisposal codes;
}

/// STEP 1 OF A VOID: the reason — required, one tap for the usual ones,
/// typed for "Other" — and, for an invoice that sold card codes, what
/// becomes of them: voided (the default — they were printed or handed
/// over) or returned to stock (only if the customer never received them).
///
/// Owns its controller for its whole life and returns the choice through
/// [Navigator.pop]; nothing when cancelled.
class VoidReasonDialog extends StatefulWidget {
  const VoidReasonDialog({
    super.key,
    required this.invoiceNo,
    this.soldCodes = 0,
  });

  /// Already formatted for the app language.
  final String invoiceNo;

  /// Card codes still sold on the invoice; 0 = the question is not asked.
  final int soldCodes;

  @override
  State<VoidReasonDialog> createState() => _VoidReasonDialogState();
}

class _VoidReasonDialogState extends State<VoidReasonDialog> {
  final _other = TextEditingController();
  final _otherFocus = FocusNode();
  VoidReason? _reason;
  CodeDisposal _codes = CodeDisposal.voidCode;
  String? _error;

  @override
  void dispose() {
    _other.dispose();
    _otherFocus.dispose();
    super.dispose();
  }

  void _pick(VoidReason reason) {
    setState(() {
      _reason = reason;
      _error = null;
    });
    if (reason == VoidReason.other) {
      // The field only exists once "Other" is chosen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otherFocus.requestFocus();
      });
    } else {
      _otherFocus.unfocus();
    }
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final reason = _reason;
    final text = reason == null
        ? ''
        : reason == VoidReason.other
            ? _other.text.trim()
            : voidReasonLabel(l10n, reason);
    if (text.isEmpty) {
      setState(() => _error = l10n.reasonRequired);
      return;
    }
    Navigator.of(context).pop(VoidChoice(reason: text, codes: _codes));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return AlertDialog(
      key: const ValueKey('void-reason-dialog'),
      // Scrolls: with the keyboard up on a small phone at a large font the
      // choices, the field and the buttons do not all fit.
      scrollable: true,
      title: Text(l10n.voidInvoiceTitle(widget.invoiceNo)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.voidReasonQuestion),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final reason in VoidReason.values)
                ChoiceChip(
                  key: ValueKey('void-reason-${reason.name}'),
                  label: Text(voidReasonLabel(l10n, reason)),
                  selected: _reason == reason,
                  onSelected: (_) => _pick(reason),
                ),
            ],
          ),
          if (_reason == VoidReason.other) ...[
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('void-reason-text'),
              controller: _other,
              focusNode: _otherFocus,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: l10n.reasonLabel,
                counterText: '',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _error!,
                key: const ValueKey('void-reason-error'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          if (widget.soldCodes > 0) ...[
            const SizedBox(height: 16),
            Text(
              l10n.voidCodesQuestion(widget.soldCodes),
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  key: const ValueKey('void-codes-void'),
                  label: Text(l10n.voidCodesVoid),
                  selected: _codes == CodeDisposal.voidCode,
                  onSelected: (_) =>
                      setState(() => _codes = CodeDisposal.voidCode),
                ),
                ChoiceChip(
                  key: const ValueKey('void-codes-stock'),
                  label: Text(l10n.voidCodesToStock),
                  selected: _codes == CodeDisposal.returnToStock,
                  onSelected: (_) =>
                      setState(() => _codes = CodeDisposal.returnToStock),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _codes == CodeDisposal.voidCode
                  ? l10n.voidCodesVoidHint
                  : l10n.voidCodesToStockHint,
              key: const ValueKey('void-codes-hint'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('void-reason-continue'),
          onPressed: _submit,
          child: Text(l10n.continueAction),
        ),
      ],
    );
  }
}

/// THE LAST STEP OF A VOID: what will happen, said before it does — the
/// invoice stays (marked, its number kept), the debt is reversed, the credit
/// that was used is given back, what was paid goes back by hand, the card
/// codes, the renewal dates. Pops `true` to go ahead.
class VoidConfirmDialog extends ConsumerWidget {
  const VoidConfirmDialog({
    super.key,
    required this.plan,
    required this.choice,
  });

  final VoidPlan plan;
  final VoidChoice choice;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final invoice = plan.invoice;
    final money = invoiceMoney(ref, invoice.currencyCode);
    final baseMoney = ref.watch(baseMoneyProvider);
    final renewal = plan.renewal;
    // A card or line number keeps its typed order inside an Arabic sentence.
    final account = renewal == null
        ? ''
        : isolateForRtl(l10n.localeName, renewal.accountNumber);
    final creditUsed = invoice.creditUsedMinor ?? 0;
    final dates = DateFormat.yMd(locale);
    String number(int value) => formatMinor(value, decimals: 0, locale: locale);

    final effects = <(IconData, String)>[
      (Icons.receipt_long_outlined, l10n.voidEffectKept),
      if (plan.debtBaseMinor > 0)
        (
          Icons.menu_book_outlined,
          l10n.voidEffectDebt(
            baseMoney(plan.debtBaseMinor),
            invoice.customerName ?? '',
          ),
        ),
      if (creditUsed > 0)
        (Icons.savings_outlined, l10n.voidEffectCredit(money(creditUsed))),
      if (plan.paidMinor > 0)
        (Icons.payments_outlined, l10n.voidEffectCash(money(plan.paidMinor))),
      if (plan.soldCodes > 0)
        (
          Icons.confirmation_number_outlined,
          choice.codes == CodeDisposal.voidCode
              ? l10n.voidEffectCodesVoid(plan.soldCodes)
              : l10n.voidEffectCodesStock(plan.soldCodes),
        ),
      if (renewal != null)
        (
          Icons.event_repeat,
          !renewal.applies
              ? l10n.voidEffectRenewalKept(account)
              : renewal.nextDueAt == null
                  ? l10n.voidEffectRenewalNone(account)
                  : l10n.voidEffectRenewal(
                      account,
                      dates.format(renewal.nextDueAt!.toLocal()),
                    ),
        ),
    ];

    return AlertDialog(
      key: const ValueKey('void-confirm-dialog'),
      scrollable: true,
      title: Text(l10n.voidInvoiceTitle(number(invoice.invoiceNo))),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.voidConfirmIntro),
          const SizedBox(height: 8),
          for (final (index, (icon, text)) in effects.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 20, color: theme.colorScheme.outline),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text, key: ValueKey('void-effect-$index')),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            l10n.auditDetailReason(choice.reason),
            key: const ValueKey('void-confirm-reason'),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('void-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.voidInvoice),
        ),
      ],
    );
  }
}

/// What the user is told when an invoice cannot be voided.
String voidBlockerText(AppLocalizations l10n, VoidPlan plan) =>
    switch (plan.blocker) {
      VoidBlocker.alreadyVoided => l10n.voidAlready,
      VoidBlocker.hasReturns => l10n.voidHasReturns,
      VoidBlocker.tooOld => l10n.voidTooOld(plan.maxAgeDays),
      null => '',
    };

/// VOIDS [invoice], step by step: the reason (and what becomes of its card
/// codes) → the PIN, when one is set → the confirmation that says what will
/// happen → the void itself, one transaction. Returns whether it was done.
///
/// Blocked like a sale without a license; refused — with the reason said —
/// for an invoice that is already void, has returns, or is older than the
/// age limit.
Future<bool> voidInvoiceFlow(BuildContext context, Invoice invoice) async {
  // A void is blocked exactly where a sale is.
  if (!licenseAllows(context, LicensedAction.sell)) return false;
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Taken before the first await: a void the user confirmed is carried out
  // and shown everywhere even if the screen is closed meanwhile.
  final container = ProviderScope.containerOf(context, listen: false);
  final repository = container.read(invoiceCorrectionRepositoryProvider);
  final locale = container.read(appLocaleProvider).languageCode;
  void say(String message) {
    if (!messenger.mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  try {
    final plan = await repository.voidPlan(invoice.id!);
    if (!plan.canVoid) {
      refreshAfterCorrection(container);
      say(voidBlockerText(l10n, plan));
      return false;
    }
    if (!context.mounted) return false;
    final choice = await showDialog<VoidChoice>(
      context: context,
      builder: (_) => VoidReasonDialog(
        invoiceNo: formatMinor(invoice.invoiceNo, decimals: 0, locale: locale),
        soldCodes: plan.soldCodes,
      ),
    );
    if (choice == null || !context.mounted) return false;
    if (!await requirePinIfSet(context, reason: l10n.pinReasonVoid)) {
      return false;
    }
    if (!context.mounted) return false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => VoidConfirmDialog(plan: plan, choice: choice),
    );
    if (confirmed != true) return false;
    await repository.voidInvoice(
      invoice.id!,
      reason: choice.reason,
      codes: choice.codes,
    );
    refreshAfterCorrection(container);
    say(l10n.invoiceVoidedSnack);
    return true;
  } on LicenseRequiredException {
    if (context.mounted) showLicenseNeeded(context, LicensedAction.sell);
  } on InvoiceVoidedException {
    // Voided from another screen meanwhile: the screens reload and show it.
    refreshAfterCorrection(container);
    say(l10n.voidAlready);
  } on InvoiceHasReturnsException {
    refreshAfterCorrection(container);
    say(l10n.voidHasReturns);
  } on InvoiceTooOldException catch (e) {
    say(l10n.voidTooOld(e.maxAgeDays));
  } on InvoiceNotFoundException {
    refreshAfterCorrection(container);
    say(l10n.invoiceNotFound);
  } on Object catch (error, stack) {
    reportError(error, stack, context: 'void invoice');
    say(l10n.saveFailedGeneric);
  }
  return false;
}
