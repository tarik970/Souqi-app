import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_output.dart';
import 'invoice_providers.dart';
import 'output_messages.dart';

enum InvoiceAction {
  print,
  shareImage,
  sharePdf,
  whatsApp,
  saveImage,
  savePdf,
}

/// Everything that can be done with a saved invoice: Print, Share (image or
/// PDF), Send on WhatsApp, Save to phone.
///
/// The OUTPUT MODE setting decides which actions are the big primary
/// buttons (Print, Share, or both); every other action stays one tap away
/// under "More". A customer phone number adds a direct WhatsApp button.
///
/// Reusable: the post-sale screen shows it now, and the archive / reprint
/// screens of phase 4 drop in the same widget for any stored [Invoice].
class InvoiceActions extends ConsumerStatefulWidget {
  const InvoiceActions({
    super.key,
    required this.invoice,
    this.copy = false,
  });

  final Invoice invoice;

  /// Every output of this bar is a REPRINT from the archive and carries the
  /// "COPY / نسخة" mark. The screen right after a sale leaves it false.
  final bool copy;

  @override
  ConsumerState<InvoiceActions> createState() => _InvoiceActionsState();
}

class _InvoiceActionsState extends ConsumerState<InvoiceActions> {
  InvoiceAction? _running;

  Invoice get _invoice => widget.invoice;

  bool get copy => widget.copy;

  InvoiceOutput get _output => ref.read(invoiceOutputProvider);

  IconData _icon(InvoiceAction action) => switch (action) {
        InvoiceAction.print => Icons.print_outlined,
        InvoiceAction.shareImage => Icons.share_outlined,
        InvoiceAction.sharePdf => Icons.picture_as_pdf_outlined,
        InvoiceAction.whatsApp => Icons.chat_outlined,
        InvoiceAction.saveImage => Icons.download_outlined,
        InvoiceAction.savePdf => Icons.download_for_offline_outlined,
      };

  String _label(AppLocalizations l10n, InvoiceAction action,
          {bool primary = false}) =>
      switch (action) {
        InvoiceAction.print => l10n.printInvoice,
        InvoiceAction.shareImage =>
          primary ? l10n.shareInvoice : l10n.shareAsImage,
        InvoiceAction.sharePdf => l10n.sharePdf,
        InvoiceAction.whatsApp => l10n.sendOnWhatsApp,
        InvoiceAction.saveImage => l10n.saveImageToPhone,
        InvoiceAction.savePdf => l10n.savePdfToPhone,
      };

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(InvoiceAction action) async {
    if (_running != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _running = action);
    // Each branch reads `ref` / `widget` once, before its first await;
    // [_snack] checks `mounted` itself.
    final output = _output;
    final invoice = _invoice;
    final isCopy = copy;
    try {
      switch (action) {
        case InvoiceAction.print:
          await output.printInvoice(invoice, copy: isCopy);
          _snack(l10n.printSent);
        case InvoiceAction.shareImage:
          await output.shareImage(invoice, copy: isCopy);
        case InvoiceAction.sharePdf:
          await output.sharePdfFile(invoice, copy: isCopy);
        case InvoiceAction.whatsApp:
          await _sendOnWhatsApp(l10n);
        case InvoiceAction.saveImage:
          _snack(l10n.savedToPhone(await output.saveImage(invoice, copy: isCopy)));
        case InvoiceAction.savePdf:
          _snack(l10n.savedToPhone(await output.savePdf(invoice, copy: isCopy)));
      }
    } on OutputException catch (e) {
      if (mounted) showOutputError(context, ref, e);
    } catch (e) {
      // Anything unexpected (rendering, file system): never fail silently.
      if (mounted) {
        showOutputError(
          context,
          ref,
          OutputException(OutputFailure.unknown, '$e'),
        );
      }
    } finally {
      if (mounted) setState(() => _running = null);
    }
  }

  /// The customer's number in international form, or null when the invoice
  /// has no usable phone.
  String? _customerPhone(InvoiceSettings? settings) {
    if (!customersEnabled) return null;
    final raw = _invoice.customerPhone;
    if (raw == null || raw.trim().isEmpty) return null;
    return toInternationalPhone(
      raw,
      defaultCountryCode: settings?.defaultCountryCode ?? '963',
    );
  }

