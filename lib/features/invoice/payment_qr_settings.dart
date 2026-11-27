import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/logging/error_log.dart';
import '../../core/printing/qr_bitmap.dart';
import '../../domain/models/invoice_extras.dart';
import '../../domain/models/invoice_settings.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import '../security/audit_providers.dart';
import '../security/pin_dialogs.dart';
import 'invoice_providers.dart';
import 'payment_qr.dart';
import 'payment_qr_reader.dart';
import 'settings_parts.dart';

/// What the audit log keeps of a payment QR: its text, shortened (it is
/// printed on every paper — not a secret, but the log must show what it
/// was changed from and to), or that it is a picture.
Map<String, Object?> paymentQrAuditDetails(InvoiceSettings s) =>
    s.paymentQrText.isNotEmpty
        ? {'qr': shortenQrText(s.paymentQrText, max: 60)}
        : s.paymentQrPicture != null
            ? const {'qr_image': 1}
            : const {};

/// Invoice settings → "Payment QR" ("رمز الدفع").
///
/// The code is where the shop's customers send money, so everything that
/// changes WHAT they are shown — switching it on or off, choosing,
/// replacing or removing the code, the lines above and under it — asks for
/// the PIN when one is set and is written to the audit log in the same
/// transaction as the setting. Where it appears (every invoice or only
/// unpaid ones, receipts, statements) is an ordinary setting.
class PaymentQrSettingsSection extends ConsumerStatefulWidget {
  const PaymentQrSettingsSection({super.key});

  @override
  ConsumerState<PaymentQrSettingsSection> createState() =>
      _PaymentQrSettingsSectionState();
}

