import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/security/code_cipher.dart';
import '../../core/utils/voucher_format.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../security/audit_providers.dart';
import '../security/pin_dialogs.dart';
import '../security/pin_session.dart';
import 'voucher_providers.dart';

/// The status of a code in words. An AVAILABLE code past its expiry reads
/// "Expired": that is what matters about it.
String codeStatusLabel(
  AppLocalizations l10n,
  VoucherCodeView code, {
  DateTime? now,
}) {
  if (code.isExpired(now ?? DateTime.now())) return l10n.codeStatusExpired;
  return switch (code.status) {
    VoucherStatus.available => l10n.codeStatusAvailable,
    VoucherStatus.sold => l10n.codeStatusSold,
    VoucherStatus.voided => l10n.codeStatusVoid,
  };
}

enum _CodeAction { reveal, voidIt, returnIt }

/// One code in a list: masked, with its serial, status and — once sold —
/// who got it; and a menu for the three PIN-guarded actions.
///
/// The widget never holds the code itself. "Show the code" fetches it after
/// the PIN, shows it in a dialog and lets go of it.
class CodeTile extends ConsumerWidget {
  const CodeTile({
    super.key,
    required this.code,
    this.showProduct = false,
    this.dense = false,
  });

  final VoucherCodeView code;

  /// Lists that mix products (the expired list, the lookup) name it.
  final bool showProduct;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final dates = DateFormat.yMd(locale);
    final expired = code.isExpired(DateTime.now());

    final facts = <String>[
      codeStatusLabel(l10n, code),
      if (code.serial != null && code.serial!.isNotEmpty)
        l10n.serialLabel(code.serial!),
      if (code.expiryAt != null)
        l10n.batchExpires(dates.format(expiryLastDay(code.expiryAt!))),
      if (code.soldAt != null)
        l10n.lookupSoldOn(dates.format(code.soldAt!.toLocal())),
      if (code.soldInvoiceNo != null)
        l10n.invoiceNoLabel(
          formatMinor(code.soldInvoiceNo!, decimals: 0, locale: locale),
        ),
      if (code.soldCustomerName != null && code.soldCustomerName!.isNotEmpty)
        code.soldCustomerName!,
      if (code.statusNote != null && code.statusNote!.isNotEmpty)
        l10n.auditDetailReason(code.statusNote!),
    ];

    return ListTile(
      key: ValueKey('code-${code.id}'),
      dense: dense,
      leading: Icon(
        switch (code.status) {
          VoucherStatus.available =>
            expired ? Icons.event_busy : Icons.confirmation_number_outlined,
          VoucherStatus.sold => Icons.check_circle_outline,
          VoucherStatus.voided => Icons.block,
        },
        color: expired || code.status == VoucherStatus.voided
            ? theme.colorScheme.error
            : null,
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showProduct)
            Text(
              code.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          // A code is one left-to-right run in both app languages.
          Text(
            code.masked,
            key: ValueKey('code-masked-${code.id}'),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(letterSpacing: 1),
          ),
        ],
      ),
      subtitle: Text(
        code.unreadable
            ? '${l10n.codeUnreadable}\n${facts.join(' · ')}'
            : facts.join(' · '),
      ),
      trailing: PopupMenuButton<_CodeAction>(
        key: ValueKey('code-menu-${code.id}'),
        onSelected: (action) => switch (action) {
          _CodeAction.reveal => revealCode(context, code),
          _CodeAction.voidIt => changeCodeStatus(context, code, toVoid: true),
          _CodeAction.returnIt =>
            changeCodeStatus(context, code, toVoid: false),
        },
        itemBuilder: (context) => [
          if (!code.unreadable)
            PopupMenuItem(
              key: const ValueKey('code-action-reveal'),
              value: _CodeAction.reveal,
              child: Text(l10n.codeReveal),
            ),
          if (code.status != VoucherStatus.voided)
            PopupMenuItem(
              key: const ValueKey('code-action-void'),
              value: _CodeAction.voidIt,
              child: Text(l10n.codeVoid),
            ),
          if (code.status != VoucherStatus.available)
            PopupMenuItem(
              key: const ValueKey('code-action-return'),
              value: _CodeAction.returnIt,
              child: Text(l10n.codeReturn),
            ),
        ],
      ),
    );
  }
}

