import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/exchange.dart';
import '../../core/providers.dart';
import '../../data/repositories/currency_repository.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';
import 'currency_form_screen.dart';

class CurrenciesScreen extends ConsumerWidget {
  const CurrenciesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currencies = ref.watch(currenciesProvider);
    final baseCode = ref.watch(baseCurrencyCodeProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.currenciesTitle)),
      body: currencies.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) => _CurrencyTile(
            currency: items[index],
            baseCode: baseCode,
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CurrencyFormScreen()),
        ),
        icon: const Icon(Icons.add),
        label: Text(l10n.addCurrency),
      ),
    );
  }
}

class _CurrencyTile extends ConsumerWidget {
  const _CurrencyTile({required this.currency, required this.baseCode});

  final Currency currency;
  final String? baseCode;

  bool get _isBase => currency.code == baseCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);

    final subtitleLines = <String>[];
    if (!_isBase && baseCode != null) {
      subtitleLines.add(l10n.rateDisplay(
          currency.code, _rateValueText(currency.rate, locale), baseCode!));
      subtitleLines.add(currency.rateUpdatedAt == null
          ? l10n.rateNeverUpdated
          : l10n.rateUpdatedAt(DateFormat.yMd(locale)
              .add_jm()
              .format(currency.rateUpdatedAt!.toLocal())));
    }

    return ListTile(
      enabled: currency.isActive,
      leading: CircleAvatar(
        child: Text(
          currency.symbol.isEmpty ? currency.code : currency.symbol,
          style: const TextStyle(fontSize: 12),
        ),
      ),
      title: Row(
        children: [
          Flexible(child: Text('${currency.nameFor(locale)} (${currency.code})')),
          if (_isBase) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(l10n.baseBadge),
              visualDensity: VisualDensity.compact,
              backgroundColor: theme.colorScheme.secondaryContainer,
            ),
          ] else if (!currency.isActive) ...[
            const SizedBox(width: 8),
            Chip(
              label: Text(l10n.inactiveBadge),
              visualDensity: VisualDensity.compact,
            ),
          ],
          if (!_isBase && currency.rateUpdatedAt == null) ...[
            const SizedBox(width: 8),
            Icon(Icons.warning_amber,
                size: 18, color: theme.colorScheme.error),
          ],
        ],
      ),
      subtitle:
          subtitleLines.isEmpty ? null : Text(subtitleLines.join('\n')),
      isThreeLine: subtitleLines.length > 1,
      trailing: PopupMenuButton<void>(
        itemBuilder: (context) => [
          if (!_isBase)
            PopupMenuItem<void>(
              child: Text(l10n.updateRate),
              onTap: () => _updateRate(context, ref),
            ),
          PopupMenuItem<void>(
            child: Text(l10n.edit),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CurrencyFormScreen(currency: currency),
              ),
            ),
          ),
          if (!_isBase) ...[
            PopupMenuItem<void>(
              child: Text(l10n.setAsBase),
              onTap: () => _setAsBase(context, ref),
            ),
            PopupMenuItem<void>(
              child: Text(currency.isActive
                  ? l10n.inactiveBadge
                  : l10n.activeLabel),
              onTap: () => _toggleActive(context, ref),
            ),
          ],
        ],
      ),
    );
  }

  String _rateValueText(RateFraction rate, String locale) {
    if (rate.denominator == 1) {
      return NumberFormat.decimalPattern(locale).format(rate.numerator);
    }
    // Reduced denominators only contain factors 2 and 5 (rates are entered
    // as decimals), so the expansion terminates; double is display-only.
    var text = (rate.numerator / rate.denominator).toStringAsFixed(10);
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
    return text;
  }

  Future<void> _updateRate(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    String? errorText;
    final rate = await showDialog<RateFraction>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.updateRate),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.rateHint(currency.code, baseCode ?? ''),
              errorText: errorText,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.of(context)
                      .pop(parseRateFraction(controller.text));
                } on FormatException {
                  setState(() => errorText = l10n.invalidRate);
                }
              },
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (rate == null) return;
    await ref.read(currencyRepositoryProvider).updateRate(currency.code, rate);
    ref.invalidate(currenciesProvider);
  }

  Future<void> _setAsBase(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(currencyRepositoryProvider);
    if (!await repo.canChangeBase()) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.baseChangeLocked)));
      return;
    }
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.baseChangeTitle),
        content: Text(l10n.baseChangeWarning(currency.code)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.setAsBase),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.setBase(currency.code);
    } on BaseCurrencyLockedException {
      messenger.showSnackBar(SnackBar(content: Text(l10n.baseChangeLocked)));
    }
    ref.invalidate(currenciesProvider);
    ref.invalidate(baseCurrencyCodeProvider);
  }

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(currencyRepositoryProvider)
          .setActive(currency.code, !currency.isActive);
      ref.invalidate(currenciesProvider);
    } on BaseCurrencyException {
      messenger
          .showSnackBar(SnackBar(content: Text(l10n.cannotDisableBase)));
    }
  }
}
