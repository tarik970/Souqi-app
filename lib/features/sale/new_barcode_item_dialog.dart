import 'package:material_ui/material_ui.dart';

import '../../core/utils/bidi.dart';
import '../../l10n/generated/app_localizations.dart';

/// "No product has the barcode 6221234567890 — what is it called?" The name
/// starts the type-to-sell sheet with the barcode attached; the product
/// itself is made when the invoice is saved, like any typed item. Pops the
/// name, or null.
class NewBarcodeItemDialog extends StatefulWidget {
  const NewBarcodeItemDialog({super.key, required this.barcode});

  final String barcode;

  @override
  State<NewBarcodeItemDialog> createState() => _NewBarcodeItemDialogState();
}

class _NewBarcodeItemDialogState extends State<NewBarcodeItemDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('new-barcode-dialog'),
      title: Text(l10n.newProductWithBarcode),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.barcodeUnknown(ltrIsolate(widget.barcode))),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('new-barcode-name'),
            controller: _name,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: l10n.productName),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ListenableBuilder(
          listenable: _name,
          builder: (context, _) => FilledButton(
            key: const ValueKey('new-barcode-next'),
            onPressed: _name.text.trim().isEmpty ? null : _submit,
            child: Text(l10n.restoreNext),
          ),
        ),
      ],
    );
  }
}
