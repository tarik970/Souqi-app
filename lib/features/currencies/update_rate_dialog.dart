import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/exchange.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';

/// Asks for "1 [currency] = ? [baseCode]", stores the exact fraction and
/// refreshes the currency providers. Returns true when a rate was saved.
///
/// Shared by the currencies screen and the sale screen's quick rate update.
Future<bool> showUpdateRateDialog(
  BuildContext context,
  WidgetRef ref, {
  required Currency currency,
  required String baseCode,
}) async {
  final l10n = AppLocalizations.of(context);
  final controller = TextEditingController(
    text: currency.rateUpdatedAt == null ? '' : rateToPlainText(currency.rate),
  );
  String? errorText;
  final rate = await showDialog<RateFraction>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(l10n.updateRate),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: l10n.rateHint(currency.code, baseCode),
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
                Navigator.of(context).pop(parseRateFraction(controller.text));
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
  controller.dispose();
  if (rate == null) return false;
  await ref.read(currencyRepositoryProvider).updateRate(currency.code, rate);
  ref.invalidate(currenciesProvider);
  return true;
}
