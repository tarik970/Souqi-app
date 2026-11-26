/// Which language does this printer speak? — answered without asking the
/// shop, so that a printer works the first time it is chosen.
///
/// Two ways, in this order:
///
/// 1. BY NAME. A printer the app knows ([builtInProfileFor]) gets the whole
///    of its tested settings — language, width, position — and is not asked
///    anything.
/// 2. BY ASKING. Every language has a status question the printer answers
///    with one byte ([PrinterProbe]); the one it answers is the one it
///    speaks. Each question waits [PrinterProbe.timeoutMs] at most.
///
/// A printer that answers neither — many cheap ones never send a byte back
/// over Bluetooth — is taken for a receipt printer (ESC/POS), which is what
/// most of them are; the printer diagnostics screen is where that is put
/// right by hand.
///
/// Pure Dart: the Bluetooth link is a function passed in ([PrinterQuery]).
library;

import 'dart:typed_data';

import 'print_job.dart';

/// The settings a known printer prints right with, out of the box.
class PrinterProfile {
  const PrinterProfile({
    required this.id,
    required this.language,
    required this.paperWidthMm,
    required this.dpi,
    required this.printableDots,
    this.offsetDots = 0,
  });

  /// The model, as it is shown ("XP-365B").
  final String id;
  final PrinterLanguage language;
  final double paperWidthMm;
  final int dpi;

  /// The image width that prints complete on this model.
  final int printableDots;

  /// Calibration: 0 = where the language's default puts the image (for
  /// TSPL, centred on the print head).
  final int offsetDots;
}

/// Xprinter XP-365B: a dual label/receipt printer that leaves the factory in
/// LABEL mode, where ESC/POS is ignored (it beeps and prints nothing). On
/// 80 mm paper its 608-dot head prints a 512-dot image complete when the
/// image is centred; 576 dots came out cut off at the side.
const PrinterProfile xp365bProfile = PrinterProfile(
  id: 'XP-365B',
  language: PrinterLanguage.tspl,
  paperWidthMm: 80,
  dpi: 203,
  printableDots: 512,
);

/// Every printer known by name: what its Bluetooth name contains (letters
/// and digits only, upper case) and its profile.
const Map<String, PrinterProfile> _profilesByName = {
  'XP365B': xp365bProfile,
};

/// The built-in profile of the printer whose Bluetooth name is [name], or
/// null for a printer the app does not know. The name only has to CONTAIN
/// the model, in any case and with or without its dash or spaces
/// ("XP-365B", "Xprinter XP 365B", "XP-365B_4F2A").
PrinterProfile? builtInProfileFor(String? name) {
  if (name == null || name.isEmpty) return null;
  final compact = StringBuffer();
  for (final unit in name.toUpperCase().codeUnits) {
    final isDigit = unit >= 0x30 && unit <= 0x39;
    final isLetter = unit >= 0x41 && unit <= 0x5A;
    if (isDigit || isLetter) compact.writeCharCode(unit);
  }
  final key = compact.toString();
  for (final entry in _profilesByName.entries) {
    if (key.contains(entry.key)) return entry.value;
  }
  return null;
}

/// The status questions and how their answers are told apart.
abstract final class PrinterProbe {
  /// ESC/POS "transmit real-time status" (DLE EOT 1). A receipt printer
  /// answers one byte; a label printer in TSPL mode sees three characters
  /// of an unknown command line and says nothing.
  static final Uint8List escPosStatus = Uint8List.fromList([0x10, 0x04, 0x01]);

  /// TSPL "printer status" (ESC ! ?), answered at once with one byte even
  /// in the middle of a job. A receipt printer reads it as "select print
  /// mode" — which the ESC @ at the start of every ESC/POS job undoes — and
  /// says nothing.
  static final Uint8List tsplStatus = Uint8List.fromList([0x1B, 0x21, 0x3F]);

  /// How long each question waits for its answer.
  static const int timeoutMs = 400;

  /// An ESC/POS real-time status byte always has the shape 0xx1xx10.
  static bool isEscPosStatus(int byte) => (byte & 0x93) == 0x12;
}

/// How a printer's language was decided.
enum DetectionSource {
  /// The printer is known by its name.
  profile,

  /// The printer answered the status question of this language.
  answered,

  /// The printer answered nothing: ESC/POS is assumed.
  silent,
}

class PrinterDetection {
  const PrinterDetection(this.language, this.source, [this.profile]);

  final PrinterLanguage language;
  final DetectionSource source;

  /// Set when [source] is [DetectionSource.profile].
  final PrinterProfile? profile;
}

/// Sends [request] to the printer and returns what it answered within
/// [timeoutMs] milliseconds (empty = nothing).
typedef PrinterQuery = Future<Uint8List> Function(
  Uint8List request,
  int timeoutMs,
);

/// Finds the language of the printer called [name].
///
/// A printer with a built-in profile is never asked. Otherwise the ESC/POS
/// question goes first: its three bytes do nothing to a label printer (they
/// end with the empty line every TSPL job starts with), while the TSPL
/// question would change a receipt printer's text mode — so it is only sent
/// to a printer that did not answer as a receipt printer.
///
/// Whatever [query] throws (the printer is off, Bluetooth is off) is passed
/// on: no language is decided for a printer that could not be reached.
Future<PrinterDetection> detectPrinterLanguage({
  required String? name,
  required PrinterQuery query,
  int timeoutMs = PrinterProbe.timeoutMs,
}) async {
  final profile = builtInProfileFor(name);
  if (profile != null) {
    return PrinterDetection(profile.language, DetectionSource.profile, profile);
  }

  final first = await query(PrinterProbe.escPosStatus, timeoutMs);
  if (first.any(PrinterProbe.isEscPosStatus)) {
    return const PrinterDetection(
      PrinterLanguage.escPos,
      DetectionSource.answered,
    );
  }

  final second = await query(PrinterProbe.tsplStatus, timeoutMs);
  // A slow receipt printer may answer the first question only now.
  if (second.any(PrinterProbe.isEscPosStatus)) {
    return const PrinterDetection(
      PrinterLanguage.escPos,
      DetectionSource.answered,
    );
  }
  if (second.isNotEmpty) {
    return const PrinterDetection(PrinterLanguage.tspl, DetectionSource.answered);
  }
  return const PrinterDetection(PrinterLanguage.escPos, DetectionSource.silent);
}
