/// One picture, two printer languages: the bytes of a print job in whichever
/// one the printer speaks. Pure Dart.
library;

import 'dart:typed_data';

import 'escpos.dart';
import 'raster.dart';
import 'tspl.dart';

/// The command language a printer understands.
enum PrinterLanguage {
  /// ESC/POS — receipt printers.
  escPos('ESCPOS'),

  /// TSPL — label printers, and dual printers left in label mode.
  tspl('TSPL');

  const PrinterLanguage(this.db);

  final String db;

  static PrinterLanguage fromDb(String? value) => values
      .firstWhere((l) => l.db == value, orElse: () => PrinterLanguage.escPos);
}

/// The horizontal offset of a printer's calibration: at most this far left
/// or right, in steps of [offsetStepDots] (one byte of a raster row, 1 mm
/// at 203 dpi).
const int maxOffsetDots = 64;
const int offsetStepDots = 8;

/// [dots] as a valid calibration offset: a multiple of [offsetStepDots]
/// within ±[maxOffsetDots].
int snapOffsetDots(int dots) {
  final clamped = dots.clamp(-maxOffsetDots, maxOffsetDots);
  return clamped - clamped.remainder(offsetStepDots);
}

/// Everything about the PRINTER that shapes the bytes of a job (the image
/// is already as wide as the printable width).
class PrintFormat {
  const PrintFormat({
    this.language = PrinterLanguage.escPos,
    this.imageMode = EscPosImageMode.gsV0,
    this.dpi = 203,
    this.cut = false,
    this.tsplZeroIsBlack = true,
    this.offsetDots = 0,
    this.headDots,
    this.paperWidthMm,
  });

  final PrinterLanguage language;

  /// ESC/POS only.
  final EscPosImageMode imageMode;

  /// TSPL only: label sizes are sent in millimetres.
  final int dpi;

  /// ESC/POS only. A TSPL job never cuts.
  final bool cut;

  /// TSPL only, see [buildTsplJob].
  final bool tsplZeroIsBlack;

  /// The printer's calibration: the print is moved this many dots to the
  /// right (negative = left). In TSPL it moves the BITMAP x position. An
  /// ESC/POS printer always starts at its left edge, so there it can only
  /// be white columns added on the left of the image — a negative offset
  /// does nothing.
  final int offsetDots;

  /// TSPL only: dots of the print head; the image is centred on it. Null =
  /// the image starts at dot 0.
  final int? headDots;

  /// TSPL only: the label (SIZE) is as wide as the paper. Null = as wide as
  /// the image.
  final double? paperWidthMm;

  PrintFormat copyWith({
    PrinterLanguage? language,
    EscPosImageMode? imageMode,
    bool? tsplZeroIsBlack,
  }) =>
      PrintFormat(
        language: language ?? this.language,
        imageMode: imageMode ?? this.imageMode,
        dpi: dpi,
        cut: cut,
        tsplZeroIsBlack: tsplZeroIsBlack ?? this.tsplZeroIsBlack,
        offsetDots: offsetDots,
        headDots: headDots,
        paperWidthMm: paperWidthMm,
      );
}

/// The complete byte stream that prints [image] and feeds [feedLines] lines
/// after it, in the language of [format] and placed as its calibration says.
Uint8List buildPrintJob(
  MonoImage image, {
  required PrintFormat format,
  int feedLines = 3,
}) {
  return switch (format.language) {
    PrinterLanguage.escPos => buildRasterJob(
        padLeft(image, format.offsetDots),
        feedLines: feedLines,
        cut: format.cut,
        mode: format.imageMode,
      ),
    PrinterLanguage.tspl => buildTsplJob(
        image,
        dpi: format.dpi,
        feedLines: feedLines,
        zeroIsBlack: format.tsplZeroIsBlack,
        x: tsplBitmapX(
          headDots: format.headDots ?? image.width,
          imageDots: image.width,
          offsetDots: format.offsetDots,
        ),
        labelWidthMm: format.paperWidthMm,
      ),
  };
}
