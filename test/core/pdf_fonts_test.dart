import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:souqi/core/money/money_format.dart';
import 'package:souqi/core/printing/pdf_fonts.dart';
import 'package:souqi/features/debts/report/debt_report_pdf.dart';

import '../features/report_test_utils.dart';

// The marks, from their code points: written as characters they would be
// invisible here and the analyzer rightly flags them.
final lrm = String.fromCharCode(0x200E);
final rlm = String.fromCharCode(0x200F);
final lre = String.fromCharCode(0x202A);
final rle = String.fromCharCode(0x202B);
final pdf = String.fromCharCode(0x202C);
final rlo = String.fromCharCode(0x202E);
final lri = String.fromCharCode(0x2066);
final pdi = String.fromCharCode(0x2069);

/// Records what a pdf widget draws instead of writing it out.
class _Recorder extends PdfGraphics {
  _Recorder(PdfPage page) : super(page, PdfStream());

  final runs = <({String text, double x})>[];

  @override
  void drawString(
    PdfFont font,
    double size,
    String s,
    double x,
    double y, {
    double? charSpace,
    double? wordSpace,
    double? scale,
    PdfTextRenderingMode mode = PdfTextRenderingMode.fill,
    double? rise,
  }) =>
      runs.add((text: s, x: x));
}

bool _arabic(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) ||
    (rune >= 0xFB50 && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF);

/// A drawn word for comparing: an Arabic letter run becomes one «ع» (it is
/// drawn as shaped presentation forms), the marks the font skips go.
String _word(String drawn) {
  final out = StringBuffer();
  var inArabic = false;
  for (final rune in stripBidiControls(drawn).runes) {
    if (_arabic(rune)) {
      if (!inArabic) out.write('ع');
      inArabic = true;
    } else {
      out.writeCharCode(rune);
      inArabic = false;
    }
  }
  return out.toString();
}

/// One line of [text] as the pdf package lays it out: the drawn words in
/// screen order, left to right; their x; and the "Unable to find a font"
/// warnings the layout printed.
({String visual, List<double> xs, List<String> warnings}) layOut(
  String text, {
  required pw.Font font,
  bool rtl = true,
}) {
  final document = PdfDocument();
  final page = PdfPage(document);
  final recorder = _Recorder(page);
  final context = pw.Context(document: document, page: page, canvas: recorder);
  final widget = pw.Theme(
    data: pw.ThemeData.withFont(base: font, bold: font),
    child: pw.Directionality(
      textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      child: pw.Text(text),
    ),
  );
  final warnings = <String>[];
  runZoned(
    () {
      widget.layout(context, const pw.BoxConstraints(maxWidth: 400));
      widget.paint(context);
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => line.contains('Unable to find')
          ? warnings.add(line)
          : parent.print(zone, line),
    ),
  );
  final runs = recorder.runs.toList()..sort((a, b) => a.x.compareTo(b.x));
  return (
    visual: runs.map((r) => _word(r.text)).join(' '),
    xs: [for (final r in runs) r.x],
    warnings: warnings,
  );
}

/// The PDF text pass and the bidi control characters intl and pasted text
/// put into our strings (lib/core/printing/pdf_fonts.dart): no warning, no
/// box in their place, and the order they ask for — the order Flutter
/// draws the same strings in on screen.
void main() {
  late ReportFonts fonts;

  setUpAll(() async {
    await initializeDateFormatting('ar');
    fonts = await testReportFonts();
  });

  // intl's Arabic numeric date: day, RLM, '/', month, RLM, '/', year.
  String arabicDate() => DateFormat.yMd('ar').format(DateTime(2026, 11, 26));

  test('the plain font warns and scrambles an Arabic date (the old bug)', () {
    expect(arabicDate(), '26$rlm/11$rlm/2026');
    final plain = pw.Font.ttf(
      ByteData.sublistView(File(ReportFonts.regularAsset).readAsBytesSync()),
    );
    final line = layOut(arabicDate(), font: plain);
    // The capture sees the warning, so the empty lists below mean something.
    expect(line.warnings, isNotEmpty);
    expect(line.visual, '/2026 /11 26');
  });

  test('an Arabic date: no warning, day on the right', () {
    final line = layOut(arabicDate(), font: fonts.regular);
    expect(line.warnings, isEmpty);
    expect(line.visual, '2026/11/26');
  });

  test('an Arabic date and time in a sentence', () {
    final generated =
        DateFormat.yMd('ar').add_Hm().format(DateTime(2026, 11, 26, 9, 5));
    final line =
        layOut('تقرير الديون · $generated · SYP', font: fonts.regular);
    expect(line.warnings, isEmpty);
    // From the right: the title, the date, the time, the currency.
    expect(line.visual, 'SYP · 09:05 2026/11/26 · ع ع');
  });

  test('a negative Arabic amount keeps its minus before the number', () {
    final amount =
        formatMinor(-150000, decimals: 0, locale: 'ar', symbol: 'ل.س');
    expect(amount, startsWith(lrm));
    final line = layOut(amount, font: fonts.regular);
    expect(line.warnings, isEmpty);
    expect(line.visual, '-150,000 ع.ع');
  });

  test('Arabic words, amounts and counts in one line', () {
    final line = layOut('رصيد 1,500 ل.س عن 3 فواتير', font: fonts.regular);
    expect(line.warnings, isEmpty);
    expect(line.visual, 'ع 3 ع ع.ع 1,500 ع');
  });

  test('a phone number reads left to right on an Arabic page', () {
    // Alone, as in the report's phone column.
    final alone = layOut('0944 123 456', font: fonts.regular);
    expect(alone.warnings, isEmpty);
    expect(alone.visual, '0944 123 456');

    // After an Arabic label, held together by LRE…PDF.
    final labelled =
        layOut('الهاتف: ${lre}0944 123 456$pdf', font: fonts.regular);
    expect(labelled.warnings, isEmpty);
    expect(labelled.visual, '0944 123 456 :ع');

    // A name pasted with its own embedding, then the phone.
    final named = layOut('$rleأحمد$pdf$rlm 0944 123 456', font: fonts.regular);
    expect(named.warnings, isEmpty);
    expect(named.visual, '456 123 0944 ع');
  });

  test('marks pasted into left-to-right text are invisible and zero wide', () {
    final clean = layOut('Ahmad 0944 123 456', font: fonts.regular, rtl: false);
    final pasted = layOut(
      '${rle}Ahmad$pdf$rlm 0944 123 456$pdi',
      font: fonts.regular,
      rtl: false,
    );
    expect(pasted.warnings, isEmpty);
    expect(pasted.visual, clean.visual);
    expect(pasted.xs, clean.xs);
  });

  test('stripBidiControls removes the marks and nothing else', () {
    expect(
      stripBidiControls('$lrm-1$rlm/2${lre}3$rlo${lri}4$pdi أ'),
      '-1/234 أ',
    );
    expect(stripBidiControls('plain'), 'plain');
  });
}
