import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../config/features.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/printing/calibration_pattern.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/printing/png_encoder.dart';
import '../../core/printing/print_job.dart';
import '../../core/printing/raster.dart';
import '../../core/printing/widget_capture.dart';
import '../../core/licensing/license_status.dart';
import '../../core/providers.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_providers.dart';
import 'invoice_view.dart';
import 'printer_test_slip.dart';

/// The shared image is rendered at twice its layout width so it stays sharp
/// when a chat app zooms it.
const double sharePixelRatio = 2;

const _pngMime = 'image/png';
const _pdfMime = 'application/pdf';
const _textMime = 'text/plain';

/// Where share/save files are staged before they leave the app. Inside the
/// app's cache, under the folder exposed by the FileProvider
/// (android/app/src/main/res/xml/souqi_file_paths.xml).
final outputDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final cache = await getTemporaryDirectory();
    return Directory(p.join(cache.path, 'share')).create(recursive: true);
  },
);

/// THE LICENSE CHECK OF EVERY PAPER (phase 5b): an invoice, a receipt or a
/// statement is printed or shared only with a valid license or on the
/// trial. Asked here, where the bytes are made — not only on the buttons —
/// and the service verifies the stored activation code again each time.
/// What stays open: the printer tests, the PIN recovery slip, and looking
/// at an invoice on the screen.
Future<void> ensureLicensedOutput(Ref ref) async {
  try {
    await ref.read(licenseServiceProvider)?.ensureCanPrint();
  } on LicenseRequiredException {
    throw const OutputException(OutputFailure.licenseRequired);
  }
}

/// Turns an [Invoice] into paper, a picture or a PDF.
///
/// One pipeline for every output: [InvoiceView] is rendered off-screen, and
/// the same pixels become printer bytes (ESC/POS or TSPL, whichever the
/// printer speaks), a PNG or a one-page PDF.
/// The printer render is exactly [InvoiceSettings.printableDots] wide at one
/// pixel per dot; the share render ignores printer-only settings and uses
/// [InvoiceSettings.shareDots] at 2×.
///
/// Every method throws [OutputException] for failures the user can act on.
class InvoiceOutput {
  InvoiceOutput(this._ref);

  final Ref _ref;

  NativeBridge get _bridge => _ref.read(nativeBridgeProvider);

  Future<InvoiceRenderContext> _context() =>
      _ref.read(invoiceRenderContextProvider.future);

  // ---- Card codes ------------------------------------------------------

  /// The prepaid card codes [invoice] sold, IN THE CLEAR, for the paper and
  /// the shared file — the one place besides "show the code" where a code is
  /// decrypted. They are handed to the renderer and dropped; nothing here
  /// logs or keeps them. Empty for an invoice that sold none, for a draft
  /// (the settings preview) and when the feature is off.
  Future<List<InvoiceCode>> codesOf(Invoice invoice) async {
    final id = invoice.id;
    if (!featureOn(Feature.vouchers) || id == null) return const [];
    return _ref.read(voucherRepositoryProvider).printableCodes(id);
  }

  // ---- Rendering -------------------------------------------------------