  Future<void> _sendOnWhatsApp(AppLocalizations l10n) async {
    // Taken before the first await: the two dialogs below can outlive this
    // widget, and neither `ref` nor `widget` may be touched after that.
    final output = _output;
    final bridge = ref.read(nativeBridgeProvider);
    final invoice = _invoice;
    final isCopy = copy;
    final settings = await ref.read(invoiceSettingsProvider.future);
    if (!mounted) return;
    // No customer phone on the invoice: ask for a number for this one send.
    final phone = _customerPhone(settings) ??
        await _askPhone(settings.defaultCountryCode);
    if (phone == null || !mounted) return;

    List<String> packages;
    try {
      packages = await bridge.whatsAppPackages();
    } on OutputException {
      packages = const [];
    }
    if (!mounted) return;
    if (packages.isEmpty) {
      _snack(l10n.whatsAppNotInstalled);
      await output.shareImage(invoice, copy: isCopy);
      return;
    }
    final package =
        packages.length == 1 ? packages.single : await _askPackage(packages);
    if (package == null || !mounted) return;

    final opened = await output.sendToWhatsApp(
      invoice,
      package: package,
      internationalPhone: phone,
      copy: isCopy,
    );
    if (!opened) {
      _snack(l10n.whatsAppUnsupported); // checks `mounted` itself
      await output.shareImage(invoice, copy: isCopy);
    }
  }

  Future<String?> _askPhone(String countryCode) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PhoneDialog(
        initial: _invoice.customerPhone ?? '',
        countryCode: countryCode,
      ),
    );
  }

  /// Both WhatsApp and WhatsApp Business are installed: let the user pick.
  Future<String?> _askPackage(List<String> packages) {
    final l10n = AppLocalizations.of(context);
    return showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l10n.whatsAppChooseTitle),
        children: [
          for (final package in packages)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(package),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(package == whatsAppBusinessPackage
                    ? l10n.whatsAppBusiness
                    : l10n.whatsAppRegular),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showMore(List<InvoiceAction> actions) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<InvoiceAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final action in actions)
              ListTile(
                key: ValueKey('invoice-more-${action.name}'),
                leading: Icon(_icon(action)),
                title: Text(_label(l10n, action)),
                onTap: () => Navigator.of(context).pop(action),
              ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) await _run(picked);
  }

  Widget _spinnerOr(InvoiceAction action) => _running == action
      ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(_icon(action));

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(invoiceSettingsProvider).value;
    final mode = settings?.outputMode ?? OutputMode.print;
    final busy = _running != null;

    final primary = [
      if (mode.prints) InvoiceAction.print,
      if (mode.shares) InvoiceAction.shareImage,
    ];
    final hasPhone = _customerPhone(settings) != null;
    final more = [
      for (final action in InvoiceAction.values)
        if (!primary.contains(action) &&
            !(action == InvoiceAction.whatsApp && hasPhone))
          action,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            for (final (index, action) in primary.indexed) ...[
              if (index > 0) const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  key: ValueKey('invoice-primary-${action.name}'),
                  onPressed: busy ? null : () => _run(action),
                  icon: _spinnerOr(action),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(_label(l10n, action, primary: true)),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (hasPhone) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('invoice-whatsapp'),
            onPressed: busy ? null : () => _run(InvoiceAction.whatsApp),
            icon: _spinnerOr(InvoiceAction.whatsApp),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(l10n.sendOnWhatsApp),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('invoice-more'),
          onPressed: busy ? null : () => _showMore(more),
          icon: busy && !primary.contains(_running) &&
                  _running != InvoiceAction.whatsApp
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.more_horiz),
          label: Text(l10n.moreActions),
        ),
      ],
    );
  }
}

/// Asks for a WhatsApp number when the invoice has no customer phone.
/// Returns the number in international form.
class _PhoneDialog extends StatefulWidget {
  const _PhoneDialog({required this.initial, required this.countryCode});

  final String initial;
  final String countryCode;

  @override
  State<_PhoneDialog> createState() => _PhoneDialogState();
}

class _PhoneDialogState extends State<_PhoneDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final phone = toInternationalPhone(
      _controller.text,
      defaultCountryCode: widget.countryCode,
    );
    if (phone == null) {
      setState(() => _error = AppLocalizations.of(context).invalidPhone);
      return;
    }
    Navigator.of(context).pop(phone);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.whatsAppPhoneTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.phone,
        textDirection: TextDirection.ltr,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: l10n.whatsAppPhoneHint,
          errorText: _error,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.send)),
      ],
    );
  }
}
