import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/save_guard.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/bidi.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../archive/invoice_detail_screen.dart';
import '../security/audit_providers.dart';
import '../security/pin_session.dart';
import 'code_widgets.dart';

/// "Was this card sold, and to whom?" — type or paste a FULL code; the
/// answer is its status, the sale date, the invoice number and the customer.
///
/// The search goes by the code's hash, so nothing is decrypted to find it
/// and a partial code finds nothing. The screen is opened behind the PIN
/// (by the caller) and every search is written to the audit log.
class CodeLookupScreen extends ConsumerStatefulWidget {
  const CodeLookupScreen({super.key});

  @override
  ConsumerState<CodeLookupScreen> createState() => _CodeLookupScreenState();
}

class _CodeLookupScreenState extends ConsumerState<CodeLookupScreen> {
  final _controller = TextEditingController();
  List<CodeLookupResult>? _results;
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final code = _controller.text;
    if (normalizeCode(code).isEmpty || _searching) return;
    final repository = ref.read(voucherRepositoryProvider);
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _searching = true);
    // A lookup that fails (the Keystore, the database) must free the search
    // again and say so; null = it failed.
    final found = await runSave(
      context,
      what: 'code lookup',
      () => repository.lookup(code),
    );
    container.invalidate(auditLogProvider);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (found != null) _results = found;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = _results;

    return PinGuardedRoute(
      child: Scaffold(
      appBar: AppBar(title: Text(l10n.lookupTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('lookup-field'),
                    controller: _controller,
                    autofocus: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: l10n.lookupHint,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  key: const ValueKey('lookup-search'),
                  tooltip: l10n.lookupAction,
                  onPressed: _searching ? null : _search,
                  icon: const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: results == null
                ? const SizedBox.shrink()
                : results.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            l10n.lookupNotFound,
                            key: const ValueKey('lookup-not-found'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView(
                        key: const ValueKey('lookup-results'),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          for (final result in results)
                            _LookupCard(result: result),
                        ],
                      ),
          ),
        ],
      ),
      ),
    );
  }
}

class _LookupCard extends ConsumerWidget {
  const _LookupCard({required this.result});

  final CodeLookupResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final dates = DateFormat.yMd(locale).add_jm();

    Widget line(IconData icon, String text, {Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: theme.colorScheme.outline),
              const SizedBox(width: 8),
              Expanded(child: Text(text, key: key)),
            ],
          ),
        );

    return Card(
      key: ValueKey('lookup-result-${result.id}'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(result.productName, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              codeStatusLabel(l10n, result),
              key: const ValueKey('lookup-status'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: result.status == VoucherStatus.sold
                    ? theme.colorScheme.primary
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            if (result.soldAt != null)
              line(
                Icons.event,
                l10n.lookupSoldOn(dates.format(result.soldAt!.toLocal())),
                key: const ValueKey('lookup-sold-on'),
              ),
            if (result.soldInvoiceNo != null)
              line(
                Icons.receipt_long,
                l10n.invoiceNoLabel(formatMinor(
                  result.soldInvoiceNo!,
                  decimals: 0,
                  locale: locale,
                )),
                key: const ValueKey('lookup-invoice-no'),
              ),
            if (result.soldCustomerName != null &&
                result.soldCustomerName!.isNotEmpty)
              line(
                Icons.person_outline,
                l10n.lookupCustomer(result.soldCustomerName!),
                key: const ValueKey('lookup-customer'),
              ),
            if (result.soldAccountNumber != null &&
                result.soldAccountNumber!.isNotEmpty)
              line(
                Icons.badge_outlined,
                l10n.lookupAccount(ltrIsolate(result.soldAccountNumber!)),
              ),
            if (result.serial != null && result.serial!.isNotEmpty)
              line(Icons.tag, l10n.serialLabel(ltrIsolate(result.serial!))),
            if (result.statusNote != null && result.statusNote!.isNotEmpty)
              line(
                Icons.notes,
                l10n.auditDetailReason(result.statusNote!),
              ),
            if (result.invoiceId != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('lookup-open-invoice'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          InvoiceDetailScreen(invoiceId: result.invoiceId!),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l10n.lookupOpenInvoice),
                ),
              )
            else if (result.soldInvoiceNo != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.lookupInvoiceDeleted,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
