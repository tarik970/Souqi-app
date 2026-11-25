import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../../core/platform/native_bridge.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/printing/png_encoder.dart';
import '../../core/printing/print_geometry.dart';
import '../../core/printing/print_job.dart';
import '../../core/printing/raster.dart';
import '../../core/printing/widget_capture.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/contact_actions.dart';
import '../invoice/invoice_output.dart';
import '../invoice/invoice_providers.dart';
import '../invoice/output_messages.dart';

/// A paper of the debt ledger — a payment receipt or an account statement —
/// described just enough to go through the output pipeline of the invoices.
class LedgerPaper {
  const LedgerPaper({
    required this.fileName,
    required this.caption,
    required this.build,
    this.customerPhone,
  });

  /// Without extension: "receipt-37", "statement-12-20261125".
  final String fileName;

  /// The short line that travels with a shared file, in the invoice
  /// language.
  final String Function(AppLocalizations l10n) caption;

  /// The paper itself. [padding] is null for the printer (the paper margin
  /// is physical) and set for a shared image.
  final Widget Function(
    InvoiceRenderContext context, {
    EdgeInsets? padding,
    required bool copy,
  }) build;

  /// The customer's phone, as typed: adds "Send on WhatsApp".
  final String? customerPhone;
}

/// Turns a [LedgerPaper] into paper, a picture or a PDF — the SAME pipeline
/// as the invoices ([InvoiceOutput]): the widget is rendered off-screen and
/// the pixels become printer bytes at the printer's width, or a PNG /
/// a one-page PDF at the share width, 2×.
///
/// Every method throws [OutputException] for failures the user can act on.
class LedgerPaperOutput {
  LedgerPaperOutput(this._ref);

  final Ref _ref;

  static const _pngMime = 'image/png';
  static const _pdfMime = 'application/pdf';

  NativeBridge get _bridge => _ref.read(nativeBridgeProvider);

  Future<InvoiceRenderContext> _context() =>
      _ref.read(invoiceRenderContextProvider.future);

  String _caption(LedgerPaper paper, InvoiceSettings settings) {
    final l10n = lookupAppLocalizations(Locale(settings.language));
    final text = paper.caption(l10n);
    final shop = settings.shopName.trim();
    return shop.isEmpty ? text : '$shop — $text';
  }

