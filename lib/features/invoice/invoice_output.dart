import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/printing/escpos.dart';
import '../../core/printing/pdf_builder.dart';
import '../../core/printing/png_encoder.dart';
import '../../core/printing/raster.dart';
import '../../core/printing/widget_capture.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_providers.dart';
import 'invoice_view.dart';

/// The shared image is rendered at twice its layout width so it stays sharp
/// when a chat app zooms it.
const double sharePixelRatio = 2;

const _pngMime = 'image/png';
const _pdfMime = 'application/pdf';

/// Where share/save files are staged before they leave the app. Inside the
/// app's cache, under the folder exposed by the FileProvider
/// (android/app/src/main/res/xml/souqi_file_paths.xml).
final outputDirectoryProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final cache = await getTemporaryDirectory();
    return Directory(p.join(cache.path, 'share')).create(recursive: true);
  },
);

/// Turns an [Invoice] into paper, a picture or a PDF.
///
/// One pipeline for every output: [InvoiceView] is rendered off-screen, and
/// the same pixels become ESC/POS raster bytes, a PNG or a one-page PDF.
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

  // ---- Rendering -------------------------------------------------------

  Future<RgbaImage> renderForPrinter(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      InvoiceView(
        invoice: invoice,
        settings: c.settings,
        currencies: c.currencies,
        logo: c.logo,
        isCopy: copy,
      ),
      logicalWidth: c.settings.printableDots,
    );
  }

  Future<RgbaImage> renderForShare(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    return captureWidget(
      InvoiceView(
        invoice: invoice,
        settings: c.settings,
        currencies: c.currencies,
        logo: c.logo,
        isCopy: copy,
        // A shared image has no physical paper margin around it.
        padding: EdgeInsets.all(c.settings.baseFontSize.toDouble()),
      ),
      logicalWidth: c.settings.shareDots,
      pixelRatio: sharePixelRatio,
    );
  }

  /// The complete ESC/POS byte stream for [invoice].
  Future<Uint8List> printJob(
    Invoice invoice, {
    InvoiceRenderContext? context,
    bool copy = false,
  }) async {
    final c = context ?? await _context();
    final image = await renderForPrinter(invoice, context: c, copy: copy);
    return buildRasterJob(
      toMonochrome(image),
      feedLines: c.settings.feedLines,
      cut: c.settings.cutPaper,
    );
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
    final c = await _context();
    final address = c.settings.printerAddress;
    if (address == null || address.isEmpty) {
      throw const OutputException(OutputFailure.noPrinterSelected);
    }
    await ensureBluetoothReady();
    final job = await printJob(invoice, context: c, copy: copy);
    await _bridge.printBytes(address, job);
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
    final c = await _context();
    final file = await _pngFile(invoice, c, copy: copy);
    await _bridge.shareFile(
      filePath: file.path,
      mimeType: _pngMime,
      text: _caption(invoice, c.settings),
    );
  }

  Future<void> sharePdfFile(Invoice invoice, {bool copy = false}) async {
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
    final c = await _context();
    final file = await _pngFile(invoice, c, copy: copy);
    return _bridge.saveToDownloads(
      filePath: file.path,
      fileName: _fileName(invoice, 'png', copy: copy),
      mimeType: _pngMime,
    );
  }

  Future<String> savePdf(Invoice invoice, {bool copy = false}) async {
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