class _PaymentQrSettingsSectionState
    extends ConsumerState<PaymentQrSettingsSection> {
  bool _busy = false;

  InvoiceSettings get _settings =>
      ref.read(invoiceSettingsProvider).requireValue;

  Future<bool> _pin() => requirePinIfSet(
        context,
        reason: AppLocalizations.of(context).pinReasonPaymentQr,
      );

  /// Writes an audited change. Everything it needs is taken before the
  /// first await of the flow, so a change the owner confirmed is saved even
  /// if the screen was closed meanwhile.
  Future<void> _save(
    _Flow flow,
    InvoiceSettings Function(InvoiceSettings s) update,
    AuditAction action,
    Map<String, Object?> details,
  ) async {
    try {
      await flow.container
          .read(invoiceSettingsProvider.notifier)
          .changeAudited(update, action: action, details: details);
      flow.container.invalidate(auditLogProvider);
    } on Object catch (error, stack) {
      reportError(error, stack, context: 'payment QR');
      flow.messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(flow.l10n.saveFailedGeneric)));
    }
  }

  _Flow _flow() => _Flow(
        container: ProviderScope.containerOf(context, listen: false),
        messenger: ScaffoldMessenger.maybeOf(context),
        l10n: AppLocalizations.of(context),
      );

  void _say(_Flow flow, String text) => flow.messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _toggle(bool on) async {
    final flow = _flow();
    if (!await _pin() || !mounted) return;
    final current = _settings;
    if (on && !current.hasPaymentQrContent) {
      await _pickAndSave(flow);
      return;
    }
    await _save(
      flow,
      (s) => s.copyWith(paymentQrEnabled: on),
      on ? AuditAction.paymentQrOn : AuditAction.paymentQrOff,
      paymentQrAuditDetails(current),
    );
  }

  Future<void> _replace() async {
    final flow = _flow();
    if (!await _pin() || !mounted) return;
    await _pickAndSave(flow);
  }

  Future<void> _remove() async {
    final flow = _flow();
    if (!await _pin() || !mounted) return;
    final before = paymentQrAuditDetails(_settings);
    await _save(
      flow,
      (s) => s.copyWith(
        paymentQrEnabled: false,
        paymentQrText: '',
        paymentQrPicture: () => null,
      ),
      AuditAction.paymentQrRemove,
      before,
    );
  }

  Future<void> _editText({required bool caption}) async {
    final flow = _flow();
    if (!await _pin() || !mounted) return;
    final s = _settings;
    final l10n = flow.l10n;
    final current = caption
        ? (s.paymentQrCaption ??
            lookupAppLocalizations(Locale(s.language)).paymentQrDefaultCaption)
        : s.paymentQrNote;
    final text = await showDialog<String>(
      context: context,
      builder: (_) => PaymentQrTextDialog(
        title: caption ? l10n.paymentQrCaptionLabel : l10n.paymentQrNoteLabel,
        initial: current,
        hint: caption ? null : l10n.paymentQrNoteHint,
      ),
    );
    if (text == null || text == current) return;
    await _save(
      flow,
      (s) => caption
          ? s.copyWith(paymentQrCaption: text)
          : s.copyWith(paymentQrNote: text),
      AuditAction.paymentQrText,
      {'field': caption ? 'caption' : 'note', 'text': text},
    );
  }

  /// Picture → code. The picture is read for a QR code first; a code that
  /// reads is shown redrawn, with what it says, for the owner to confirm. A
  /// picture with no readable code is offered "as is" (black and white,
  /// with a warning), or another try.
  Future<void> _pickAndSave(_Flow flow) async {
    final source = await showModalBottomSheet<QrImageSource>(
      context: context,
      builder: (_) => const QrSourceSheet(),
    );
    if (source == null || !mounted) return;
    setState(() => _busy = true);
    PickedQrImage? picked;
    String? text;
    QrBitmap? bitmap;
    var notAnImage = false;
    try {
      picked = await flow.container.read(qrImagePickerProvider)(source);
      if (picked != null) {
        try {
          text = await flow.container.read(qrImageDecoderProvider)(picked.path);
        } on Object {
          text = null;
        }
        if (text == null) {
          try {
            bitmap = await qrBitmapFromPicture(picked.bytes);
          } on FormatException {
            notAnImage = true;
          }
        }
      }
    } on Object catch (error, stack) {
      reportError(error, stack, context: 'payment QR picture');
      if (mounted) setState(() => _busy = false);
      _say(flow, flow.l10n.paymentQrPickError);
      return;
    } finally {
      // The file picker's copy in the app's cache: nothing keeps it.
      if (source == QrImageSource.file && picked != null) {
        try {
          await File(picked.path).delete();
        } on FileSystemException {
          // Already gone.
        }
      }
    }
    if (mounted) setState(() => _busy = false);
    if (picked == null || !mounted) return;
    if (notAnImage) {
      _say(flow, flow.l10n.paymentQrNotAnImage);
      return;
    }

    final read = text;
    if (read != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => PaymentQrConfirmDialog(text: read, settings: _settings),
      );
      if (ok != true) return;
      await _save(
        flow,
        (s) => s.copyWith(
          paymentQrEnabled: true,
          paymentQrText: read,
          paymentQrPicture: () => null,
        ),
        AuditAction.paymentQrSet,
        {'qr': shortenQrText(read, max: 60)},
      );
      return;
    }

    final picture = bitmap == null ? null : QrPicture.fromBitmap(bitmap);
    final choice = await showDialog<UnreadQrChoice>(
      context: context,
      builder: (_) => PaymentQrUnreadDialog(picture: picture),
    );
    if (!mounted) return;
    if (choice == UnreadQrChoice.another) return _pickAndSave(flow);
    if (choice != UnreadQrChoice.useImage || picture == null) return;
    await _save(
      flow,
      (s) => s.copyWith(
        paymentQrEnabled: true,
        paymentQrText: '',
        paymentQrPicture: () => picture,
      ),
      AuditAction.paymentQrSet,
      const {'qr_image': 1},
    );
  }

  void _change(InvoiceSettings Function(InvoiceSettings s) update) =>
      ref.read(invoiceSettingsProvider.notifier).change(update);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final s = ref.watch(invoiceSettingsProvider).requireValue;
    final debt = featureOn(Feature.debt);
    final caption = (s.paymentQrCaption ??
            lookupAppLocalizations(Locale(s.language)).paymentQrDefaultCaption)
        .trim();
    final note = s.paymentQrNote.trim();
    final on = s.paymentQrEnabled && s.hasPaymentQrContent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSectionTitle(l10n.paymentQrSection),
        SwitchListTile(
          key: const ValueKey('payment-qr-switch'),
          title: Text(l10n.paymentQrSwitch),
          subtitle: Text(l10n.paymentQrSwitchHint),
          value: on,
          onChanged: _busy ? null : _toggle,
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: LinearProgressIndicator(
              key: ValueKey('payment-qr-busy'),
            ),
          ),
        if (on) ...[
          _PaymentQrSummary(settings: s),
          SettingsPadded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('payment-qr-replace'),
                  onPressed: _busy ? null : _replace,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.paymentQrReplace),
                ),
                TextButton.icon(
                  key: const ValueKey('payment-qr-remove'),
                  onPressed: _busy ? null : _remove,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.paymentQrRemove),
                ),
              ],
            ),
          ),
          ListTile(
            key: const ValueKey('payment-qr-caption'),
            title: Text(l10n.paymentQrCaptionLabel),
            subtitle: Text(caption.isEmpty ? l10n.paymentQrTextNone : caption),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _busy ? null : () => _editText(caption: true),
          ),
          ListTile(
            key: const ValueKey('payment-qr-note'),
            title: Text(l10n.paymentQrNoteLabel),
            subtitle: Text(note.isEmpty ? l10n.paymentQrNoteHint : note),
            trailing: const Icon(Icons.edit_outlined),
            onTap: _busy ? null : () => _editText(caption: false),
          ),
          // "Only when something is left to pay", receipts and statements
          // exist only with the debt ledger.
          if (debt) ...[
            SettingsPadded(child: Text(l10n.paymentQrWhenLabel)),
            RadioGroup<PaymentQrWhen>(
              groupValue: s.paymentQrWhen,
              onChanged: (value) {
                if (value != null) {
                  _change((s) => s.copyWith(paymentQrWhen: value));
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioListTile<PaymentQrWhen>(
                    key: const ValueKey('payment-qr-when-always'),
                    value: PaymentQrWhen.always,
                    title: Text(l10n.paymentQrWhenAlways),
                  ),
                  RadioListTile<PaymentQrWhen>(
                    key: const ValueKey('payment-qr-when-unpaid'),
                    value: PaymentQrWhen.unpaidOnly,
                    title: Text(l10n.paymentQrWhenUnpaid),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              key: const ValueKey('payment-qr-receipts'),
              title: Text(l10n.paymentQrOnReceipts),
              value: s.paymentQrOnReceipts,
              onChanged: (value) =>
                  _change((s) => s.copyWith(paymentQrOnReceipts: value)),
            ),
            SwitchListTile(
              key: const ValueKey('payment-qr-statements'),
              title: Text(l10n.paymentQrOnStatements),
              value: s.paymentQrOnStatements,
              onChanged: (value) =>
                  _change((s) => s.copyWith(paymentQrOnStatements: value)),
            ),
          ],
        ],
      ],
    );
  }
}

