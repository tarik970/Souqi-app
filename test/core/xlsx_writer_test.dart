import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:souqi/core/reports/xlsx_writer.dart';

/// The hand-written .xlsx writer: a valid package, real numeric and date
/// cells, right-to-left sheets, frozen header rows, fitted columns.
void main() {
  Map<String, String> unzip(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    return {
      for (final file in archive.files)
        if (file.isFile) file.name: utf8.decode(file.content as List<int>),
    };
  }

  XlsxWorkbook sample({bool rtl = false}) => XlsxWorkbook(
        moneyDecimals: 0,
        moneySymbol: 'ل.س',
        sheets: [
          XlsxSheet(name: 'Debtors', rightToLeft: rtl)
            ..add([
              const XlsxText('Customer', style: XlsxStyle.header),
              const XlsxText('Phone', style: XlsxStyle.header),
              const XlsxText('Balance', style: XlsxStyle.header),
              const XlsxText('Since', style: XlsxStyle.header),
              const XlsxText('Receipt', style: XlsxStyle.header),
            ])
            ..add([
              const XlsxText('Ahmad & <Sons> "Ltd"'),
              const XlsxText('0944 123 456'),
              const XlsxMoney(3250000, decimals: 0),
              XlsxDate(DateTime(2026, 11, 26, 22, 1), withTime: true),
              const XlsxInt(37),
            ]),
          XlsxSheet(name: "Today's movements"),
        ],
      );

  test('a valid package: content types, workbook, sheets in order', () {
    final files = unzip(sample().encode());
    expect(files.keys, containsAll([
      '[Content_Types].xml',
      '_rels/.rels',
      'xl/workbook.xml',
      'xl/_rels/workbook.xml.rels',
      'xl/styles.xml',
      'xl/worksheets/sheet1.xml',
      'xl/worksheets/sheet2.xml',
    ]));
    final workbook = files['xl/workbook.xml']!;
    expect(workbook, contains('<sheet name="Debtors" sheetId="1" r:id="rId1"/>'));
    expect(workbook, contains('name="Today\'s movements" sheetId="2"'));
    // Every XML part parses as UTF-8 text starting with the declaration.
    for (final entry in files.entries) {
      expect(entry.value, startsWith('<?xml'), reason: entry.key);
    }
  });

  test('numbers are numeric cells with the money format; text is text', () {
    final sheet = unzip(sample().encode())['xl/worksheets/sheet1.xml']!;
    // Money: a plain <v> number (no t="…") with the money style.
    expect(
      sheet,
      contains('<c r="C2" s="${XlsxStyle.money.index}"><v>3250000</v></c>'),
    );
    // An integer cell.
    expect(
      sheet,
      contains('<c r="E2" s="${XlsxStyle.integer.index}"><v>37</v></c>'),
    );
    // A phone stays TEXT, leading zero and all.
    expect(sheet, contains('t="inlineStr"><is><t xml:space="preserve">0944 123 456</t>'));
    // Escaped.
    expect(sheet, contains('Ahmad &amp; &lt;Sons&gt; "Ltd"'));
    // A date-time is Excel's day number with the date-time style.
    expect(
      sheet,
      contains('<c r="D2" s="${XlsxStyle.dateTime.index}"><v>${excelSerial(DateTime(2026, 11, 26, 22, 1))}</v></c>'),
    );
    final styles = unzip(sample().encode())['xl/styles.xml']!;
    expect(styles, contains('formatCode="#,##0&quot; ل.س&quot;"'));
    expect(styles, contains('<cellXfs count="${XlsxStyle.values.length}">'));
  });

  test('money with decimals is written exactly, never through a double', () {
    final book = XlsxWorkbook(
      moneyDecimals: 2,
      moneySymbol: r'$',
      sheets: [
        XlsxSheet(name: 'A')
          ..add([const XlsxMoney(123456789012345, decimals: 2)])
          ..add([const XlsxMoney(-5, decimals: 2)]),
      ],
    );
    final files = unzip(book.encode());
    expect(files['xl/worksheets/sheet1.xml'], contains('<v>1234567890123.45</v>'));
    expect(files['xl/worksheets/sheet1.xml'], contains('<v>-0.05</v>'));
    expect(files['xl/styles.xml'], contains('formatCode="#,##0.00&quot; \$&quot;"'));
  });

  test('right-to-left sheets and a frozen header row', () {
    final rtl = unzip(sample(rtl: true).encode())['xl/worksheets/sheet1.xml']!;
    expect(rtl, contains('<sheetView workbookViewId="0" rightToLeft="1">'));
    expect(rtl, contains('<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'));
    final ltr = unzip(sample().encode())['xl/worksheets/sheet1.xml']!;
    expect(ltr, isNot(contains('rightToLeft')));
    expect(ltr, contains('state="frozen"'));
    // An empty sheet has nothing to freeze.
    final empty = unzip(sample().encode())['xl/worksheets/sheet2.xml']!;
    expect(empty, isNot(contains('<pane')));
  });

  test('columns are fitted to their longest content', () {
    final sheet = unzip(sample().encode())['xl/worksheets/sheet1.xml']!;
    final widths = {
      for (final m in RegExp(r'<col min="(\d+)" max="\d+" width="([\d.]+)"')
          .allMatches(sheet))
        int.parse(m[1]!): double.parse(m[2]!),
    };
    expect(widths.keys, [1, 2, 3, 4, 5]);
    // The long name is wider than the receipt number column.
    expect(widths[1]!, greaterThan(widths[5]!));
    for (final width in widths.values) {
      expect(width, inInclusiveRange(8, 60));
    }
  });

  test('sheet names follow Excel\'s rules', () {
    for (final bad in ['', 'a/b', 'x' * 32, "'quoted'", 'a:b', 'a[1]']) {
      expect(
        () => XlsxWorkbook(moneyDecimals: 0, sheets: [XlsxSheet(name: bad)])
            .encode(),
        throwsArgumentError,
        reason: bad,
      );
    }
    expect(
      () => XlsxWorkbook(
        moneyDecimals: 0,
        sheets: [XlsxSheet(name: 'Same'), XlsxSheet(name: 'same')],
      ).encode(),
      throwsArgumentError,
    );
  });

  test('column names and Excel day numbers', () {
    expect([for (final i in [0, 1, 25, 26, 27, 51, 52, 701, 702]) columnName(i)],
        ['A', 'B', 'Z', 'AA', 'AB', 'AZ', 'BA', 'ZZ', 'AAA']);
    expect(excelSerial(DateTime(2026, 1, 1)), '46023');
    expect(excelSerial(DateTime(2026, 11, 26)), '46352');
    expect(excelSerial(DateTime(2026, 11, 26, 12)), '46352.50000000');
  });

  test('control characters a pasted note may carry are dropped', () {
    final book = XlsxWorkbook(
      moneyDecimals: 0,
      sheets: [
        XlsxSheet(name: 'A')..add([XlsxText('a${String.fromCharCode(7)}b')]),
      ],
    );
    expect(unzip(book.encode())['xl/worksheets/sheet1.xml'], contains('>ab<'));
  });
}
