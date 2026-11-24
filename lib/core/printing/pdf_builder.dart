/// Wraps a rendered invoice image in a one-page PDF.
///
/// The PDF carries the SAME pixels as the shared PNG — Arabic shaping, the
/// logo and the layout are whatever Flutter drew — on a page as wide as the
/// paper, so printing it at 100 % from any PDF app gives a receipt-sized
/// result.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'raster.dart';

Future<Uint8List> buildImagePdf(
  RgbaImage image, {
  required double pageWidthMm,
  String? title,
}) {
  final pageWidth = pageWidthMm * PdfPageFormat.mm;
  final pageHeight = pageWidth * image.height / image.width;
  final doc = pw.Document(title: title, creator: 'Souqi');
  // Opaque RGB: an alpha channel would only add a second (mask) image.
  final pdfImage = PdfImage(
    doc.document,
    image: flattenToRgb(image),
    width: image.width,
    height: image.height,
    alpha: false,
  );
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat(pageWidth, pageHeight, marginAll: 0),
      build: (_) => pw.Image(
        pw.ImageProxy(pdfImage),
        width: pageWidth,
        height: pageHeight,
        fit: pw.BoxFit.fill,
      ),
    ),
  );
  return doc.save();
}
