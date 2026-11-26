import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/constants/settings_keys.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/customers_providers.dart';
import '../security/audit_providers.dart';
import '../security/pin_dialogs.dart';
import '../security/pin_session.dart';
import '../stats/stats_providers.dart';

/// Formats BASE-currency amounts — the currency every balance is in — for
/// the app language.
class BaseMoney {
  const BaseMoney({
    required this.code,
    required this.symbol,
    required this.decimals,
    required this.locale,
  });

  final String code;
  final String symbol;
  final int decimals;
  final String locale;

  String get label => symbol.isEmpty ? code : symbol;

  /// "12,500 ل.س".
  String call(int minor) =>
      formatMinor(minor, decimals: decimals, locale: locale, symbol: label);

  /// "12,500", for a column that already says which currency it is in.
  String plain(int minor) =>
      formatMinor(minor, decimals: decimals, locale: locale);
}

final baseMoneyProvider = Provider<BaseMoney>((ref) {
  final base = ref.watch(baseCurrencyProvider).value;
  return BaseMoney(
    code: base?.code ?? '',
    symbol: base?.symbol ?? '',
    decimals: base?.decimalPlaces ?? 0,
    locale: ref.watch(appLocaleProvider).languageCode,
  );
});

/// Every customer with a non-zero balance and their FIFO aging — behind the
/// debtors list, the home card and the debt statistics. Kept (not
/// auto-disposed): it is the one expensive read of the ledger, and it is
/// thrown away exactly when the ledger changes ([refreshDebtData]).
final debtorsProvider = FutureProvider<DebtorsSnapshot>((ref) {
  if (!featureOn(Feature.debt)) {
    return DebtorsSnapshot.empty(DateTime.now());
  }
  return ref.watch(debtRepositoryProvider).debtors(now: ref.watch(clockProvider)());
});

/// Where one customer's account stands.
final accountSummaryProvider =
    FutureProvider.autoDispose.family<AccountSummary, int>(
  (ref, customerId) => ref
      .watch(debtRepositoryProvider)
      .accountSummary(customerId, now: ref.watch(clockProvider)()),
);

/// What the Account tab is showing of one customer's ledger.
class LedgerRequest {
  const LedgerRequest({
    required this.customerId,
    this.from,
    this.to,
    required this.limit,
  });

  final int customerId;

  /// Inclusive / exclusive; null = unbounded.
  final DateTime? from;
  final DateTime? to;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is LedgerRequest &&
      other.customerId == customerId &&
      other.from == from &&
      other.to == to &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(customerId, from, to, limit);
}

/// One customer's ledger, newest first, with running balances. One row more
/// than [LedgerRequest.limit] is read, so the screen knows whether there is
/// more to show.
final ledgerProvider =
    FutureProvider.autoDispose.family<List<LedgerLine>, LedgerRequest>(
  (ref, request) => ref.watch(debtRepositoryProvider).ledger(
        request.customerId,
        from: request.from,
        to: request.to,
        limit: request.limit + 1,
      ),
);

/// The shop's default number of days to pay (default 30).
final debtDefaultDueDaysProvider = FutureProvider<int>((ref) async {
  final days = await ref
      .watch(settingsRepositoryProvider)
      .getInt(SettingsKeys.debtDefaultDueDays, fallback: 30);
  return days < 0 ? 0 : days;
});

/// Whether the debtors list and customer accounts ask for the PIN.
final debtRequirePinProvider = FutureProvider<bool>(
  (ref) =>
      ref.watch(settingsRepositoryProvider).getBool(SettingsKeys.debtRequirePin),
);

/// The stored debt reminder text; '' means "the built-in default in the
/// invoice language".
final debtReminderTemplateProvider = FutureProvider<String>(
  (ref) => ref
      .watch(settingsRepositoryProvider)
      .getString(SettingsKeys.debtReminderText),
);

/// Goes up by one every time the ledger is written to. Providers that read
/// the ledger and are not listed in [refreshDebtData] (a statement, a
/// receipt) watch it, and so reload with everything else.
class LedgerRevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final ledgerRevisionProvider =
    NotifierProvider<LedgerRevisionNotifier, int>(LedgerRevisionNotifier.new);

/// Everything that shows balances is now stale: an entry was written to the
/// ledger (a sale on credit, a payment, a reversal…).
///
/// Takes the container so it still runs when the screen that caused it has
/// already been closed.
void refreshDebtData(ProviderContainer container) {
  container.read(ledgerRevisionProvider.notifier).bump();
  container
    ..invalidate(debtorsProvider)
    ..invalidate(accountSummaryProvider)
    ..invalidate(ledgerProvider)
    ..invalidate(debtStatsProvider)
    // Reversals, adjustments and limit overrides write to the audit log.
    ..invalidate(auditLogProvider);
}

/// The debts, unlocked with the PIN: one session for the debtors list,
/// customer accounts, payments, statements and the figures on the home and
/// statistics screens. It locks again after the "lock again after" time
/// without a touch on a debt screen, and at once when the app goes to the
/// background (see [PinSessionNotifier]).
class DebtUnlockNotifier extends PinSessionNotifier {}

final debtUnlockedProvider =
    NotifierProvider<DebtUnlockNotifier, bool>(DebtUnlockNotifier.new);

/// The gate in front of the debtors list and customer accounts: with the
/// "PIN to open debts" setting on, asks for the PIN unless the debt session
/// is still unlocked. Returns whether the caller may go on. Recording a
/// debt at a sale never comes through here.
Future<bool> requireDebtAccess(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!await container.read(debtRequirePinProvider.future)) return true;
  if (container.read(debtUnlockedProvider)) {
    // Opening a debt screen is using the session.
    container.read(debtUnlockedProvider.notifier).touch();
    return true;
  }
  // The idle time is read before the timer needs it.
  await container.read(pinAutoLockMinutesProvider.future);
  if (!context.mounted) return false;
  final l10n = AppLocalizations.of(context);
  if (!await requirePin(context, reason: l10n.pinReasonDebtAccess)) {
    return false;
  }
  container.read(debtUnlockedProvider.notifier).unlock();
  return true;
}
