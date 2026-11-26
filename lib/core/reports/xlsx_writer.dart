/// A small, pure-Dart writer of Excel workbooks (.xlsx, Office Open XML).
///
/// Only what the reports need, written by hand rather than through a
/// package so every detail is under control: real NUMERIC cells with a
/// currency number format, real DATE cells, right-to-left sheets for
/// Arabic, frozen header rows and column widths fitted to the content.
/// Text goes in as inline strings (no shared-string table), which every
/// spreadsheet app reads.
///
/// Works offline and in a background isolate: no Flutter, no platform.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../money/money_format.dart';

/// How a cell looks. The order is the `cellXfs` order in styles.xml.
enum XlsxStyle {
  normal,

  /// Bold on a light fill: the header row of a table.
  header,
  bold,

  /// The workbook's money format ("#,##0 ل.س").
  money,
  moneyBold,

  /// A whole number with grouping ("1,234").
  integer,
  integerBold,

  /// yyyy-mm-dd hh:mm
  dateTime,

  /// yyyy-mm-dd
  date,

  /// Bigger and bold: the title line of a sheet.
  title,
}

sealed class XlsxCell {
  const XlsxCell(this.style);

  final XlsxStyle style;
}

class XlsxText extends XlsxCell {
  const XlsxText(this.text, {XlsxStyle style = XlsxStyle.normal})
      : super(style);

  final String text;
}

/// An amount held as integer minor units with [decimals] places, written as
/// the exact decimal number ("1234.50") — never through a double.
class XlsxMoney extends XlsxCell {
  const XlsxMoney(
    this.minor, {
    required this.decimals,
    bool bold = false,
  }) : super(bold ? XlsxStyle.moneyBold : XlsxStyle.money);

  final int minor;
  final int decimals;
}

class XlsxInt extends XlsxCell {
  const XlsxInt(this.value, {bool bold = false})
      : super(bold ? XlsxStyle.integerBold : XlsxStyle.integer);

  final int value;
}

/// A date (or date and time) on the local wall clock of [local]'s fields.
class XlsxDate extends XlsxCell {
  const XlsxDate(this.local, {bool withTime = false})
      : super(withTime ? XlsxStyle.dateTime : XlsxStyle.date);

  final DateTime local;
}

class XlsxSheet {
  XlsxSheet({
    required this.name,
    this.rightToLeft = false,
    this.frozenRows = 1,
    List<List<XlsxCell?>>? rows,
  }) : rows = rows ?? [];

  /// At most 31 characters, none of `[]:*?/\` (Excel's rules).
  final String name;
  final bool rightToLeft;

  /// Rows at the top that stay in place while scrolling.
  final int frozenRows;
  final List<List<XlsxCell?>> rows;

  void add(List<XlsxCell?> row) => rows.add(row);
}

class XlsxWorkbook {
  XlsxWorkbook({
    required this.sheets,
    required this.moneyDecimals,
    this.moneySymbol = '',
  });

  final List<XlsxSheet> sheets;

  /// The base currency every money cell is in: its decimal places and the
  /// symbol written after the number.
  final int moneyDecimals;
  final String moneySymbol;

  static const String mimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// The number format of the money cells, e.g. `#,##0" ل.س"`.
  String get moneyFormat {
    final decimals = moneyDecimals > 0 ? '.${'0' * moneyDecimals}' : '';
    final symbol = moneySymbol.replaceAll('"', '').trim();
    return symbol.isEmpty ? '#,##0$decimals' : '#,##0$decimals" $symbol"';
  }

