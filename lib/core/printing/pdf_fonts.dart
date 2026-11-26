/// Fonts for the PDFs the pdf package lays out itself (the daily debt
/// report), made safe for the invisible bidi control characters our text
/// carries.
///
/// intl writes them into Arabic output — a date is 26/11/2026 with an
/// RLM after each part, a negative amount starts with an LRM — and customer
/// names pasted from other apps often bring their own. Tajawal has no glyph
/// for any of them, so the pdf package used to cut the text at each one,
/// draw a crossed box in its place and print "Unable to find a font to draw
/// U+200F". Cutting the text also undid what the mark was there for: each
/// piece went through the bidi pass on its own and an Arabic date came out
/// as `/2026 /11 26`.
///
/// [BidiSafeTtfFont] reports the marks as supported, so the text stays in
/// one piece and reaches the pdf package's bidi pass, which honours LRM,
/// RLM and the embeddings/overrides (U+202A–U+202E) and removes them from
/// what it draws — the same order Flutter gives on screen. Whatever is left
/// (every mark in left-to-right text, which skips that pass, and the
/// isolates U+2066–U+2069 the pass does not know) is measured as zero width
/// and never written. The strings themselves are not touched, so the
/// Flutter UI keeps its marks.
///
/// Invoices, receipts and statements are not affected: their PDFs carry
/// the picture Flutter drew, not text.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// LRM, RLM, LRE, RLE, PDF, LRO, RLO, LRI, RLI, FSI and PDI.
bool isBidiControl(int rune) =>
    rune == 0x200E ||
    rune == 0x200F ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2066 && rune <= 0x2069);

/// [text] without its bidi control characters.
String stripBidiControls(String text) {
  if (!text.runes.any(isBidiControl)) return text;
  return String.fromCharCodes(text.runes.where((r) => !isBidiControl(r)));
}

/// A TrueType font for pdf widgets that takes the bidi control characters
/// in its stride — see the library comment.
class BidiSafeTtfFont extends pw.TtfFont {
  BidiSafeTtfFont(super.data, {super.protect});

  @override
  PdfFont buildFont(PdfDocument pdfDocument) =>
      _BidiSafePdfTtfFont(pdfDocument, data, protect: protect);
}

class _BidiSafePdfTtfFont extends PdfTtfFont {
  _BidiSafePdfTtfFont(super.pdfDocument, super.bytes, {super.protect});

  @override
  bool isRuneSupported(int charCode) =>
      isBidiControl(charCode) || super.isRuneSupported(charCode);

  @override
  PdfFontMetrics glyphMetrics(int charCode) => isBidiControl(charCode)
      ? PdfFontMetrics.zero
      : super.glyphMetrics(charCode);

  @override
  void putText(PdfStream stream, String text) =>
      super.putText(stream, stripBidiControls(text));
}

/// A [BidiSafeTtfFont] from the bytes of a .ttf file.
pw.Font bidiSafeTtf(ByteData data) => BidiSafeTtfFont(data);
