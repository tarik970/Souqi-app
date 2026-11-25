import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import 'debt_providers.dart';
import 'debt_text.dart';

/// A money field: digits only (any digit shapes), left-to-right, with the
/// currency after it. The text is parsed with [parseAmount]; this widget
/// owns nothing — the controller belongs to the form around it.
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.label,
    required this.currencyLabel,
    this.errorText,
    this.helperText,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String currencyLabel;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool enabled;

  /// The typed amount in minor units, or null when it is not an amount
  /// greater than zero.
  static int? parseAmount(String text, {required int decimals}) {
    final minor = parseAmountMinor(text, decimals: decimals);
    return minor == null || minor <= 0 ? null : minor;
  }

  @override
  Widget build(BuildContext context) {
    // Gaining focus selects the whole amount: an amount a field opens on is
    // restated, not continued, so the first keystroke replaces it.
    return SelectAllOnFocus(controller: controller, child: _field());
  }

  Widget _field() {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        suffixText: currencyLabel,
        errorText: errorText,
        errorMaxLines: 3,
        helperText: helperText,
        helperMaxLines: 3,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// A balance as coloured words: what the customer owes in the error colour,
/// what the shop owes them in the primary colour.
class BalanceText extends ConsumerWidget {
  const BalanceText(this.balanceBaseMinor, {super.key, this.style});

  final int balanceBaseMinor;
  final TextStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(baseMoneyProvider);
    final color = balanceBaseMinor > 0
        ? theme.colorScheme.error
        : balanceBaseMinor < 0
            ? theme.colorScheme.primary
            : theme.colorScheme.outline;
    return Text(
      balanceInWords(l10n, balanceBaseMinor, money.call),
      style: (style ?? theme.textTheme.titleMedium)
          ?.copyWith(color: color, fontWeight: FontWeight.bold),
    );
  }
}

/// A small pill: "Overdue", "Over limit", "Reversed".
class DebtBadge extends StatelessWidget {
  const DebtBadge(this.label, {super.key, this.alert = true});

  final String label;

  /// Error colours (something needs attention) rather than neutral ones.
  final bool alert;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: alert ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: alert ? scheme.onErrorContainer : scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

/// The four aging buckets as a 2 × 2 grid of labelled amounts. A grid, not a
/// row: four amounts in the millions do not fit side by side on a phone.
class AgingGrid extends ConsumerWidget {
  const AgingGrid({super.key, required this.aging});

  final AgingSummary aging;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final money = ref.watch(baseMoneyProvider);
    Widget cell(AgingBucket bucket) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agingBucketLabel(l10n, bucket),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    money(aging[bucket]),
                    key: ValueKey('aging-${bucket.name}'),
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: bucket == AgingBucket.over90 && aging[bucket] > 0
                          ? theme.colorScheme.error
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Column(
      key: const ValueKey('aging-grid'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cell(AgingBucket.current),
            const SizedBox(width: 12),
            cell(AgingBucket.days31to60),
          ],
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cell(AgingBucket.days61to90),
            const SizedBox(width: 12),
            cell(AgingBucket.over90),
          ],
        ),
      ],
    );
  }
}

/// "12/25/2026" in the app language.
String formatDay(DateTime moment, String locale) =>
    DateFormat.yMd(locale).format(moment.toLocal());

/// A row that shows a date and opens the date picker: "Due date  12/25/2026".
/// [onChanged] gets the picked day (local midnight); with [onCleared] a
/// clear button is shown while a date is set.
class DateRow extends ConsumerWidget {
  const DateRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onCleared,
    this.placeholder,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onCleared;

  /// Shown instead of a date while [value] is null.
  final String? placeholder;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final now = DateTime.now();
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value?.toLocal() ?? now,
          firstDate: firstDate ?? DateTime(now.year - 20),
          lastDate: lastDate ?? DateTime(now.year + 10),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: value != null && onCleared != null
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: onCleared,
                )
              : const Icon(Icons.event),
        ),
        child: Text(
          value == null ? (placeholder ?? '') : formatDay(value!, locale),
          style: value == null
              ? theme.textTheme.bodyLarge
                  ?.copyWith(color: theme.colorScheme.outline)
              : theme.textTheme.bodyLarge,
        ),
      ),
    );
  }
}

/// The locked door in front of the debts. With the "PIN to open debts"
/// setting on, [child] is shown only while the debt session is unlocked;
/// otherwise a lock and an "Unlock" button are.
///
/// - Until the PIN has been entered, nothing of [child] is built — and so
///   nothing is read from the ledger.
/// - Every touch on [child] counts as using the session and pushes the
///   automatic lock back.
/// - When the session locks again (idle too long, or the app went to the
///   background), [child] is HIDDEN, not thrown away: a payment form half
///   filled in is still there after the PIN. Leaving the app to read the
///   amount of a transfer must not cost the seller what they had typed.
class DebtLockGate extends ConsumerStatefulWidget {
  const DebtLockGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DebtLockGate> createState() => _DebtLockGateState();
}

class _DebtLockGateState extends ConsumerState<DebtLockGate> {
  /// The session was unlocked at least once while this gate was on screen:
  /// [DebtLockGate.child] exists and is kept.
  bool _built = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final required = ref.watch(debtRequirePinProvider).value;
    final unlocked = ref.watch(debtUnlockedProvider);
    // A screen that just locked must not keep the keyboard up.
    ref.listen(debtUnlockedProvider, (previous, next) {
      if (previous == true && !next) {
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
    // Until the setting is read, nothing is shown.
    if (required == null) {
      return const SizedBox.shrink();
    }
    final open = !required || unlocked;
    if (open) _built = true;

    final lock = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(
              l10n.debtLockedMessage,
              key: const ValueKey('debt-locked'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              key: const ValueKey('debt-unlock'),
              onPressed: () => requireDebtAccess(context),
              child: Text(l10n.unlock),
            ),
          ],
        ),
      ),
    );

    // ONE shape of tree whatever the state, so [child] keeps its place — and
    // its state — when the door closes and opens again: always the first
    // child of the Stack, with the lock (when there is one) after it.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_built)
          Offstage(
            offstage: !open,
            child: TickerMode(
              enabled: open,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) =>
                    ref.read(debtUnlockedProvider.notifier).touch(),
                child: widget.child,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        if (!open)
          lock,
      ],
    );
  }
}

/// For a sheet or dialog opened FROM a debt screen (one ledger entry in
/// full, the reason of a reversal): it closes when the debt session locks,
/// so nothing of the ledger stays on screen over the lock.
class ClosesWithDebtSession extends ConsumerWidget {
  const ClosesWithDebtSession({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(debtUnlockedProvider, (previous, next) {
      if (previous != true || next) return;
      final route = ModalRoute.of(context);
      if (route == null || !route.isActive) return;
      Navigator.of(context)
        ..popUntil((candidate) => candidate == route)
        ..pop();
    });
    return child;
  }
}
