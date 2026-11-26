/// Turns a pasted list or a .txt / .csv file into card codes to load.
///
/// Pure text in, values out — no database, no widgets — so the rules (which
/// lines are skipped, what counts as a duplicate) are unit-tested directly.
library;

import '../utils/normalize.dart';

/// What each line holds. The user picks this once per import and checks the
/// masked preview; nothing is guessed from the data.
enum CodeColumns {
  /// The whole line is the code.
  codeOnly,

  /// `serial,code`.
  serialThenCode,

  /// `code,serial`.
  codeThenSerial,
}

/// One card to load.
class ParsedCode {
  const ParsedCode({required this.code, this.serial, required this.line});

  /// The code as written on the line (trimmed). Stored encrypted as is, so
  /// it prints the way the card shows it.
  final String code;

  /// Not a secret: the number printed on the outside of the card.
  final String? serial;

  /// 1-based line in the source, for messages.
  final int line;
}

/// What [parseCodeList] made of the text.
class CodeParseResult {
  const CodeParseResult({
    required this.codes,
    required this.emptyLines,
    required this.duplicateLines,
    required this.invalidLines,
    required this.headerSkipped,
  });

  /// The cards to load, in the order of the text, each code once.
  final List<ParsedCode> codes;

  /// Lines with nothing on them.
  final int emptyLines;

  /// Lines repeating a code that appeared earlier in the same text.
  final int duplicateLines;

  /// Lines that have text but no code in the chosen column.
  final int invalidLines;

  /// The first line was a column heading ("serial,code") and was left out.
  final bool headerSkipped;

  static const empty = CodeParseResult(
    codes: [],
    emptyLines: 0,
    duplicateLines: 0,
    invalidLines: 0,
    headerSkipped: false,
  );
}

/// Column headings a spreadsheet export starts with. Compared after
/// lowercasing; a real code never matches one of these.
const _headerWords = {
  'code',
  'codes',
  'pin',
  'pins',
  'serial',
  'serial number',
  'serial no',
  'sn',
  's/n',
  'number',
  'card',
  'الرمز',
  'رمز',
  'الكود',
  'كود',
  'التسلسلي',
  'الرقم التسلسلي',
  'رقم تسلسلي',
  'البطاقة',
};

final _lineBreak = RegExp('\r\n|\r|\n');
final _fieldSeparator = RegExp('[,;\t]');

String _unquote(String field) {
  final text = field.trim();
  if (text.length >= 2 &&
      ((text.startsWith('"') && text.endsWith('"')) ||
          (text.startsWith("'") && text.endsWith("'")))) {
    return text.substring(1, text.length - 1).trim();
  }
  return text;
}

/// Splits [text] into cards.
///
/// - Empty lines are skipped and counted.
/// - With two columns the line is cut at its FIRST `,` `;` or tab; a line
///   without a separator is a code with no serial.
/// - Two lines are the same card when their codes are equal after
///   [normalizeCode] — "1234-5678", "1234 5678" and "١٢٣٤٥٦٧٨" are one card.
///   The first one is kept, the rest are counted as duplicates.
/// - A line whose code column is empty (or holds only dashes) is invalid.
CodeParseResult parseCodeList(String text, {required CodeColumns columns}) {
  // A file saved by Windows tools often starts with a byte-order mark.
  final bom = String.fromCharCode(0xFEFF);
  final source = text.startsWith(bom) ? text.substring(1) : text;

  final codes = <ParsedCode>[];
  final seen = <String>{};
  var emptyLines = 0;
  var duplicateLines = 0;
  var invalidLines = 0;
  var headerSkipped = false;
  var firstContentLine = true;

  final lines = source.split(_lineBreak);
  // A trailing newline is the end of the last line, not an empty line.
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.isEmpty) {
      emptyLines++;
      continue;
    }

    String code;
    String? serial;
    if (columns == CodeColumns.codeOnly) {
      code = _unquote(line);
    } else {
      final cut = line.indexOf(_fieldSeparator);
      if (cut < 0) {
        code = _unquote(line);
      } else {
        final first = _unquote(line.substring(0, cut));
        // Only the NEXT field: a third column (a price, a date) or a
        // trailing separator from a spreadsheet export is not part of the
        // code — "4567890123456,100" would be stored, printed and hashed as
        // the code, and the same card could be loaded twice.
        final rest = line.substring(cut + 1);
        final end = rest.indexOf(_fieldSeparator);
        final second = _unquote(end < 0 ? rest : rest.substring(0, end));
        if (columns == CodeColumns.serialThenCode) {
          serial = first;
          code = second;
        } else {
          code = first;
          serial = second;
        }
      }
    }

    if (firstContentLine) {
      firstContentLine = false;
      final words = [code, ?serial].map((w) => w.toLowerCase());
      if (words.every(_headerWords.contains)) {
        headerSkipped = true;
        continue;
      }
    }

    final normalized = normalizeCode(code);
    if (normalized.isEmpty) {
      invalidLines++;
      continue;
    }
    if (!seen.add(normalized)) {
      duplicateLines++;
      continue;
    }
    codes.add(ParsedCode(
      code: code,
      serial: serial == null || serial.isEmpty ? null : serial,
      line: i + 1,
    ));
  }

  return CodeParseResult(
    codes: codes,
    emptyLines: emptyLines,
    duplicateLines: duplicateLines,
    invalidLines: invalidLines,
    headerSkipped: headerSkipped,
  );
}