  Uint8List encode() {
    _checkNames();
    final archive = Archive();
    void add(String name, String xml) =>
        archive.addFile(ArchiveFile.string(name, xml));
    add('[Content_Types].xml', _contentTypes());
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook());
    add('xl/_rels/workbook.xml.rels', _workbookRels());
    add('xl/styles.xml', _styles());
    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheet(sheets[i]));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  void _checkNames() {
    final seen = <String>{};
    for (final sheet in sheets) {
      final name = sheet.name;
      if (name.isEmpty ||
          name.length > 31 ||
          RegExp(r'[\[\]:*?/\\]').hasMatch(name) ||
          name.startsWith("'") ||
          name.endsWith("'")) {
        throw ArgumentError.value(name, 'sheet name');
      }
      if (!seen.add(name.toLowerCase())) {
        throw ArgumentError.value(name, 'sheet name', 'used twice');
      }
    }
  }

  // ---- Package parts ---------------------------------------------------

  String _contentTypes() {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>',
    );
    for (var i = 0; i < sheets.length; i++) {
      out.write(
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    out.write('</Types>');
    return out.toString();
  }

  static const String _rootRels =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>';

  String _workbook() {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<bookViews><workbookView/></bookViews><sheets>',
    );
    for (var i = 0; i < sheets.length; i++) {
      out.write(
        '<sheet name="${_attr(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
      );
    }
    out.write('</sheets></workbook>');
    return out.toString();
  }

  String _workbookRels() {
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
    );
    for (var i = 0; i < sheets.length; i++) {
      out.write(
        '<Relationship Id="rId${i + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" '
        'Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    out.write(
      '<Relationship Id="rId${sheets.length + 1}" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
      'Target="styles.xml"/></Relationships>',
    );
    return out.toString();
  }

  /// numFmt 164 = money, 165 = date-time, 166 = date; 3 is Excel's
  /// built-in "#,##0". Fonts: 0 normal, 1 bold, 2 title. Fills: 0 and 1 are
  /// required by Excel, 2 is the header fill.
  String _styles() {
    String xf(int numFmt, int font, int fill) =>
        '<xf numFmtId="$numFmt" fontId="$font" fillId="$fill" borderId="0" xfId="0"'
        '${numFmt == 0 ? '' : ' applyNumberFormat="1"'}'
        '${font == 0 ? '' : ' applyFont="1"'}'
        '${fill == 0 ? '' : ' applyFill="1"'}/>';
    final xfs = {
      XlsxStyle.normal: xf(0, 0, 0),
      XlsxStyle.header: xf(0, 1, 2),
      XlsxStyle.bold: xf(0, 1, 0),
      XlsxStyle.money: xf(164, 0, 0),
      XlsxStyle.moneyBold: xf(164, 1, 0),
      XlsxStyle.integer: xf(3, 0, 0),
      XlsxStyle.integerBold: xf(3, 1, 0),
      XlsxStyle.dateTime: xf(165, 0, 0),
      XlsxStyle.date: xf(166, 0, 0),
      XlsxStyle.title: xf(0, 2, 0),
    };
    assert(xfs.length == XlsxStyle.values.length);
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '<numFmts count="3">'
        '<numFmt numFmtId="164" formatCode="${_attr(moneyFormat)}"/>'
        '<numFmt numFmtId="165" formatCode="yyyy-mm-dd hh:mm"/>'
        '<numFmt numFmtId="166" formatCode="yyyy-mm-dd"/>'
        '</numFmts>'
        '<fonts count="3">'
        '<font><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="11"/><name val="Calibri"/></font>'
        '<font><b/><sz val="14"/><name val="Calibri"/></font>'
        '</fonts>'
        '<fills count="3">'
        '<fill><patternFill patternType="none"/></fill>'
        '<fill><patternFill patternType="gray125"/></fill>'
        '<fill><patternFill patternType="solid"><fgColor rgb="FFE8EFEA"/><bgColor indexed="64"/></patternFill></fill>'
        '</fills>'
        '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${xfs.length}">'
        '${[for (final style in XlsxStyle.values) xfs[style]].join()}'
        '</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }

  String _sheet(XlsxSheet sheet) {
    final widths = _columnWidths(sheet);
    final out = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<sheetViews><sheetView workbookViewId="0"'
      '${sheet.rightToLeft ? ' rightToLeft="1"' : ''}>',
    );
    if (sheet.frozenRows > 0 && sheet.rows.length > sheet.frozenRows) {
      final top = 'A${sheet.frozenRows + 1}';
      out.write(
        '<pane ySplit="${sheet.frozenRows}" topLeftCell="$top" '
        'activePane="bottomLeft" state="frozen"/>'
        '<selection pane="bottomLeft" activeCell="$top" sqref="$top"/>',
      );
    }
    out.write('</sheetView></sheetViews>');
    if (widths.isNotEmpty) {
      out.write('<cols>');
      for (var i = 0; i < widths.length; i++) {
        out.write(
          '<col min="${i + 1}" max="${i + 1}" '
          'width="${widths[i].toStringAsFixed(1)}" customWidth="1"/>',
        );
      }
      out.write('</cols>');
    }
    out.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      final row = sheet.rows[r];
      out.write('<row r="${r + 1}">');
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell == null) continue;
        out.write(_cell('${columnName(c)}${r + 1}', cell));
      }
      out.write('</row>');
    }
    out.write('</sheetData></worksheet>');
    return out.toString();
  }

  String _cell(String ref, XlsxCell cell) {
    final style = cell.style.index == 0 ? '' : ' s="${cell.style.index}"';
    return switch (cell) {
      XlsxText(:final text) => '<c r="$ref"$style t="inlineStr"><is>'
          '<t xml:space="preserve">${_text(text)}</t></is></c>',
      XlsxMoney(:final minor, :final decimals) =>
        '<c r="$ref"$style><v>${minorToPlainText(minor, decimals: decimals)}</v></c>',
      XlsxInt(:final value) => '<c r="$ref"$style><v>$value</v></c>',
      XlsxDate(:final local) =>
        '<c r="$ref"$style><v>${excelSerial(local)}</v></c>',
    };
  }

  /// Fitted to the longest thing in each column: characters + a margin,
  /// between 8 and 60 (Excel's width unit is about one digit).
  List<double> _columnWidths(XlsxSheet sheet) {
    final widths = <double>[];
    for (final row in sheet.rows) {
      for (var c = 0; c < row.length; c++) {
        final cell = row[c];
        if (cell == null) continue;
        while (widths.length <= c) {
          widths.add(0);
        }
        final length = _displayLength(cell);
        if (length > widths[c]) widths[c] = length;
      }
    }
    return [
      for (final w in widths) (w + 2).clamp(8, 60).toDouble(),
    ];
  }

  double _displayLength(XlsxCell cell) => switch (cell) {
        XlsxText(:final text, :final style) => text
                .split('\n')
                .fold<int>(0, (m, line) => line.length > m ? line.length : m) *
            (style == XlsxStyle.title ? 1.3 : (style == XlsxStyle.header ? 1.1 : 1)),
        XlsxMoney(:final minor, :final decimals) => formatMinor(
              minor,
              decimals: decimals,
              locale: 'en',
            ).length +
            (moneySymbol.isEmpty ? 0 : moneySymbol.length + 1) +
            1,
        XlsxInt(:final value) => '$value'.length * 1.3,
        XlsxDate(:final style) => style == XlsxStyle.dateTime ? 16 : 10,
      }
          .toDouble();
}

