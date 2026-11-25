import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/exchange.dart';
import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';

/// Asks for "1 [currency] = ? [baseCode]", stores the exact fraction and
/// refreshes the currency providers. Returns true when a rate was saved.
///
/// Shared by the currencies screen and the sale screen's quick rate update.
Future<bool> showUpdateRateDialog(
  BuildContext context, {
  required Currency currency,
  required String baseCode,
}) async {
  // Taken before the dialog opens: a rate the user saved must be written even
  // if the widget that opened the dialog is gone by the time it closes, and a
  // WidgetRef must not be touched after its widget was disposed.
  final container = ProviderScope.containerOf(context, listen: false);
  final rate = await showDialog<RateFraction>(
    context: context,
    builder: (_) => UpdateRateDialog(currency: currency, baseCode: baseCode),
  );
  if (rate == null) return false;
  await container
      .read(currencyRepositoryProvider)
      .updateRate(currency.code, rate);
  container.invalidate(currenciesProvider);
  return true;
}

/// The dialog itself. Pops with the entered [RateFraction], or with nothing
/// when cancelled.
///
/// It owns its text controller. The controller used to be created by
/// [showUpdateRateDialog] and disposed as soon as `showDialog` returned — but
/// that future completes when the route is POPPED, while the dialog stays in
/// the tree for the whole exit animation. Its text field then rebuilt (losing
/// focus, the keyboard sliding away) on a disposed controller, which threw
/// and left the element tree broken ("_dependents.isEmpty"). A controller
/// disposed in [State.dispose] lives exactly as long as the field that uses
/// it.
class UpdateRateDialog extends StatefulWidget {
  const UpdateRateDialog({
    super.key,
    required this.currency,
    required this.baseCode,
  });

  final Currency currency;
  final String baseCode;

  @override
  State<UpdateRateDialog> createState() => _UpdateRateDialogState();
}

class _UpdateRateDialogState extends State<UpdateRateDialog> {
  late final _controller = TextEditingController(
    text: widget.currency.rateUpdatedAt == null
        ? ''
        : rateToPlainText(widget.currency.rate),
  );
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final RateFraction rate;
    try {
      rate = parseRateFraction(_controller.text);
    } on FormatException {
      setState(
        () => _errorText = AppLocalizations.of(context).invalidRate,
      );
      return;
    }
    Navigator.of(context).pop(rate);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.updateRate),
      content: SelectAllOnFocus(
        controller: _controller,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.rateHint(widget.currency.code, widget.baseCode),
            errorText: _errorText,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.save)),
      ],
    );
  }
}