class _Flow {
  const _Flow({
    required this.container,
    required this.messenger,
    required this.l10n,
  });

  final ProviderContainer container;
  final ScaffoldMessengerState? messenger;
  final AppLocalizations l10n;
}

/// The stored code: a small picture of it, what kind it is, what it says.
class _PaymentQrSummary extends StatelessWidget {
  const _PaymentQrSummary({required this.settings});

  final InvoiceSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = settings;
    final fromText = s.paymentQrText.isNotEmpty;
    final dots = paymentQrModuleDotsFor(s);
    final tooDense = dots != null && dots < paymentQrMinReadableModuleDots;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PaymentQrThumbnail(settings: s, size: 88),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fromText ? l10n.paymentQrFromText : l10n.paymentQrFromImage,
                  key: const ValueKey('payment-qr-kind'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: fromText ? null : theme.colorScheme.error,
                  ),
                ),
                if (fromText)
                  Text(
                    shortenQrText(s.paymentQrText),
                    key: const ValueKey('payment-qr-content'),
                    textDirection: TextDirection.ltr,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                if (tooDense)
                  Text(
                    l10n.paymentQrTooDense,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The code as it will print, small, on white.
class PaymentQrThumbnail extends StatelessWidget {
  const PaymentQrThumbnail({
    super.key,
    required this.settings,
    this.text,
    this.picture,
    this.size = 88,
  });

  final InvoiceSettings settings;

  /// What to show instead of the stored code (the confirm dialogs).
  final String? text;
  final QrPicture? picture;
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shownText = text ?? (picture == null ? settings.paymentQrText : '');
    final shownPicture = text != null ? null : picture ?? settings.paymentQrPicture;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(2),
      child: Center(
        child: PaymentQrSymbol(
          text: shownText,
          picture: shownPicture,
          // As big as the box allows: the quiet zone is kept inside it.
          targetDots: size.floor(),
        ),
      ),
    );
  }
}

