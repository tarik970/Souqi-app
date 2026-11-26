import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/load_error_view.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../security/pin_dialogs.dart';
import 'code_widgets.dart';
import 'voucher_providers.dart';

/// Unsold codes past their expiry date. They are never sold automatically;
/// they wait here for the owner to decide: void them (written off), or —
/// when the date was simply wrong — correct the batch's expiry from the
/// product's stock screen, which puts them back on sale.
class ExpiredCodesScreen extends ConsumerWidget {
  const ExpiredCodesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final codes = ref.watch(expiredCodesProvider(null));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.expiredCodesTitle)),
      body: codes.when(
        skipLoadingOnReload: true,
        loading: () => const SizedBox.shrink(),
        error: (e, stack) => LoadErrorView(e, stack),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  l10n.expiredEmpty,
                  key: const ValueKey('expired-empty'),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Grouped by product, in the order the list arrives in.
          final groups = <int, List<VoucherCodeView>>{};
          for (final code in items) {
            groups.putIfAbsent(code.productId, () => []).add(code);
          }
          return ListView(
            key: const ValueKey('expired-list'),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              for (final group in groups.values) _ExpiredGroup(codes: group),
            ],
          );
        },
      ),
    );
  }
}

class _ExpiredGroup extends ConsumerWidget {
  const _ExpiredGroup({required this.codes});

  final List<VoucherCodeView> codes;

  Future<void> _voidAll(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final container = ProviderScope.containerOf(context, listen: false);
    final locale = container.read(appLocaleProvider).languageCode;
    final first = codes.first;
    String count(int value) => formatMinor(value, decimals: 0, locale: locale);

    final reason = await showDialog<String>(
      context: context,
      builder: (_) => ReasonDialog(
        title: l10n.voidExpiredTitle,
        message: l10n.voidExpiredMessage(
          count(codes.length),
          first.productName,
        ),
        confirmLabel: l10n.voidExpiredAction,
      ),
    );
    if (reason == null || !context.mounted) return;
    if (!await requirePin(context, reason: l10n.pinReasonCodes)) return;

    final voided = await container
        .read(voucherRepositoryProvider)
        .voidExpired(productId: first.productId, reason: reason);
    refreshVoucherData(container);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(l10n.expiredVoided(count(voided)))),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final first = codes.first;

    return Card(
      key: ValueKey('expired-product-${first.productId}'),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              first.productName,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              l10n.cardsCount(
                formatMinor(codes.length, decimals: 0, locale: locale),
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final code in codes) CodeTile(code: code, dense: true),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: OutlinedButton.icon(
              key: ValueKey('expired-void-${first.productId}'),
              onPressed: () => _voidAll(context),
              icon: const Icon(Icons.block),
              label: Text(l10n.voidExpiredAction),
            ),
          ),
        ],
      ),
    );
  }
}
