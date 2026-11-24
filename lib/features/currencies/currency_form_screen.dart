import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/money/exchange.dart';
import '../../core/providers.dart';
import '../../domain/models/currency.dart';
import '../../l10n/generated/app_localizations.dart';

/// Adds a currency (code + names + rate) or edits an existing one
/// (names, symbol, decimals; the rate is updated from the list screen).
class CurrencyFormScreen extends ConsumerStatefulWidget {
  const CurrencyFormScreen({super.key, this.currency});

  final Currency? currency;

  @override
  ConsumerState<CurrencyFormScreen> createState() =>
      _CurrencyFormScreenState();
}

class _CurrencyFormScreenState extends ConsumerState<CurrencyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code;
  late final TextEditingController _nameAr;
  late final TextEditingController _nameEn;
  late final TextEditingController _symbol;
  late final TextEditingController _rate;
  late int _decimals;
  String? _codeError;
  bool _saving = false;

  Currency? get _initial => widget.currency;

  bool get _isNew => _initial == null;

  @override
  void initState() {
    super.initState();
    _code = TextEditingController(text: _initial?.code ?? '');
    _nameAr = TextEditingController(text: _initial?.nameAr ?? '');
    _nameEn = TextEditingController(text: _initial?.nameEn ?? '');
    _symbol = TextEditingController(text: _initial?.symbol ?? '');
    _rate = TextEditingController();
    _decimals = _initial?.decimalPlaces ?? 0;
  }

  @override
  void dispose() {
    _code.dispose();
    _nameAr.dispose();
    _nameEn.dispose();
    _symbol.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    setState(() => _codeError = null);
    if (!_formKey.currentState!.validate()) return;

    final repo = ref.read(currencyRepositoryProvider);
    // The list is refreshed through the container: the save must show up
    // even if this screen was closed while it ran.
    final container = ProviderScope.containerOf(context, listen: false);
    if (_isNew) {
      final code = _code.text.trim().toUpperCase();
      if (await repo.codeExists(code)) {
        if (!mounted) return;
        setState(() => _codeError = l10n.currencyCodeExists);
        return;
      }
      if (!mounted) return;
      setState(() => _saving = true);
      await repo.insert(Currency(
        code: code,
        nameAr: _nameAr.text.trim(),
        nameEn: _nameEn.text.trim(),
        symbol: _symbol.text.trim(),
        decimalPlaces: _decimals,
        rate: parseRateFraction(_rate.text),
        rateUpdatedAt: DateTime.now().toUtc(),
      ));
    } else {
      setState(() => _saving = true);
      await repo.update(Currency(
        code: _initial!.code,
        nameAr: _nameAr.text.trim(),
        nameEn: _nameEn.text.trim(),
        symbol: _symbol.text.trim(),
        decimalPlaces: _decimals,
        rate: _initial!.rate,
        rateUpdatedAt: _initial!.rateUpdatedAt,
        isActive: _initial!.isActive,
        sortOrder: _initial!.sortOrder,
      ));
    }
    container.invalidate(currenciesProvider);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final baseCode = ref.watch(baseCurrencyCodeProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? l10n.addCurrency : l10n.editCurrency),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isNew) ...[
              TextFormField(
                controller: _code,
                decoration: InputDecoration(
                  labelText: l10n.currencyCode,
                  errorText: _codeError,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 8,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _nameAr,
              decoration: InputDecoration(labelText: l10n.currencyNameAr),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameEn,
              decoration: InputDecoration(labelText: l10n.currencyNameEn),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? l10n.fieldRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _symbol,
              decoration: InputDecoration(labelText: l10n.currencySymbol),
              maxLength: 6,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _decimals,
              decoration: InputDecoration(labelText: l10n.currencyDecimals),
              items: [
                for (var d = 0; d <= 4; d++)
                  DropdownMenuItem(value: d, child: Text('$d')),
              ],
              onChanged: (v) => setState(() => _decimals = v ?? 0),
            ),
            if (_isNew) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                decoration: InputDecoration(
                  labelText: l10n.exchangeRate,
                  hintText: l10n.rateHint(
                    _code.text.trim().isEmpty
                        ? '…'
                        : _code.text.trim().toUpperCase(),
                    baseCode,
                  ),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  try {
                    parseRateFraction(v ?? '');
                    return null;
                  } on FormatException {
                    return l10n.invalidRate;
                  }
                },
              ),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
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