/// A, B, … Z, AA, AB … for a zero-based column index.
String columnName(int index) {
  var n = index + 1;
  final out = StringBuffer();
  final letters = <int>[];
  while (n > 0) {
    final rem = (n - 1) % 26;
    letters.add(0x41 + rem);
    n = (n - 1) ~/ 26;
  }
  out.writeCharCode(letters.removeLast());
  while (letters.isNotEmpty) {
    out.writeCharCode(letters.removeLast());
  }
  return out.toString();
}

/// Excel's date number: days since 1899-12-30, the time of day as the
/// fraction, from the wall-clock fields of [local].
String excelSerial(DateTime local) {
  final wall = DateTime.utc(
    local.year,
    local.month,
    local.day,
    local.hour,
    local.minute,
    local.second,
  );
  final seconds = wall.difference(DateTime.utc(1899, 12, 30)).inSeconds;
  final days = seconds ~/ 86400;
  final rest = seconds % 86400;
  if (rest == 0) return '$days';
  final fraction = (rest / 86400).toStringAsFixed(8).substring(1);
  return '$days$fraction';
}

String _text(String value) => const HtmlEscape(HtmlEscapeMode.element)
    .convert(_xmlSafe(value));

String _attr(String value) => const HtmlEscape(HtmlEscapeMode.attribute)
    .convert(_xmlSafe(value));

/// XML 1.0 forbids most control characters, even escaped: a note pasted
/// from somewhere could carry one and make the whole file unreadable.
String _xmlSafe(String value) => value.replaceAll(
      RegExp('[\u0000-\u0008\u000B\u000C\u000E-\u001F]'),
      '',
    );
