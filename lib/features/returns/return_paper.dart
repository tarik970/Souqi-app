import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/money/money_format.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice_return.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../debts/debt_output.dart';
import '../debts/debt_papers.dart';
import '../invoice/invoice_text.dart';
import '../invoice/invoice_view.dart';

/// The words for how a refund was given back.
String refundMethodLabel(AppLocalizations l10n, RefundMethod method) =>
    switch (method) {
      RefundMethod.cash => l10n.refundMethodCash,
      RefundMethod.debt => l10n.refundMethodDebt,
      RefundMethod.credit => l10n.refundMethodCredit,
    };

/// A RETURN DOCUMENT ("مرتجع رقم 12 — من فاتورة 152") as it is printed and
/// shared: its number and date, the invoice it returns from, the customer,
/// the returned lines, the refund and how it was given back, the reason.
///
/// The same rules as the invoice and the receipt, because it goes through
/// the same off-screen capture ([PaperFrame]): one logical pixel per printer
/// dot, self-contained, worded and laid out in the INVOICE language — right
/// to left in Arabic, left to right in English — and a "COPY" mark on a
/// reprint.
class ReturnView extends StatelessWidget {
  const ReturnView({
    super.key,
    required this.document,
    required this.settings,
    required this.currencies,
    this.logo,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.isCopy = false,
  });

  final InvoiceReturn document;
  final InvoiceSettings settings;
  final Map<String, Currency> currencies;
  final ui.Image? logo;
  final EdgeInsets padding;
  final bool isCopy;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final doc = document;
    final code = doc.currencyCode;
    final money = InvoiceMoney(
      currencies: currencies,
      display: s.currencyDisplay,
      locale: s.language,
    );
    final name = doc.customerName?.trim() ?? '';
    final phone = doc.customerPhone?.trim() ?? '';
    final reason = doc.reason?.trim() ?? '';
    // A refund given back two ways (off the debt, the rest in cash) says
    // each amount; given back one way, it only names the way.
    final parts = [
      if (doc.debtMinor > 0) (RefundMethod.debt, doc.debtMinor),
      if (doc.creditMinor > 0) (RefundMethod.credit, doc.creditMinor),
      if (doc.cashMinor > 0) (RefundMethod.cash, doc.cashMinor),
    ];

    return PaperFrame(
      settings: s,
      logo: logo,
      padding: padding,
      isCopy: isCopy,
      title: lookupAppLocalizations(Locale(s.language)).returnTitle,
      builder: (style) {
        final l10n = style.l10n;
        final gap = style.gap;
        return [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: gap,
            children: [
              Text(
                l10n.returnNoLabel(
                  localizeDigits('${doc.returnNo}', s.language),
                ),
                style: style.bold,
              ),
              Text(
                formatInvoiceDateTime(doc.createdAt, locale: s.language),
                // One left-to-right unit even on an Arabic paper.
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
          Text(
            l10n.returnFromInvoice(
              localizeDigits('${doc.invoiceNo}', s.language),
            ),
          ),
          if (name.isNotEmpty || phone.isNotEmpty) style.rule,
          if (s.showCustomerName && name.isNotEmpty)
            PaperPair(
              label: l10n.invoiceCustomerLabel,
              gap: gap,
              value: Text(name),
            ),
          if (s.showCustomerPhone && phone.isNotEmpty)
            PaperPair(
              label: l10n.invoicePhoneLabel,
              gap: gap,
              value: Text(phone, textDirection: TextDirection.ltr),
            ),
          style.rule,
          for (final item in doc.items)
            _ReturnedLine(
              item: item,
              style: style,
              money: money,
              currencyCode: code,
              showCode: s.showItemCode,
              showUnit: s.showUnit,
              language: s.language,
            ),
          style.rule,
          PaperPair(
            label: l10n.returnRefundTotal,
            gap: gap,
            colon: false,
            labelStyle: style.bold.copyWith(fontSize: style.base * 1.3),
            value: Text(
              money.amount(doc.refundMinor, code),
              style: style.bold.copyWith(fontSize: style.base * 1.3),
            ),
          ),
          if (parts.length == 1)
            PaperPair(
              label: l10n.returnRefundMethod,
              gap: gap,
              value: Text(refundMethodLabel(l10n, parts.single.$1)),
            )
          else
            for (final (method, amount) in parts)
              PaperPair(
                label: refundMethodLabel(l10n, method),
                gap: gap,
                colon: false,
                value: Text(money.amount(amount, code)),
              ),
          if (reason.isNotEmpty) ...[
            SizedBox(height: gap * 0.5),
            PaperPair(
              label: l10n.reasonLabel,
              gap: gap,
              value: Text(reason),
            ),
          ],
        ];
      },
    );
  }
}

/// One returned line: its name (with the code when enabled), then the
/// quantity at the start and what was given back for it at the end.
class _ReturnedLine extends StatelessWidget {
  const _ReturnedLine({
    required this.item,
    required this.style,
    required this.money,
    required this.currencyCode,
    required this.showCode,
    required this.showUnit,
    required this.language,
  });

  final InvoiceReturnItem item;
  final PaperStyle style;
  final InvoiceMoney money;
  final String currencyCode;
  final bool showCode;
  final bool showUnit;
  final String language;

  @override
  Widget build(BuildContext context) {
    final gap = style.gap;
    final code = item.productCode;
    final unit = item.unitName;
    final qty = formatQuantity(item.qtyThousandths, locale: language);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap * 0.25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCode && code != null && code.isNotEmpty) ...[
                Text(code, textDirection: TextDirection.ltr),
                SizedBox(width: gap),
              ],
              Expanded(child: Text(item.productName, style: style.bold)),
            ],
          ),
          // A Wrap of two text runs: the quantity at the start of the line
          // and the amount at its end on a wide paper; on a narrow paper at
          // a large font the amount moves under the quantity instead of
          // running off the edge. Separate runs, so the unit beside the
          // quantity can never reorder the number.
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: gap,
            children: [
              Text(
                showUnit && unit != null && unit.isNotEmpty
                    ? '$qty $unit'
                    : qty,
              ),
              Text(
                money.amount(
                  item.refundMinor,
                  currencyCode,
                  withCurrency: false,
                ),
                style: style.bold,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A return document as a [LedgerPaper]: it prints, shares, goes to
/// WhatsApp and saves through the same pipeline as a receipt.
LedgerPaper returnPaper(InvoiceReturn document) => LedgerPaper(
      fileName: 'return-${document.returnNo}',
      caption: (l10n) => '${l10n.returnNoLabel('${document.returnNo}')} — '
          '${l10n.returnFromInvoice('${document.invoiceNo}')}',
      customerPhone: document.customerPhone,
      build: (c, {padding, required copy}) => ReturnView(
        document: document,
        settings: c.settings,
        currencies: c.currencies,
        logo: c.logo,
        isCopy: copy,
        padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
      ),
    );
