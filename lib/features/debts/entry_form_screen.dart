import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../security/pin_dialogs.dart';
import 'debt_providers.dart';
import 'debt_widgets.dart';

/// What a [LedgerEntryFormScreen] adds to the account.
enum LedgerEntryKind {
  /// A debt with no invoice behind it: a cash loan, an old item.
  manualDebt,

  /// What the customer owed — or was owed — before the app.
  openingBalance,

  /// A manual correction of the balance. Asks for the PIN and a reason, and
  /// is written to the audit log.
  adjustment,
}

/// Adds one entry to a customer's account by hand: a manual debt, an
/// opening balance or an adjustment. (A payment has its own form, with a
/// receipt; many opening balances at once have the bulk screen.)
///
/// Nothing here edits an existing entry — the ledger is append-only. A
/// mistake is corrected by reversing the entry from the Account tab.
class LedgerEntryFormScreen extends ConsumerStatefulWidget {
  const LedgerEntryFormScreen({
    super.key,
    required this.customerId,
    required this.kind,
  });

  final int customerId;
  final LedgerEntryKind kind;

  @override
  ConsumerState<LedgerEntryFormScreen> createState() =>
      _LedgerEntryFormScreenState();
}

class _LedgerEntryFormScreenState
    extends ConsumerState<LedgerEntryFormScreen> {
  // Owned by this page for its whole life.
  final _amount = TextEditingController();
  final _note = TextEditingController();

  /// True = the entry makes the customer owe more.
  bool _increases = true;

  /// Null = today.
  DateTime? _date;

  /// Null = the customer's default number of days from the date.
  DateTime? _dueDate;
  String? _amountError;
  String? _noteError;
  bool _saving = false;

  LedgerEntryKind get _kind => widget.kind;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  String _title(AppLocalizations l10n) => switch (_kind) {
        LedgerEntryKind.manualDebt => l10n.addDebt,
        LedgerEntryKind.openingBalance => l10n.openingBalance,
        LedgerEntryKind.adjustment => l10n.adjustment,
      };

  /// The moment the entry is dated: the picked day (at this time of day, so
  /// entries of one day keep the order they were typed in), or now.
  DateTime _entryMoment() {
    final now = DateTime.now();
    final day = _date;
    if (day == null) return now;
    return DateTime(
      day.year,
      day.month,
      day.day,
      now.hour,
      now.minute,
      now.second,
      now.millisecond,
    );
  }

  Future<void> _save(int decimals) async {
    if (_saving) return;
    final l10n = AppLocalizations.of(context);
    final amount = AmountField.parseAmount(_amount.text, decimals: decimals);
    final note = _note.text.trim();
    final needsReason = _kind == LedgerEntryKind.adjustment;
    setState(() {
      _amountError = amount == null ? l10n.amountInvalid : null;
      _noteError = needsReason && note.isEmpty ? l10n.reasonRequired : null;
    });
    if (amount == null || (needsReason && note.isEmpty)) return;

    // Taken before the first await: a confirmed entry is written and shown
    // everywhere even if this page is closed meanwhile.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final debts = container.read(debtRepositoryProvider);
    if (needsReason) {
      if (!await requirePin(context, reason: l10n.pinReasonAdjustment)) return;
      if (!mounted) return;
    }
    setState(() => _saving = true);
    final at = _entryMoment();
    switch (_kind) {
      case LedgerEntryKind.manualDebt:
        await debts.addManualDebt(
          customerId: widget.customerId,
          amountBaseMinor: amount,
          dueAt: _dueDate,
          note: note,
          at: at,
        );
      case LedgerEntryKind.openingBalance:
        await debts.addOpeningBalance(
          customerId: widget.customerId,
          amountBaseMinor: amount,
          customerOwes: _increases,
          note: note,
          at: at,
        );
      case LedgerEntryKind.adjustment:
        await debts.addAdjustment(
          customerId: widget.customerId,
          amountBaseMinor: amount,
          increasesDebt: _increases,
          reason: note,
        );
    }
    refreshDebtData(container);
    if (messenger.mounted) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.entrySaved)));
    }
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(baseMoneyProvider);
    final customer = ref.watch(customerProvider(widget.customerId)).value;
    final summary = ref.watch(accountSummaryProvider(widget.customerId)).value;
    final base = ref.watch(baseCurrencyProvider).value;
    final decimals = base?.decimalPlaces ?? 0;
    final today = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(_title(l10n))),
      body: DebtLockGate(
        child: ListView(
        key: const ValueKey('entry-form'),
        padding: const EdgeInsets.all(16),
        children: [
          if (customer != null)
            Text(customer.name, style: theme.textTheme.titleLarge),
          if (summary != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: BalanceText(summary.balanceBaseMinor),
            ),
          const SizedBox(height: 16),
          if (_kind != LedgerEntryKind.manualDebt) ...[
            // Which way the entry goes. Chips in a Wrap: two long labels do
            // not fit side by side on a small phone at a large font.
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  key: const ValueKey('entry-increase'),
                  label: Text(_kind == LedgerEntryKind.adjustment
                      ? l10n.adjustmentIncrease
                      : l10n.openingOwesToggle),
                  selected: _increases,
                  onSelected: (_) => setState(() => _increases = true),
                ),
                ChoiceChip(
                  key: const ValueKey('entry-decrease'),
                  label: Text(_kind == LedgerEntryKind.adjustment
                      ? l10n.adjustmentDecrease
                      : l10n.openingCreditToggle),
                  selected: !_increases,
                  onSelected: (_) => setState(() => _increases = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          AmountField(
            key: const ValueKey('entry-amount'),
            controller: _amount,
            label: l10n.amountLabel,
            currencyLabel: money.label,
            errorText: _amountError,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _amountError = null),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('entry-note'),
            controller: _note,
            minLines: 1,
            maxLines: 3,
            onChanged: (_) => setState(() => _noteError = null),
            decoration: InputDecoration(
              labelText: _kind == LedgerEntryKind.adjustment
                  ? l10n.reasonLabel
                  : _kind == LedgerEntryKind.manualDebt
                      ? l10n.manualDebtNoteHint
                      : l10n.noteOptional,
              errorText: _noteError,
              border: const OutlineInputBorder(),
            ),
          ),
          // An adjustment is always dated now: it is a correction made
          // today, not a rewrite of the past.
          if (_kind != LedgerEntryKind.adjustment) ...[
            const SizedBox(height: 12),
            DateRow(
              key: const ValueKey('entry-date'),
              label: l10n.dateLabel,
              value: _date ?? today,
              lastDate: today,
              onChanged: (day) => setState(() => _date = day),
            ),
          ],
          if (_kind == LedgerEntryKind.manualDebt) ...[
            const SizedBox(height: 12),
            DateRow(
              key: const ValueKey('entry-due-date'),
              label: l10n.dueDateLabel,
              value: _dueDate,
              placeholder: l10n.defaultDueDaysLabel,
              onChanged: (day) => setState(() => _dueDate = day),
              onCleared: () => setState(() => _dueDate = null),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('entry-save'),
            onPressed: _saving ? null : () => _save(decimals),
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