  /// [codes] defaults to the invoice's own ([codesOf]); pass an empty list
  /// to leave them off (they are then printed as separate slips).
  Future<RgbaImage> renderForPrinter(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
    List<InvoiceCode>? codes,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      InvoiceView(
        invoice: invoice,
        settings: c.settings,
        currencies: c.currencies,
        logo: c.logo,
        isCopy: copy,
        codes: codes ?? await codesOf(invoice),
      ),
      logicalWidth: c.settings.printableDots,
    );
  }

  /// One card on a slip of its own, at the printer's width.
  Future<RgbaImage> renderSlip(
    Invoice invoice,
    InvoiceCode code, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      CodeSlipView(
        invoice: invoice,
        code: code,
        settings: c.settings,
        isCopy: copy,
      ),
      logicalWidth: c.settings.printableDots,
    );
  }

  /// The shared image always carries the codes with the invoice — the
  /// "separate slips" setting is about paper only. That is the point of
  /// sending it: the customer receives the cards.
  Future<RgbaImage> renderForShare(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
    List<InvoiceCode>? codes,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      InvoiceView(
        invoice: invoice,
        settings: c.settings,
        currencies: c.currencies,
        logo: c.logo,
        isCopy: copy,
        codes: codes ?? await codesOf(invoice),
        // A shared image has no physical paper margin around it.
        padding: EdgeInsets.all(c.settings.baseFontSize.toDouble()),
      ),
      logicalWidth: c.settings.shareDots,
      pixelRatio: sharePixelRatio,
    );
  }

  /// Lines fed between two card slips even when the invoice setting is 0:
  /// without a gap there is nowhere to tear.
  static const int minSlipFeedLines = 3;

  /// The complete byte stream for [invoice], in the printer's language.
  ///
  /// With "print each card on a separate slip" on, the invoice is printed
  /// without its codes and each sold card follows as its own job — its own
  /// feed and (when the printer has a cutter) its own cut. In TSPL each
  /// slip is a label of its own, with its own PRINT.
  Future<Uint8List> printJob(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
    List<InvoiceCode>? codes,
  }) async {
    final c = context ?? await _context();
    final sold = codes ?? await codesOf(invoice);
    final slips = c.settings.codesOnSeparateSlips && sold.isNotEmpty;
    final image = await renderForPrinter(
      invoice,
      context: c,
      copy: copy,
      codes: slips ? const [] : sold,
    );
    final format = c.settings.printFormat;
    final main = buildPrintJob(
      toMonochrome(image),
      format: format,
      feedLines: c.settings.feedLines,
    );
    if (!slips) return main;

    final job = BytesBuilder(copy: false)..add(main);
    final feed = c.settings.feedLines < minSlipFeedLines
        ? minSlipFeedLines
        : c.settings.feedLines;
    for (final code in sold) {
      final slip = await renderSlip(invoice, code, context: c, copy: copy);
      job.add(buildPrintJob(
        toMonochrome(slip),
        format: format,
        feedLines: feed,
      ));
    }
    return job.toBytes();
  }

  /// The share image as PNG bytes, `2 × shareDots` pixels wide.
  Future<Uint8List> sharePng(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final image = await renderForShare(invoice, context: context, copy: copy);
    return encodePngRgb(
      width: image.width,
      height: image.height,
      rgb: flattenToRgb(image),
    );
  }

  /// The same render on a PDF page as wide as the paper.
  Future<Uint8List> sharePdf(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    final image = await renderForShare(invoice, context: c, copy: copy);
    return buildImagePdf(
      image,
      pageWidthMm: c.settings.sharePageWidthMm,
      title: _caption(invoice, c.settings),
    );
  }

  // ---- Printing --------------------------------------------------------

  Future<void> printInvoice(Invoice invoice, {bool copy = false}) async {
    await ensureLicensedOutput(_ref);
    final c = await _context();
    final address = c.settings.printerAddress;
    if (address == null || address.isEmpty) {
      throw const OutputException(OutputFailure.noPrinterSelected);
    }
    await ensureBluetoothReady();
    final job = await printJob(invoice, context: c, copy: copy);
    await send(c.settings, address, job);
  }

  /// Writes [job] to the printer at [address], paced as the compatibility
  /// settings say (chunk size and the pause between chunks).
  Future<void> send(InvoiceSettings settings, String address, Uint8List job) =>
      _bridge.printBytes(
        address,
        job,
        chunkSize: settings.printChunkSize,
        chunkDelayMs: settings.printChunkDelayMs,
      );

  // ---- Printer diagnostics ---------------------------------------------

  /// Prints the short test slip of the diagnostics screen: the shop name,
  /// a line of Arabic and [label] (which test this is). [format] replaces
  /// the stored language and image mode, so a mode can be tried before it
  /// is chosen. Same checks and failures as [printInvoice].
  Future<void> printTest({
    required PrintFormat format,
    required String label,
  }) async {
    final c = await _context();
    final address = c.settings.printerAddress;
    if (address == null || address.isEmpty) {
      throw const OutputException(OutputFailure.noPrinterSelected);
    }
    await ensureBluetoothReady();
    final image = await captureWidget(
      PrinterTestSlipView(
        settings: c.settings,
        label: label,
        printedAt: DateTime.now(),
      ),
      logicalWidth: c.settings.printableDots,
    );
    await send(
      c.settings,
      address,
      buildPrintJob(
        toMonochrome(image),
        format: format,
        feedLines: c.settings.feedLines < minSlipFeedLines
            ? minSlipFeedLines
            : c.settings.feedLines,
      ),
    );
  }

  /// Checks Bluetooth exists, is allowed and is on. With [askPermission] the
  /// system permission dialog is shown when the permission is missing.
  Future<void> ensureBluetoothReady({bool askPermission = true}) async {
    var status = await _bridge.bluetoothStatus();
    if (!status.supported) {
      throw const OutputException(OutputFailure.bluetoothUnsupported);
    }
    if (!status.permissionGranted) {
      if (!askPermission || !await _bridge.requestBluetoothPermission()) {
        throw const OutputException(OutputFailure.bluetoothPermissionDenied);
      }
      status = await _bridge.bluetoothStatus();
    }
    if (!status.enabled) {
      throw const OutputException(OutputFailure.bluetoothOff);
    }
  }

  /// Prints the calibration ruler with [settings] — passed in, not read,
  /// because the diagnostics screen prints it in the same breath as it
  /// changes the offset or the width. The pattern is as wide as the
  /// printable width and goes through the same job builder as an invoice,
  /// so it lands on the paper exactly where an invoice would.
  Future<void> printCalibration(InvoiceSettings settings) async {
    final address = settings.printerAddress;
    if (address == null || address.isEmpty) {
      throw const OutputException(OutputFailure.noPrinterSelected);
    }
    await ensureBluetoothReady();
    await send(
      settings,
      address,
      buildPrintJob(
        buildCalibrationPattern(
          width: settings.printableDots,
          offsetDots: settings.printerOffsetDots,
        ),
        format: settings.printFormat,
        feedLines: settings.feedLines < minSlipFeedLines
            ? minSlipFeedLines
            : settings.feedLines,
      ),
    );
  }

  // ---- PIN recovery code -----------------------------------------------

  /// Prints the PIN recovery [code] on a slip of its own: large, in fours,
  /// with a line saying what it is for. Same checks and failures as
  /// [printInvoice].
  Future<void> printRecoveryCode(String code) async {
    final c = await _context();
    final address = c.settings.printerAddress;
    if (address == null || address.isEmpty) {
      throw const OutputException(OutputFailure.noPrinterSelected);
    }
    await ensureBluetoothReady();
    final image = await captureWidget(
      RecoverySlipView(
        code: code,
        settings: c.settings,
        printedAt: DateTime.now(),
      ),
      logicalWidth: c.settings.printableDots,
    );
    await send(
      c.settings,
      address,
      buildPrintJob(
        toMonochrome(image),
        format: c.settings.printFormat,
        feedLines: c.settings.feedLines < minSlipFeedLines
            ? minSlipFeedLines
            : c.settings.feedLines,
      ),
    );
  }

  /// Hands a small UTF-8 text file to the share sheet. The staged copy has
  /// to outlive the sheet; the launch housekeeping removes it within a day.
  Future<void> shareTextFile({
    required String fileName,
    required String text,
  }) async {
    final file = await _stage(fileName, Uint8List.fromList(utf8.encode(text)));
    await _bridge.shareFile(filePath: file.path, mimeType: _textMime);
  }

  /// Saves a small UTF-8 text file to Downloads/Souqi and returns the path
  /// to show the user. No copy is left behind in the app's cache.
  Future<String> saveTextFile({
    required String fileName,
    required String text,
  }) async {
    final file = await _stage(fileName, Uint8List.fromList(utf8.encode(text)));
    try {
      return await _bridge.saveToDownloads(
        filePath: file.path,
        fileName: fileName,
        mimeType: _textMime,
      );
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Swept on the next launch.
      }
    }
  }

  // ---- Sharing and saving ----------------------------------------------

  /// A reprint gets its own file name, so sharing a copy never overwrites
  /// the original that is still sitting in the cache.
  String _fileName(Invoice invoice, String extension, {bool copy = false}) =>
      copy
          ? 'invoice-${invoice.invoiceNo}-copy.$extension'
          : 'invoice-${invoice.invoiceNo}.$extension';

  /// A short line that travels with the file: shop name and invoice number,
  /// in the invoice language.
  String _caption(Invoice invoice, InvoiceSettings settings) {
    final l10n = lookupAppLocalizations(Locale(settings.language));
    final number = l10n.invoiceNoLabel('${invoice.invoiceNo}');
    final shop = settings.shopName.trim();
    return shop.isEmpty ? number : '$shop — $number';
  }

  Future<File> _stage(String name, Uint8List bytes) async {
    final directory = await _ref.read(outputDirectoryProvider)();
    return File(p.join(directory.path, name)).writeAsBytes(bytes, flush: true);
  }

  Future<File> _pngFile(
    Invoice invoice,
    InvoiceRenderContext c, {
    bool copy = false,
  }) async =>
      _stage(
        _fileName(invoice, 'png', copy: copy),
        await sharePng(invoice, context: c, copy: copy),
      );

  Future<File> _pdfFile(
    Invoice invoice,
    InvoiceRenderContext c, {
    bool copy = false,
  }) async =>
      _stage(
        _fileName(invoice, 'pdf', copy: copy),
        await sharePdf(invoice, context: c, copy: copy),
      );

  Future<void> shareImage(Invoice invoice, {bool copy = false}) async {
    await ensureLicensedOutput(_ref);
    final c = await _context();
    final file = await _pngFile(invoice, c, copy: copy);
    await _bridge.shareFile(
      filePath: file.path,
      mimeType: _pngMime,
      text: _caption(invoice, c.settings),
    );
  }

  Future<void> sharePdfFile(Invoice invoice, {bool copy = false}) async {
    await ensureLicensedOutput(_ref);
    final c = await _context();
    final file = await _pdfFile(invoice, c, copy: copy);
    await _bridge.shareFile(
      filePath: file.path,
      mimeType: _pdfMime,
      text: _caption(invoice, c.settings),
    );
  }

  /// Opens [package] on the chat of [internationalPhone] with the invoice
  /// image attached. Returns false when the device cannot open the chat
  /// directly; the caller then falls back to [shareImage].
  Future<bool> sendToWhatsApp(
    Invoice invoice, {
    required String package,
    required String internationalPhone,
    bool copy = false,
  }) async {
    await ensureLicensedOutput(_ref);
    final c = await _context();
    final file = await _pngFile(invoice, c, copy: copy);
    try {
      return await _bridge.sendToWhatsApp(
        package: package,
        internationalPhone: internationalPhone,
        filePath: file.path,
        mimeType: _pngMime,
        text: _caption(invoice, c.settings),
      );
    } on OutputException {
      return false;
    }
  }

  /// Saves the image to Downloads/Souqi; returns the path to show the user.
  Future<String> saveImage(Invoice invoice, {bool copy = false}) async {
    await ensureLicensedOutput(_ref);
    final c = await _context();
    final file = await _pngFile(invoice, c, copy: copy);
    return _bridge.saveToDownloads(
      filePath: file.path,
      fileName: _fileName(invoice, 'png', copy: copy),
      mimeType: _pngMime,
    );
  }

  Future<String> savePdf(Invoice invoice, {bool copy = false}) async {
    await ensureLicensedOutput(_ref);
    final c = await _context();
    final file = await _pdfFile(invoice, c, copy: copy);
    return _bridge.saveToDownloads(
      filePath: file.path,
      fileName: _fileName(invoice, 'pdf', copy: copy),
      mimeType: _pdfMime,
    );
  }
}

final invoiceOutputProvider = Provider<InvoiceOutput>(InvoiceOutput.new);