/// PIN, then the code in full in a dialog. Written to the audit log by the
/// repository.
Future<void> revealCode(BuildContext context, VoucherCodeView code) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;
  final String plain;
  try {
    plain = await container.read(voucherRepositoryProvider).reveal(code.id);
  } on CodeUnreadableException {
    messenger.showSnackBar(SnackBar(content: Text(l10n.codeUnreadable)));
    return;
  }
  container.invalidate(auditLogProvider);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => RevealedCodeDialog(
      productName: code.productName,
      code: plain,
      serial: code.serial,
    ),
  );
}

/// The reason first (it doubles as the confirmation), then the PIN, then the
/// change — void, or return to stock.
Future<void> changeCodeStatus(
  BuildContext context,
  VoucherCodeView code, {
  required bool toVoid,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // The change is carried out even if the list row is rebuilt away.
  final container = ProviderScope.containerOf(context, listen: false);
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => ReasonDialog(
      title: toVoid ? l10n.voidCodeTitle : l10n.returnCodeTitle,
      message: toVoid ? l10n.voidCodeMessage : l10n.returnCodeMessage,
      confirmLabel: toVoid ? l10n.codeVoid : l10n.codeReturn,
    ),
  );
  if (reason == null || !context.mounted) return;
  if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;

  final repository = container.read(voucherRepositoryProvider);
  final changed = toVoid
      ? await repository.voidCode(code.id, reason: reason)
      : await repository.returnToStock(code.id, reason: reason);
  refreshVoucherData(container);
  if (!changed) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(toVoid ? l10n.codeVoided : l10n.codeReturned),
    ));
}

/// Asks why. Pops the reason (never empty), or null when cancelled.
class ReasonDialog extends StatefulWidget {
  const ReasonDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String confirmLabel;

  @override
  State<ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<ReasonDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _controller.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = AppLocalizations.of(context).fieldRequired);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('reason-dialog'),
      scrollable: true,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('reason-field'),
            controller: _controller,
            autofocus: true,
            maxLength: 120,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.reasonLabel,
              errorText: _error,
              counterText: '',
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
          key: const ValueKey('reason-confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// A code in full, grouped in fours, for as long as the dialog is open.
class RevealedCodeDialog extends StatelessWidget {
  const RevealedCodeDialog({
    super.key,
    required this.productName,
    required this.code,
    this.serial,
  });

  final String productName;
  final String code;
  final String? serial;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return PinGuardedRoute(
      child: AlertDialog(
      key: const ValueKey('revealed-code-dialog'),
      scrollable: true,
      title: Text(l10n.codeRevealedTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(productName, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          // Groups wrap between each other, never inside one.
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              key: const ValueKey('revealed-code'),
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 4,
              children: [
                for (final group in codeGroups(code))
                  Text(
                    group,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
              ],
            ),
          ),
          if (serial != null && serial!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              l10n.serialLabel(serial!),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          key: const ValueKey('revealed-code-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.done),
        ),
      ],
      ),
    );
  }
}

/// The "Card codes" block of an invoice screen: every code the invoice sold,
/// masked, each with its menu. Nothing at all for an invoice without codes.
class InvoiceCodesSection extends ConsumerWidget {
  const InvoiceCodesSection({super.key, required this.invoiceId});

  final int invoiceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final codes = ref.watch(invoiceCodesProvider(invoiceId)).value;
    if (codes == null || codes.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const ValueKey('invoice-codes'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(l10n.codesTitle, style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
            child: Text(
              l10n.codesMaskedNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          for (final code in codes)
            CodeTile(code: code, showProduct: true, dense: true),
        ],
      ),
    );
  }
}
