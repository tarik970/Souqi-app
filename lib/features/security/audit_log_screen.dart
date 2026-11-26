import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/voucher_format.dart';
import '../../data/repositories/archive_repository.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import 'audit_providers.dart';
import 'pin_session.dart';

/// The log of sensitive actions: when, what, on which product. Opened from
/// the settings after the PIN (the caller asks for it — this screen only
/// shows).
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  static const List<ArchivePeriod> periods = [
    ArchivePeriod.all,
    ArchivePeriod.today,
    ArchivePeriod.thisWeek,
    ArchivePeriod.thisMonth,
    ArchivePeriod.custom,
  ];

  static String _periodLabel(AppLocalizations l10n, ArchivePeriod period) =>
      switch (period) {
        ArchivePeriod.all => l10n.periodAll,
        ArchivePeriod.today => l10n.periodToday,
        ArchivePeriod.yesterday => l10n.periodYesterday,
        ArchivePeriod.thisWeek => l10n.periodThisWeek,
        ArchivePeriod.thisMonth => l10n.periodThisMonth,
        ArchivePeriod.custom => l10n.periodCustom,
      };

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    ArchivePeriod value,
  ) async {
    if (value != ArchivePeriod.custom) {
      ref.read(auditPeriodProvider.notifier).setPreset(value);
      return;
    }
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, now.month, now.day),
    );
    if (picked == null || !context.mounted) return;
    ref
        .read(auditPeriodProvider.notifier)
        .setCustomRange(picked.start, picked.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final period = ref.watch(auditPeriodProvider);
    final log = ref.watch(auditLogProvider);
    final range = period.range;
    final locale = ref.watch(appLocaleProvider).languageCode;
    final dates = DateFormat.yMd(locale);

    return PinGuardedRoute(
      child: Scaffold(
      appBar: AppBar(title: Text(l10n.auditLogTitle)),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                for (final value in periods) ...[
                  if (value != periods.first) const SizedBox(width: 8),
                  ChoiceChip(
                    key: ValueKey('audit-period-${value.name}'),
                    label: Text(_periodLabel(l10n, value)),
                    selected: period.preset == value,
                    onSelected: (_) => _select(context, ref, value),
                  ),
                ],
              ],
            ),
          ),
          if (range != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.periodRangeLabel(
                    dates.format(range.from),
                    dates.format(range.to.subtract(const Duration(days: 1))),
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Expanded(
            child: log.when(
              skipLoadingOnReload: true,
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Center(child: Text('$e')),
              data: (data) => data.entries.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          l10n.auditEmpty,
                          key: const ValueKey('audit-empty'),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const ValueKey('audit-list'),
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: data.entries.length + (data.hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        if (index >= data.entries.length) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: OutlinedButton(
                              key: const ValueKey('audit-load-more'),
                              onPressed: () => ref
                                  .read(auditLogProvider.notifier)
                                  .loadMore(),
                              child: Text(l10n.loadMore),
                            ),
                          );
                        }
                        return _AuditTile(entry: data.entries[index]);
                      },
                    ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// The words for one logged action.
String auditActionLabel(AppLocalizations l10n, String action) =>
    switch (AuditAction.fromDb(action)) {
      AuditAction.codeImport => l10n.auditCodeImport,
      AuditAction.codeReveal => l10n.auditCodeReveal,
      AuditAction.codeLookup => l10n.auditCodeLookup,
      AuditAction.codeVoid => l10n.auditCodeVoid,
      AuditAction.codeRestore => l10n.auditCodeRestore,
      AuditAction.codeExport => l10n.auditCodeExport,
      AuditAction.codeExpiryChange => l10n.auditCodeExpiryChange,
      AuditAction.batchDelete => l10n.auditBatchDelete,
      AuditAction.invoiceReprint => l10n.auditInvoiceReprint,
      AuditAction.pinSet => l10n.auditPinSet,
      AuditAction.pinChange => l10n.auditPinChange,
      AuditAction.pinRemove => l10n.auditPinRemove,
      AuditAction.recoveryCodeCreate => l10n.auditRecoveryCodeCreate,
      AuditAction.pinRecover => l10n.auditPinRecover,
      AuditAction.pinResetSigned => l10n.auditPinResetSigned,
      AuditAction.debtReversal => l10n.auditDebtReversal,
      AuditAction.debtAdjustment => l10n.auditDebtAdjustment,
      AuditAction.creditLimitOverride => l10n.auditCreditLimitOverride,
      AuditAction.debtReportOn => l10n.auditDebtReportOn,
      AuditAction.debtReportOff => l10n.auditDebtReportOff,
      AuditAction.debtReportFolder => l10n.auditDebtReportFolder,
      // Written by a newer version of the app: show what was stored.
      null => action,
    };

IconData _auditIcon(String action) => switch (AuditAction.fromDb(action)) {
      AuditAction.codeImport => Icons.playlist_add,
      AuditAction.codeReveal => Icons.visibility_outlined,
      AuditAction.codeLookup => Icons.search,
      AuditAction.codeVoid => Icons.block,
      AuditAction.codeRestore => Icons.undo,
      AuditAction.codeExport => Icons.ios_share,
      AuditAction.codeExpiryChange => Icons.event,
      AuditAction.batchDelete => Icons.delete_outline,
      AuditAction.invoiceReprint => Icons.print_outlined,
      AuditAction.pinSet ||
      AuditAction.pinChange ||
      AuditAction.pinRemove =>
        Icons.lock_outline,
      AuditAction.recoveryCodeCreate => Icons.key_outlined,
      AuditAction.pinRecover || AuditAction.pinResetSigned => Icons.lock_reset,
      AuditAction.debtReversal => Icons.undo,
      AuditAction.debtAdjustment => Icons.tune,
      AuditAction.creditLimitOverride => Icons.report_gmailerrorred_outlined,
      AuditAction.debtReportOn || AuditAction.debtReportOff =>
        Icons.summarize_outlined,
      AuditAction.debtReportFolder => Icons.folder_outlined,
      null => Icons.info_outline,
    };

class _AuditTile extends ConsumerWidget {
  const _AuditTile({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final details = entry.details;
    String number(Object? value) =>
        formatMinor(value as int, decimals: 0, locale: locale);

    // Small facts, each its own piece: a count, the card's last digits, the
    // invoice, the reason that was typed.
    // Debt actions carry the customer and base-currency amounts.
    final base = ref.watch(baseCurrencyProvider).value;
    String amount(Object? value) => formatMinor(
          (value as int).abs(),
          decimals: base?.decimalPlaces ?? 0,
          locale: locale,
          symbol: base == null
              ? ''
              : (base.symbol.isEmpty ? base.code : base.symbol),
        );
    final facts = <String>[
      if (entry.productName != null) entry.productName!,
      if (details['customer'] is String) details['customer'] as String,
      if (details['amount'] is int) amount(details['amount']),
      if (details['receipt_no'] is int)
        l10n.receiptNoLabel(number(details['receipt_no'])),
      if (details['new_balance'] is int && details['limit'] is int)
        '${l10n.newBalanceLabel}: ${amount(details['new_balance'])} · '
            '${l10n.creditLimitLabel}: ${amount(details['limit'])}',
      if (details['count'] is int) l10n.cardsCount(number(details['count'])),
      if (details['found'] is int)
        l10n.auditDetailFound(number(details['found'])),
      if (details['tail'] is String && (details['tail'] as String).isNotEmpty)
        ltrIsolate(maskWithTail(details['tail'] as String)),
      if (details['serial'] is String)
        l10n.serialLabel(ltrIsolate(details['serial'] as String)),
      if (details['invoice_no'] is int)
        l10n.invoiceNoLabel(number(details['invoice_no'])),
      if (details['folder'] is String)
        l10n.auditDetailFolder(details['folder'] as String),
      if (details['reason'] is String &&
          (details['reason'] as String).isNotEmpty)
        l10n.auditDetailReason(details['reason'] as String),
    ];

    return ListTile(
      key: ValueKey('audit-${entry.id}'),
      leading: Icon(_auditIcon(entry.action)),
      title: Text(auditActionLabel(l10n, entry.action)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (facts.isNotEmpty) Text(facts.join(' · ')),
          Text(
            DateFormat.yMd(locale).add_jm().format(entry.createdAt.toLocal()),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
