import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/money/money_format.dart';
import '../../../core/printing/pdf_fonts.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/debt_report.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../debt_text.dart';

/// The fonts the PDF is set in: the app's own Tajawal, which shapes Arabic
/// and carries Latin letters and digits — bundled, never downloaded. Built
/// bidi-safe, so the marks in Arabic dates and amounts order the text
/// instead of printing as boxes (see pdf_fonts.dart).
class ReportFonts {
  const ReportFonts({required this.regular, required this.bold});

  ReportFonts.fromBytes({required ByteData regular, required ByteData bold})
      : regular = bidiSafeTtf(regular),
        bold = bidiSafeTtf(bold);

  final pw.Font regular;
  final pw.Font bold;

  static const String regularAsset = 'assets/fonts/Tajawal-Regular.ttf';
  static const String boldAsset = 'assets/fonts/Tajawal-Bold.ttf';
}

/// A Table cannot run right to left by itself: an Arabic table gets its
/// columns in reverse, so the first column is on the right.
List<T> _ordered<T>(List<T> cells, bool rtl) =>
    rtl ? cells.reversed.toList() : cells;

/// The daily debt report as a PDF: A4 portrait, the shop and the date on
/// top of every page, "Page n of m" at the bottom, the summary and then
/// every debtor — as many pages as that takes.
///
/// Laid out with the pdf package's own text engine (vector text, real
/// Arabic shaping), not a captured picture: it runs in the background job,
/// where there is no screen to draw on, and a 500-debtor report stays a
/// small file.
Future<Uint8List> buildDebtReportPdf(
  DebtReportData data, {
  required ReportFonts fonts,
}) async {
  final doc = await buildDebtReportDocument(data, fonts: fonts);
  return doc.save();
}

/// The document itself, for a test that counts its pages.
Future<pw.Document> buildDebtReportDocument(
  DebtReportData data, {
  required ReportFonts fonts,
}) async {
  // The dates are written with intl's date formats, whose data for a
  // language must be loaded first. In the app the Material localizations
  // do that; the background engine has none, so it is done here — from the
  // data bundled with intl, offline.
  await initializeDateFormatting(data.language);
  return _document(data, fonts);
}

pw.Document _document(DebtReportData data, ReportFonts fonts) {
  final l10n = lookupAppLocalizations(Locale(data.language));
  final locale = data.language;
  final rtl = data.rightToLeft;
  final currency = data.currency;
  String money(int minor) => formatMinor(
        minor,
        decimals: currency.decimals,
        locale: locale,
        symbol: currency.label,
      );
  String count(int value) => formatMinor(value, decimals: 0, locale: locale);
  final dateFormat = DateFormat.yMd(locale);
  String date(DateTime? at) => at == null ? '' : dateFormat.format(at.toLocal());
  final generated =
      DateFormat.yMd(locale).add_Hm().format(data.generatedAt);

  const ink = PdfColor.fromInt(0xFF12332B);
  const rule = PdfColor.fromInt(0xFFB9C7C0);
  const shade = PdfColor.fromInt(0xFFE8EFEA);
  final small = pw.TextStyle(fontSize: 8, color: PdfColors.grey700);

  pw.Widget cell(
    String text, {
    bool bold = false,
    bool number = false,
    PdfColor? color,
  }) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: pw.Text(
          text,
          maxLines: 2,
          // Amounts line up at the end of the column in both directions.
          textAlign: number
              ? (rtl ? pw.TextAlign.left : pw.TextAlign.right)
              : null,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: color,
          ),
        ),
      );

  final s = data.summary;
  final summaryRows = <(String, String, bool)>[
    (l10n.reportTotalOutstanding, money(s.totalOutstandingBaseMinor), true),
    (l10n.reportDebtorsCount, count(s.debtorsCount), true),
    (l10n.reportOverdueCount, count(s.overdueCount), false),
    (l10n.reportCreditBalances, money(s.totalCreditBaseMinor), false),
    for (final bucket in AgingBucket.values)
      (
        '${l10n.reportAgingHeading}: ${agingBucketLabel(l10n, bucket)}',
        money(s.aging[bucket]),
        false,
      ),
    (l10n.reportCollectedToday, money(s.collectedTodayBaseMinor), false),
    (l10n.reportNewDebtToday, money(s.newDebtTodayBaseMinor), false),
  ];

  final summary = pw.Table(
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: rule, width: 0.5),
    ),
    columnWidths: {
      for (final (i, width) in _ordered([3.0, 2.0], rtl).indexed)
        i: pw.FlexColumnWidth(width),
    },
    children: [
      for (final (label, value, bold) in summaryRows)
        pw.TableRow(
          children: _ordered([
            cell(label, bold: bold),
            cell(value, bold: bold, number: true),
          ], rtl),
        ),
    ],
  );

  final headers = [
    l10n.reportColCustomer,
    l10n.reportColPhone,
    l10n.reportColBalance,
    l10n.reportColOldestUnpaid,
    l10n.lastPaymentLabel,
    l10n.reportColOverdue,
  ];
  const widths = [3.2, 2.2, 2.4, 1.7, 1.7, 1.0];
  final debtors = pw.Table(
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: rule, width: 0.5),
      bottom: pw.BorderSide(color: rule, width: 0.5),
    ),
    columnWidths: {
      for (final (i, width) in _ordered(widths, rtl).indexed)
        i: pw.FlexColumnWidth(width),
    },
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: shade),
        children: _ordered([
          for (final (i, header) in headers.indexed)
            cell(header, bold: true, number: i == 2),
        ], rtl),
      ),
      for (final d in data.debtors)
        pw.TableRow(
          children: _ordered([
            cell(d.name),
            // A phone number reads left to right in both languages.
            cell(d.phone ?? ''),
            cell(money(d.balanceBaseMinor), number: true),
            cell(date(d.oldestUnpaidAt)),
            cell(date(d.lastPaymentAt)),
            cell(
              d.overdue ? l10n.reportYes : l10n.reportNo,
              bold: d.overdue,
              color: d.overdue ? PdfColors.red800 : null,
            ),
          ], rtl),
        ),
    ],
  );

  final doc = pw.Document(
    title: '${l10n.reportTitle} ${DateFormat('yyyy-MM-dd').format(data.generatedAt)}',
    creator: 'Souqi',
    author: data.shopName.isEmpty ? null : data.shopName,
  );
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(32, 28, 32, 28),
      textDirection: rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
      // The check is a debug-build guard against runaway layouts; a shop
      // with thousands of debtors legitimately needs hundreds of pages.
      maxPages: 100000,
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.only(bottom: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: ink, width: 1)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (data.shopName.isNotEmpty)
              pw.Text(
                data.shopName,
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                ),
              ),
            pw.Text(
              '${l10n.reportTitle} · $generated · ${currency.code}',
              style: const pw.TextStyle(fontSize: 10),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.center,
        margin: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          l10n.reportPageOf(
            count(context.pageNumber),
            count(context.pagesCount),
          ),
          style: small,
        ),
      ),
      build: (context) => [
        pw.Text(
          l10n.reportSheetSummary,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 4),
        summary,
        pw.SizedBox(height: 14),
        pw.Text(
          l10n.reportSheetDebtors,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
        ),
        pw.SizedBox(height: 4),
        if (data.debtors.isEmpty)
          pw.Text(l10n.reportNoDebtors, style: const pw.TextStyle(fontSize: 10))
        else
          debtors,
      ],
    ),
  );
  return doc;
}
