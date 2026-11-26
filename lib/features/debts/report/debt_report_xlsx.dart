import 'dart:typed_data';
import 'dart:ui' show Locale;

import '../../../core/reports/xlsx_writer.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/debt_report.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../debt_text.dart';

/// The four sheet names, in the report's language — what a test checks and
/// what the shop sees on the tabs.
List<String> debtReportSheetNames(String language) {
  final l10n = lookupAppLocalizations(Locale(language));
  return [
    l10n.reportSheetSummary,
    l10n.reportSheetDebtors,
    l10n.reportSheetMovements,
    l10n.reportSheetBalances,
  ];
}

/// The daily debt report as an Excel workbook:
///
/// 1. Summary — when and for which shop, the totals, the aging buckets and
///    today's collections and new debt.
/// 2. Debtors — every customer who owes, biggest first.
/// 3. Today's movements — every ledger entry dated or written today.
/// 4. All balances — every customer with an account, zero and credit
///    balances included.
///
/// Amounts are numeric cells in the base currency's format, dates are date
/// cells, phone numbers stay text (leading zeros). Arabic sheets run right
/// to left. The header row of every sheet is frozen.
Uint8List buildDebtReportXlsx(DebtReportData data) {
  final l10n = lookupAppLocalizations(Locale(data.language));
  final decimals = data.currency.decimals;
  final rtl = data.rightToLeft;
  final names = debtReportSheetNames(data.language);

  XlsxCell money(int minor, {bool bold = false}) =>
      XlsxMoney(minor, decimals: decimals, bold: bold);
  XlsxCell? date(DateTime? at) =>
      at == null ? null : XlsxDate(at.toLocal());
  XlsxCell? text(String? value) =>
      value == null || value.isEmpty ? null : XlsxText(value);
  List<XlsxCell?> header(List<String> labels) => [
        for (final label in labels) XlsxText(label, style: XlsxStyle.header),
      ];
  XlsxCell label(String value) => XlsxText(value, style: XlsxStyle.bold);

  final s = data.summary;
  final summary = XlsxSheet(name: names[0], rightToLeft: rtl)
    ..add([XlsxText(l10n.reportTitle, style: XlsxStyle.title)])
    ..add([label(l10n.reportGeneratedAt), XlsxDate(data.generatedAt, withTime: true)])
    ..add([label(l10n.reportShop), text(data.shopName)])
    ..add([label(l10n.reportCurrency), XlsxText(data.currency.code)])
    ..add(const [])
    ..add([label(l10n.reportTotalOutstanding), money(s.totalOutstandingBaseMinor, bold: true)])
    ..add([label(l10n.reportDebtorsCount), XlsxInt(s.debtorsCount, bold: true)])
    ..add([label(l10n.reportOverdueCount), XlsxInt(s.overdueCount)])
    ..add([label(l10n.reportCreditBalances), money(s.totalCreditBaseMinor)])
    ..add(const [])
    ..add([XlsxText(l10n.reportAgingHeading, style: XlsxStyle.header), XlsxText(l10n.reportColBalance, style: XlsxStyle.header)])
    ..add([XlsxText(agingBucketLabel(l10n, AgingBucket.current)), money(s.aging[AgingBucket.current])])
    ..add([XlsxText(agingBucketLabel(l10n, AgingBucket.days31to60)), money(s.aging[AgingBucket.days31to60])])
    ..add([XlsxText(agingBucketLabel(l10n, AgingBucket.days61to90)), money(s.aging[AgingBucket.days61to90])])
    ..add([XlsxText(agingBucketLabel(l10n, AgingBucket.over90)), money(s.aging[AgingBucket.over90])])
    ..add(const [])
    ..add([label(l10n.reportCollectedToday), money(s.collectedTodayBaseMinor)])
    ..add([label(l10n.reportNewDebtToday), money(s.newDebtTodayBaseMinor)]);

  final debtors = XlsxSheet(name: names[1], rightToLeft: rtl)
    ..add(header([
      l10n.reportColCustomer,
      l10n.reportColPhone,
      l10n.reportColBalance,
      l10n.creditLimitLabel,
      l10n.reportColOldestUnpaid,
      l10n.lastPaymentLabel,
      l10n.reportColOverdue,
    ]));
  for (final d in data.debtors) {
    debtors.add([
      XlsxText(d.name),
      text(d.phone),
      money(d.balanceBaseMinor),
      d.creditLimitBaseMinor == null ? null : money(d.creditLimitBaseMinor!),
      date(d.oldestUnpaidAt),
      date(d.lastPaymentAt),
      XlsxText(d.overdue ? l10n.reportYes : l10n.reportNo),
    ]);
  }

  final movements = XlsxSheet(name: names[2], rightToLeft: rtl)
    ..add(header([
      l10n.reportColTime,
      l10n.reportColDate,
      l10n.reportColCustomer,
      l10n.reportColEntry,
      l10n.reportColDebit,
      l10n.reportColCredit,
      l10n.reportColReceiptNo,
      l10n.reportColInvoiceNo,
      l10n.reportColMethod,
      l10n.reportColNote,
      l10n.reportColStatus,
    ]));
  for (final m in data.movements) {
    final e = m.entry;
    movements.add([
      XlsxDate(e.recordedAt.toLocal(), withTime: true),
      XlsxDate(e.createdAt.toLocal()),
      XlsxText(m.customerName),
      XlsxText(describeEntry(l10n, e, locale: data.language)),
      e.isDebit ? money(e.amountBaseMinor) : null,
      e.isDebit ? null : money(e.amountBaseMinor),
      e.receiptNo == null ? null : XlsxInt(e.receiptNo!),
      e.invoiceNo == null ? null : XlsxInt(e.invoiceNo!),
      e.paymentMethod == null
          ? null
          : XlsxText(paymentMethodLabel(l10n, e.paymentMethod!)),
      text(e.note),
      e.isReversed ? XlsxText(l10n.reportReversed) : null,
    ]);
  }

  final balances = XlsxSheet(name: names[3], rightToLeft: rtl)
    ..add(header([
      l10n.reportColCustomer,
      l10n.reportColPhone,
      l10n.reportColBalance,
      l10n.reportColStatus,
      l10n.creditLimitLabel,
      l10n.lastPaymentLabel,
      l10n.reportColActive,
    ]));
  for (final b in data.balances) {
    balances.add([
      XlsxText(b.name),
      text(b.phone),
      money(b.balanceBaseMinor),
      XlsxText(
        b.balanceBaseMinor > 0
            ? l10n.reportStatusOwes
            : b.balanceBaseMinor < 0
                ? l10n.reportStatusCredit
                : l10n.reportStatusSettled,
      ),
      b.creditLimitBaseMinor == null ? null : money(b.creditLimitBaseMinor!),
      date(b.lastPaymentAt),
      XlsxText(b.isActive ? l10n.reportYes : l10n.reportNo),
    ]);
  }

  return XlsxWorkbook(
    sheets: [summary, debtors, movements, balances],
    moneyDecimals: decimals,
    moneySymbol: data.currency.label,
  ).encode();
}
