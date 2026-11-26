import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../core/money/money_format.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_text.dart';
import '../invoice/invoice_view.dart';
import 'debt_text.dart';

const _ink = Color(0xFF000000);
const _paper = Color(0xFFFFFFFF);

/// Everything a payment receipt ("سند قبض") prints.
class ReceiptData {
  const ReceiptData({
    required this.payment,
    required this.customerName,
    this.customerPhone,
    required this.baseCurrencyCode,
  });

  /// The PAYMENT entry, with its receipt number and the balance before it.
  final DebtEntry payment;
  final String customerName;
  final String? customerPhone;
  final String baseCurrencyCode;
}

/// Everything an account statement ("كشف حساب") prints.
class StatementData {
  const StatementData({
    required this.statement,
    required this.customerName,
    this.customerPhone,
    required this.baseCurrencyCode,
    required this.printedAt,
  });

  final AccountStatement statement;
  final String customerName;
  final String? customerPhone;
  final String baseCurrencyCode;
  final DateTime printedAt;
}

/// The frame every paper of the ledger shares with the invoice: its own
/// direction (the INVOICE language), font, colours and strings, no text
/// scaling — so it renders identically on screen and in the off-screen
/// capture — with the shop header on top and the footer underneath.
class _Paper extends StatelessWidget {
  const _Paper({
    required this.settings,
    required this.logo,
    required this.padding,
    required this.isCopy,
    required this.title,
    required this.builder,
    this.cancelled = false,
  });

  final InvoiceSettings settings;
  final ui.Image? logo;
  final EdgeInsets padding;
  final bool isCopy;
  final String title;

  /// The paper was cancelled (a reversed payment): says so in a box.
  final bool cancelled;
  final List<Widget> Function(_PaperStyle style) builder;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l10n = lookupAppLocalizations(Locale(s.language));
    final base = s.baseFontSize.toDouble();
    final body = TextStyle(
      fontFamily: 'Tajawal',
      fontSize: base,
      height: 1.3,
      color: _ink,
      // Medium, not Regular: thin strokes are the first thing a thermal head
      // loses.
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    );
    final style = _PaperStyle(
      l10n: l10n,
      base: base,
      gap: base * 0.4,
      body: body,
      bold: body.copyWith(fontWeight: FontWeight.w700),
      small: body.copyWith(fontSize: base * 0.8),
      rule: PaperRule(thickness: base >= 28 ? 3 : 2, space: base * 0.4),
    );
    final shopName = s.shopName.trim();
    final header = isolateSpacedNumbers(s.headerText.trim());
    final footer = isolateSpacedNumbers(s.footerText.trim());