  Future<RgbaImage> renderForPrinter(
    LedgerPaper paper, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      paper.build(c, copy: copy),
      logicalWidth: c.settings.printableDots,
    );
  }

  Future<RgbaImage> renderForShare(
    LedgerPaper paper, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      paper.build(
        c,
        copy: copy,
        // A shared image has no physical paper margin around it.
        padding: EdgeInsets.all(c.settings.baseFontSize.toDouble()),
      ),
      logicalWidth: c.settings.shareDots,
      pixelRatio: sharePixelRatio,
    );
  }

  /// The complete byte stream, in the printer's language. A long statement
  /// is one long strip: ESC/POS sends it in bands and the roll simply keeps
  /// feeding; TSPL sends it as pages that join on continuous paper.
  Future<Uint8List> printJob(
    LedgerPaper paper, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    final image = await renderForPrinter(paper, context: c, copy: copy);
    return buildPrintJob(
      toMonochrome(image),
      format: c.settings.printFormat,
      feedLines: c.settings.feedLines,
    );
  }

  Future<Uint8List> sharePng(
    LedgerPaper paper, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final image = await renderForShare(paper, context: context, copy: copy);
    return encodePngRgb(
      width: image.width,
      height: image.height,
      rgb: flattenToRgb(image),
    );
  }

  Future<Uint8List> sharePdf(
    LedgerPaper paper, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    final image = await renderForShare(paper, context: c, copy: copy);
    return buildImagePdf(
      image,
      pageWidthMm: c.settings.sharePageWidthMm,
      title: _caption(paper, c.settings),
    );
  }

  Future<void> print(LedgerPaper paper, {bool copy = false}) async {
    final c = await _context();
    final address = c.settings.printerAddress;
    if (address == null || address.isEmpty) {
      throw const OutputException(OutputFailure.noPrinterSelected);
    }
    final output = _ref.read(invoiceOutputProvider);
    await output.ensureBluetoothReady();
    await output.send(
      c.settings,
      address,
      await printJob(paper, context: c, copy: copy),
    );
  }

  String _name(LedgerPaper paper, String extension, bool copy) =>
      copy ? '${paper.fileName}-copy.$extension' : '${paper.fileName}.$extension';

  Future<File> _stage(String name, Uint8List bytes) async {
    final directory = await _ref.read(outputDirectoryProvider)();
    return File(p.join(directory.path, name)).writeAsBytes(bytes, flush: true);
  }

  Future<File> _pngFile(
    LedgerPaper paper,
    InvoiceRenderContext c,
    bool copy,
  ) async =>
      _stage(
        _name(paper, 'png', copy),
        await sharePng(paper, context: c, copy: copy),
      );

  Future<File> _pdfFile(
    LedgerPaper paper,
    InvoiceRenderContext c,
    bool copy,
  ) async =>
      _stage(
        _name(paper, 'pdf', copy),
        await sharePdf(paper, context: c, copy: copy),
      );

  Future<void> shareImage(LedgerPaper paper, {bool copy = false}) async {
    final c = await _context();
    final file = await _pngFile(paper, c, copy);
    await _bridge.shareFile(
      filePath: file.path,
      mimeType: _pngMime,
      text: _caption(paper, c.settings),
    );
  }

  Future<void> sharePdfFile(LedgerPaper paper, {bool copy = false}) async {
    final c = await _context();
    final file = await _pdfFile(paper, c, copy);
    await _bridge.shareFile(
      filePath: file.path,
      mimeType: _pdfMime,
      text: _caption(paper, c.settings),
    );
  }

  /// Opens [package] on the customer's chat with the image attached. Returns
  /// false when the device cannot open the chat directly; the caller then
  /// falls back to [shareImage].
  Future<bool> sendToWhatsApp(
    LedgerPaper paper, {
    required String package,
    required String internationalPhone,
    bool copy = false,
  }) async {
    final c = await _context();
    final file = await _pngFile(paper, c, copy);
    try {
      return await _bridge.sendToWhatsApp(
        package: package,
        internationalPhone: internationalPhone,
        filePath: file.path,
        mimeType: _pngMime,
        text: _caption(paper, c.settings),
      );
    } on OutputException {
      return false;
    }
  }

  Future<String> saveImage(LedgerPaper paper, {bool copy = false}) async {
    final c = await _context();
    final file = await _pngFile(paper, c, copy);
    return _bridge.saveToDownloads(
      filePath: file.path,
      fileName: _name(paper, 'png', copy),
      mimeType: _pngMime,
    );
  }

  Future<String> savePdf(LedgerPaper paper, {bool copy = false}) async {
    final c = await _context();
    final file = await _pdfFile(paper, c, copy);
    return _bridge.saveToDownloads(
      filePath: file.path,
      fileName: _name(paper, 'pdf', copy),
      mimeType: _pdfMime,
    );
  }
}

final ledgerPaperOutputProvider =
    Provider<LedgerPaperOutput>(LedgerPaperOutput.new);

enum PaperAction { print, shareImage, sharePdf, whatsApp, saveImage, savePdf }

/// Print / Share / Send on WhatsApp / Save for a [LedgerPaper], laid out
/// like the buttons under an invoice: the OUTPUT MODE setting decides the
/// big primary buttons, a customer phone adds a direct WhatsApp button, and
/// everything else is one tap away under "More".
class PaperActions extends ConsumerStatefulWidget {
  const PaperActions({super.key, required this.paper, this.copy = false});

  final LedgerPaper paper;

  /// Every output carries the "COPY / نسخة" mark (a reprint).
  final bool copy;

  @override
  ConsumerState<PaperActions> createState() => _PaperActionsState();
}

class _PaperActionsState extends ConsumerState<PaperActions> {
  PaperAction? _running;

  IconData _icon(PaperAction action) => switch (action) {
        PaperAction.print => Icons.print_outlined,
        PaperAction.shareImage => Icons.share_outlined,
        PaperAction.sharePdf => Icons.picture_as_pdf_outlined,
        PaperAction.whatsApp => Icons.chat_outlined,
        PaperAction.saveImage => Icons.download_outlined,
        PaperAction.savePdf => Icons.download_for_offline_outlined,
      };

  String _label(AppLocalizations l10n, PaperAction action,
          {bool primary = false}) =>
      switch (action) {
        PaperAction.print => l10n.printInvoice,
        PaperAction.shareImage =>
          primary ? l10n.shareInvoice : l10n.shareAsImage,
        PaperAction.sharePdf => l10n.sharePdf,
        PaperAction.whatsApp => l10n.sendOnWhatsApp,
        PaperAction.saveImage => l10n.saveImageToPhone,
        PaperAction.savePdf => l10n.savePdfToPhone,
      };

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String? _phone(InvoiceSettings? settings) {
    final raw = widget.paper.customerPhone;
    if (raw == null || raw.trim().isEmpty) return null;
    return toInternationalPhone(
      raw,
      defaultCountryCode: settings?.defaultCountryCode ?? '963',
    );
  }