/// Where the picture of the code comes from.
class QrSourceSheet extends StatelessWidget {
  const QrSourceSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        key: const ValueKey('payment-qr-source-sheet'),
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              l10n.paymentQrSourceTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const ValueKey('payment-qr-source-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l10n.paymentQrSourceGallery),
            onTap: () => Navigator.of(context).pop(QrImageSource.gallery),
          ),
          ListTile(
            key: const ValueKey('payment-qr-source-file'),
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(l10n.paymentQrSourceFile),
            onTap: () => Navigator.of(context).pop(QrImageSource.file),
          ),
          ListTile(
            key: const ValueKey('payment-qr-source-camera'),
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text(l10n.paymentQrSourceCamera),
            onTap: () => Navigator.of(context).pop(QrImageSource.camera),
          ),
        ],
      ),
    );
  }
}

/// "Use this payment code?": the code as it will be printed — redrawn from
/// what was read — and what it says, shortened.
class PaymentQrConfirmDialog extends StatelessWidget {
  const PaymentQrConfirmDialog({
    super.key,
    required this.text,
    required this.settings,
  });

  final String text;
  final InvoiceSettings settings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final preview = settings.copyWith(
      paymentQrText: text,
      paymentQrPicture: () => null,
    );
    final dots = paymentQrModuleDotsFor(preview);
    return AlertDialog(
      key: const ValueKey('payment-qr-confirm'),
      scrollable: true,
      title: Text(l10n.paymentQrConfirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: PaymentQrThumbnail(settings: settings, text: text, size: 168),
          ),
          const SizedBox(height: 12),
          Text(l10n.paymentQrConfirmHint),
          const SizedBox(height: 4),
          Text(
            shortenQrText(text, max: 120),
            key: const ValueKey('payment-qr-confirm-text'),
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (dots != null && dots < paymentQrMinReadableModuleDots) ...[
            const SizedBox(height: 8),
            Text(
              l10n.paymentQrTooDense,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('payment-qr-confirm-cancel'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('payment-qr-confirm-use'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.paymentQrUse),
        ),
      ],
    );
  }
}

/// What the owner does with a picture whose code could not be read.
enum UnreadQrChoice { useImage, another }

/// "No QR code could be read": try another picture, or — when there is a
/// picture worth keeping — use it as it is, in black and white, with the
/// warning that it may not scan.
class PaymentQrUnreadDialog extends StatelessWidget {
  const PaymentQrUnreadDialog({super.key, required this.picture});

  /// The picture made black and white; null when it had nothing in it.
  final QrPicture? picture;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final picture = this.picture;
    return AlertDialog(
      key: const ValueKey('payment-qr-unread'),
      scrollable: true,
      title: Text(l10n.paymentQrNotReadTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.paymentQrNotReadBody),
          if (picture != null) ...[
            const SizedBox(height: 12),
            Center(
              child: PaymentQrThumbnail(
                settings: const InvoiceSettings(),
                picture: picture,
                size: 168,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.paymentQrUseImageWarning,
              key: const ValueKey('payment-qr-unread-warning'),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('payment-qr-unread-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('payment-qr-unread-another'),
          onPressed: () => Navigator.of(context).pop(UnreadQrChoice.another),
          child: Text(l10n.paymentQrChooseAnother),
        ),
        if (picture != null)
          FilledButton(
            key: const ValueKey('payment-qr-unread-use'),
            onPressed: () => Navigator.of(context).pop(UnreadQrChoice.useImage),
            child: Text(l10n.paymentQrUseImage),
          ),
      ],
    );
  }
}

/// One line of text above or under the code. Owns its controller; returns
/// the text (trimmed, possibly empty = no line) through `Navigator.pop`.
class PaymentQrTextDialog extends StatefulWidget {
  const PaymentQrTextDialog({
    super.key,
    required this.title,
    required this.initial,
    this.hint,
  });

  final String title;
  final String initial;
  final String? hint;

  static const int maxLength = 60;

  @override
  State<PaymentQrTextDialog> createState() => _PaymentQrTextDialogState();
}

class _PaymentQrTextDialogState extends State<PaymentQrTextDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      key: const ValueKey('payment-qr-text-dialog'),
      scrollable: true,
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('payment-qr-text-field'),
        controller: _controller,
        autofocus: true,
        maxLength: PaymentQrTextDialog.maxLength,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: const ValueKey('payment-qr-text-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const ValueKey('payment-qr-text-save'),
          onPressed: _save,
          child: Text(l10n.save),
        ),
      ],
    );
  }
}