    return MediaQuery(
      // Fresh data: no text scaling, no bold-text override from the phone.
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: s.isRtl ? TextDirection.rtl : TextDirection.ltr,
        child: ColoredBox(
          color: _paper,
          child: DefaultTextStyle(
            style: body,
            child: Padding(
              padding: padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isCopy) ...[
                    PaperCopyMark(
                      label: l10n.invoiceCopyMark,
                      style: style.bold,
                      base: base,
                    ),
                    SizedBox(height: style.gap),
                  ],
                  if (cancelled) ...[
                    PaperCopyMark(
                      label: l10n.receiptReversedMark,
                      style: style.bold,
                      base: base,
                    ),
                    SizedBox(height: style.gap),
                  ],
                  if (logo != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: style.gap),
                      child: Center(
                        child: FractionallySizedBox(
                          widthFactor: 0.45,
                          child: RawImage(
                            image: logo,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                      ),
                    ),
                  if (shopName.isNotEmpty)
                    Text(
                      shopName,
                      textAlign: TextAlign.center,
                      style: style.bold
                          .copyWith(fontSize: base * 1.45, height: 1.25),
                    ),
                  if (header.isNotEmpty)
                    Text(header, textAlign: TextAlign.center),
                  if (logo != null || shopName.isNotEmpty || header.isNotEmpty)
                    style.rule,
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: style.bold.copyWith(fontSize: base * 1.25),
                  ),
                  SizedBox(height: style.gap * 0.5),
                  ...builder(style),
                  if (footer.isNotEmpty) ...[
                    style.rule,
                    Text(footer, textAlign: TextAlign.center),
                  ],
                  if (s.showPoweredBy)
                    Padding(
                      padding: EdgeInsets.only(top: style.gap),
                      child: Text(
                        l10n.poweredByFooter,
                        textAlign: TextAlign.center,
                        style: style.small,
                      ),
                    ),
                  // A paper made on the trial says so, like an invoice.
                  if (s.trialNotice)
                    Padding(
                      padding: EdgeInsets.only(top: style.gap),
                      child: Text(
                        l10n.invoiceTrialLine,
                        textAlign: TextAlign.center,
                        style: style.small,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperStyle {
  const _PaperStyle({
    required this.l10n,
    required this.base,
    required this.gap,
    required this.body,
    required this.bold,
    required this.small,
    required this.rule,
  });

  final AppLocalizations l10n;
  final double base;
  final double gap;
  final TextStyle body;
  final TextStyle bold;
  final TextStyle small;
  final Widget rule;
}

/// A balance on paper: "عليه 5,000 ل.س" as two separate text runs, so the
/// amount can never be reordered by the Arabic word beside it, and a narrow
/// paper wraps between the two.
class _PaperBalance extends StatelessWidget {
  const _PaperBalance({
    required this.baseMinor,
    required this.money,
    required this.currencyCode,
    required this.l10n,
    required this.gap,
    this.style,
  });

  final int baseMinor;
  final InvoiceMoney money;
  final String currencyCode;
  final AppLocalizations l10n;
  final double gap;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: gap * 0.6,
      children: [
        if (baseMinor != 0)
          Text(baseMinor > 0 ? l10n.paperOwes : l10n.paperCredit, style: style),
        Text(money.amount(baseMinor.abs(), currencyCode), style: style),
      ],
    );
  }
}

/// A payment receipt ("سند قبض") as it is printed and shared: receipt
/// number, date, the customer, the balance before, the amount paid and the
/// balance after, under the shop's header and over its footer.
///
/// The same rules as [InvoiceView], because it goes through the same
/// off-screen capture: one logical pixel per printer dot, self-contained,
/// worded in the INVOICE language, a "COPY" mark on a reprint.
class ReceiptView extends StatelessWidget {
  const ReceiptView({
    super.key,
    required this.receipt,
    required this.settings,
    required this.currencies,
    this.logo,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.isCopy = false,
  });

  final ReceiptData receipt;
  final InvoiceSettings settings;
  final Map<String, Currency> currencies;
  final ui.Image? logo;
  final EdgeInsets padding;
  final bool isCopy;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final payment = receipt.payment;
    final baseCode = receipt.baseCurrencyCode;
    final money = InvoiceMoney(
      currencies: currencies,
      display: s.currencyDisplay,
      locale: s.language,
    );
    final phone = receipt.customerPhone?.trim() ?? '';
    final note = payment.note?.trim() ?? '';
    final before = payment.balanceBeforeBaseMinor;
    final after = payment.balanceAfterBaseMinor;
    final origCode = payment.origCurrencyCode;
    final origAmount = payment.origAmountMinor;
    final origRate = payment.origRate;
    final method = payment.paymentMethod;

    return _Paper(
      settings: s,
      logo: logo,
      padding: padding,
      isCopy: isCopy,
      cancelled: payment.isReversed,
      title: lookupAppLocalizations(Locale(s.language)).receiptTitle,
      builder: (style) {
        final l10n = style.l10n;
        final gap = style.gap;
        return [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: gap,
            children: [
              if (payment.receiptNo != null)
                Text(
                  l10n.receiptNoLabel(
                    localizeDigits('${payment.receiptNo}', s.language),
                  ),
                  style: style.bold,
                ),
              Text(
                formatInvoiceDateTime(payment.createdAt, locale: s.language),
                // One left-to-right unit even on an Arabic paper.
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
          style.rule,
          PaperPair(
            label: l10n.receiptReceivedFrom,
            gap: gap,
            value: Text(receipt.customerName.trim(), style: style.bold),
          ),
          if (s.showCustomerPhone && phone.isNotEmpty)
            PaperPair(
              label: l10n.invoicePhoneLabel,
              gap: gap,
              value: Text(phone, textDirection: TextDirection.ltr),
            ),
          style.rule,
          if (before != null)
            PaperPair(
              label: l10n.previousBalanceLabel,
              gap: gap,
              colon: false,
              value: _PaperBalance(
                baseMinor: before,
                money: money,
                currencyCode: baseCode,
                l10n: l10n,
                gap: gap,
              ),
            ),
          PaperPair(
            label: l10n.receiptAmountLabel,
            gap: gap,
            colon: false,
            labelStyle: style.bold.copyWith(fontSize: style.base * 1.2),
            value: Text(
              money.amount(payment.amountBaseMinor, baseCode),
              style: style.bold.copyWith(fontSize: style.base * 1.2),
            ),
          ),
          if (origCode != null && origAmount != null) ...[
            PaperPair(
              label: l10n.receiptPaidAs,
              gap: gap,
              value: Text(money.amount(origAmount, origCode)),
            ),
            if (origRate != null)
              PaperAtoms(
                gap: gap * 0.6,
                alignEnd: true,
                style: style.small,
                children: [
                  Text('${localizeDigits('1', s.language)} '
                      '${money.label(origCode)}'),
                  const Text('='),
                  Text('${formatRateValue(origRate, locale: s.language)} '
                      '${money.label(baseCode)}'),
                ],
              ),
          ],
          if (method != null)
            PaperPair(
              label: l10n.receiptMethodLabel,
              gap: gap,
              value: Text(paymentMethodLabel(l10n, method)),
            ),
          if (after != null)
            PaperPair(
              label: l10n.newBalanceLabel,
              gap: gap,
              colon: false,
              labelStyle: style.bold,
              value: _PaperBalance(
                baseMinor: after,
                money: money,
                currencyCode: baseCode,
                l10n: l10n,
                gap: gap,
                style: style.bold,
              ),
            ),
          if (note.isNotEmpty) ...[
            SizedBox(height: gap * 0.5),
            PaperPair(
              label: l10n.receiptNoteLabel,
              gap: gap,
              value: Text(note),
            ),
          ],
        ];
      },
    );
  }
}

/// An account statement ("كشف حساب") as it is printed and shared: the
/// balance brought forward, every entry of the period with its running
/// balance, the totals of debits and credits, and the closing balance.
///
/// One long strip, like a long invoice: a thermal printer simply keeps
/// feeding, and the capture already cuts tall papers into slices.
class StatementView extends StatelessWidget {
  const StatementView({
    super.key,
    required this.data,
    required this.settings,
    required this.currencies,
    this.logo,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.isCopy = false,
  });

  final StatementData data;
  final InvoiceSettings settings;
  final Map<String, Currency> currencies;
  final ui.Image? logo;
  final EdgeInsets padding;
  final bool isCopy;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final statement = data.statement;
    final baseCode = data.baseCurrencyCode;
    final money = InvoiceMoney(
      currencies: currencies,
      display: s.currencyDisplay,
      locale: s.language,
    );
    final phone = data.customerPhone?.trim() ?? '';
    final from = statement.from;
    final to = statement.to;

    return _Paper(
      settings: s,
      logo: logo,
      padding: padding,
      isCopy: isCopy,
      title: lookupAppLocalizations(Locale(s.language)).accountStatement,
      builder: (style) {
        final l10n = style.l10n;
        final gap = style.gap;
        String day(DateTime moment) =>
            formatInvoiceDate(moment.toLocal(), locale: s.language);
        // The last day of the range is the day BEFORE its exclusive end.
        final lastDay = to?.toLocal().subtract(const Duration(days: 1));
        final period = from == null && lastDay == null
            ? l10n.statementWholeAccount
            : from == null
                ? l10n.statementUntil(day(lastDay!))
                : null;

        Widget balance(int baseMinor, {TextStyle? textStyle}) => _PaperBalance(
              baseMinor: baseMinor,
              money: money,
              currencyCode: baseCode,
              l10n: l10n,
              gap: gap,
              style: textStyle,
            );

        return [
          PaperPair(
            label: l10n.invoiceCustomerLabel,
            gap: gap,
            value: Text(data.customerName.trim(), style: style.bold),
          ),
          if (s.showCustomerPhone && phone.isNotEmpty)
            PaperPair(
              label: l10n.invoicePhoneLabel,
              gap: gap,
              value: Text(phone, textDirection: TextDirection.ltr),
            ),
          if (period != null)
            Text(period, textAlign: TextAlign.center)
          else
            // Two dates, each its own left-to-right run.
            PaperAtoms(
              gap: gap * 0.6,
              children: [
                Text(day(from!), textDirection: TextDirection.ltr),
                const Text('—'),
                Text(
                  day(lastDay ?? data.printedAt),
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          style.rule,
          PaperPair(
            label: l10n.statementOpening,
            gap: gap,
            colon: false,
            value: balance(statement.openingBalanceBaseMinor),
          ),
          style.rule,
          if (statement.lines.isEmpty)
            Text(l10n.statementNoEntries, textAlign: TextAlign.center),
          for (final line in statement.lines)
            _StatementLine(
              line: line,
              style: style,
              money: money,
              baseCode: baseCode,
              language: s.language,
            ),
          style.rule,
          PaperPair(
            label: l10n.statementTotalDebits,
            gap: gap,
            colon: false,
            value: Text(money.amount(statement.totalDebitsBaseMinor, baseCode)),
          ),
          PaperPair(
            label: l10n.statementTotalCredits,
            gap: gap,
            colon: false,
            value:
                Text(money.amount(statement.totalCreditsBaseMinor, baseCode)),
          ),
          PaperPair(
            label: l10n.statementClosing,
            gap: gap,
            colon: false,
            labelStyle: style.bold.copyWith(fontSize: style.base * 1.15),
            value: balance(
              statement.closingBalanceBaseMinor,
              textStyle: style.bold.copyWith(fontSize: style.base * 1.15),
            ),
          ),
          SizedBox(height: gap * 0.5),
          Text(
            formatInvoiceDateTime(data.printedAt, locale: s.language),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: style.small,
          ),
        ];
      },
    );
  }
}

/// One entry of a statement: the date and what it was, then the amount
/// (under "debit" or "credit") at the start and the running balance at the
/// end. A cancelled entry and its reversal both stay on the statement — the
/// account really did go up and down — with the cancelled one marked.
class _StatementLine extends StatelessWidget {
  const _StatementLine({
    required this.line,
    required this.style,
    required this.money,
    required this.baseCode,
    required this.language,
  });

  final LedgerLine line;
  final _PaperStyle style;
  final InvoiceMoney money;
  final String baseCode;
  final String language;

  @override
  Widget build(BuildContext context) {
    final entry = line.entry;
    final l10n = style.l10n;
    final gap = style.gap;
    final after = line.balanceAfterBaseMinor;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap * 0.25),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Each line is a Wrap of separate text runs: on a wide paper the
          // two ends sit on one line; on a narrow paper at a large font the
          // second one moves under the first instead of running off the edge.
          Wrap(
            spacing: gap,
            children: [
              Text(
                formatInvoiceDate(entry.createdAt.toLocal(), locale: language),
                textDirection: TextDirection.ltr,
              ),
              Text(
                entry.isReversed
                    ? '${describeEntry(l10n, entry, locale: language)} '
                        '(${l10n.entryReversed})'
                    : describeEntry(l10n, entry, locale: language),
                style: style.bold,
              ),
            ],
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: gap,
            children: [
              Wrap(
                spacing: gap * 0.6,
                children: [
                  Text(entry.isDebit ? l10n.ledgerDebit : l10n.ledgerCredit),
                  Text(money.amount(
                    entry.amountBaseMinor,
                    baseCode,
                    withCurrency: false,
                  )),
                ],
              ),
              Wrap(
                spacing: gap * 0.6,
                children: [
                  if (after != 0)
                    Text(
                      after > 0 ? l10n.paperOwes : l10n.paperCredit,
                      style: style.small,
                    ),
                  Text(
                    money.amount(after.abs(), baseCode, withCurrency: false),
                    style: style.bold,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