  Future<void> _run(PaperAction action) async {
    if (_running != null) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _running = action);
    // Read once, before the first await; [_snack] checks `mounted` itself.
    final output = ref.read(ledgerPaperOutputProvider);
    final paper = widget.paper;
    final copy = widget.copy;
    try {
      switch (action) {
        case PaperAction.print:
          await output.print(paper, copy: copy);
          _snack(l10n.printSent);
        case PaperAction.shareImage:
          await output.shareImage(paper, copy: copy);
        case PaperAction.sharePdf:
          await output.sharePdfFile(paper, copy: copy);
        case PaperAction.whatsApp:
          await _sendOnWhatsApp(l10n, output, paper, copy);
        case PaperAction.saveImage:
          _snack(l10n.savedToPhone(await output.saveImage(paper, copy: copy)));
        case PaperAction.savePdf:
          _snack(l10n.savedToPhone(await output.savePdf(paper, copy: copy)));
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

  Future<void> _sendOnWhatsApp(
    AppLocalizations l10n,
    LedgerPaperOutput output,
    LedgerPaper paper,
    bool copy,
  ) async {
    final bridge = ref.read(nativeBridgeProvider);
    final settings = await ref.read(invoiceSettingsProvider.future);
    if (!mounted) return;
    final phone = _phone(settings);
    if (phone == null) {
      await output.shareImage(paper, copy: copy);
      return;
    }
    List<String> packages;
    try {
      packages = await bridge.whatsAppPackages();
    } on OutputException {
      packages = const [];
    }
    if (!mounted) return;
    if (packages.isEmpty) {
      _snack(l10n.whatsAppNotInstalled);
      await output.shareImage(paper, copy: copy);
      return;
    }
    final package = packages.length == 1
        ? packages.single
        : await askWhatsAppPackage(context, packages);
    if (package == null || !mounted) return;
    final opened = await output.sendToWhatsApp(
      paper,
      package: package,
      internationalPhone: phone,
      copy: copy,
    );
    if (!opened) {
      _snack(l10n.whatsAppUnsupported);
      await output.shareImage(paper, copy: copy);
    }
  }

  Future<void> _showMore(List<PaperAction> actions) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showModalBottomSheet<PaperAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final action in actions)
              ListTile(
                key: ValueKey('paper-more-${action.name}'),
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

  Widget _spinnerOr(PaperAction action) => _running == action
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
      if (mode.prints) PaperAction.print,
      if (mode.shares) PaperAction.shareImage,
    ];
    final hasPhone = _phone(settings) != null;
    final more = [
      for (final action in PaperAction.values)
        if (!primary.contains(action) && action != PaperAction.whatsApp) action,
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
                  key: ValueKey('paper-primary-${action.name}'),
                  onPressed: busy ? null : () => _run(action),
                  icon: _spinnerOr(action),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _label(l10n, action, primary: true),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (hasPhone) ...[
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const ValueKey('paper-whatsapp'),
            onPressed: busy ? null : () => _run(PaperAction.whatsApp),
            icon: _spinnerOr(PaperAction.whatsApp),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(l10n.sendOnWhatsApp, textAlign: TextAlign.center),
            ),
          ),
        ],
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('paper-more'),
          onPressed: busy ? null : () => _showMore(more),
          icon: const Icon(Icons.more_horiz),
          label: Text(l10n.moreActions),
        ),
      ],
    );
  }
}

/// A [LedgerPaper] on a strip of "paper", scaled down to fit — the same
/// proportions as the invoice preview: as wide as the printable area plus
/// the side margins, laid out at its true size in dots and only scaled
/// visually, so line breaks match the print exactly.
class LedgerPaperPreview extends StatelessWidget {
  const LedgerPaperPreview({
    super.key,
    required this.paper,
    required this.context_,
    this.copy = false,
    this.maxWidth = 380,
  });

  final LedgerPaper paper;
  final InvoiceRenderContext context_;
  final bool copy;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final settings = context_.settings;
    final dots = settings.printableDots.toDouble();
    final margin =
        mmToDots(settings.sideMarginMm, settings.printerDpi).roundToDouble();
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: dots + 2 * margin,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: paper.build(context_, copy: copy),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
