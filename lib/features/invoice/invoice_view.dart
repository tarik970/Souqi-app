import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/utils/normalize.dart';
import '../../core/utils/voucher_format.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
import '../../domain/models/voucher.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_text.dart';

const _ink = Color(0xFF000000);
const _paper = Color(0xFFFFFFFF);

/// The invoice as it is printed and shared — ONE widget for the thermal
/// print, the shared image/PDF, the settings preview and the on-screen view.
///
/// It is laid out with one logical pixel per printer dot, so the parent
/// gives it a width in dots (see [InvoiceSettings.printableDots]) and it
/// takes the height its content needs.
///
/// Self-contained on purpose: it sets its own direction (from the INVOICE
/// language, independent of the app language), its own font, colours and
/// strings, and ignores the phone's text-scale setting. It therefore renders
/// identically on screen and in the off-screen capture, which has no Theme,
/// no MediaQuery and no Localizations above it.
class InvoiceView extends StatelessWidget {
  const InvoiceView({
    super.key,
    required this.invoice,
    required this.settings,
    required this.currencies,
    this.logo,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.isCopy = false,
    this.codes = const [],
  });

  final Invoice invoice;
  final InvoiceSettings settings;

  /// The prepaid card codes this invoice sold, printed under the totals:
  /// each in a large block with its product name and serial. The printer and
  /// share pipeline passes them in full — the customer is buying exactly
  /// these digits; the on-screen previews pass them with the secret dropped
  /// ([InvoiceCode.hidden]) and get the masked form.
  final List<InvoiceCode> codes;

  /// The currency table by code (symbols and decimal places).
  final Map<String, Currency> currencies;

  /// The decoded shop logo. Decoded by the caller so the first frame already
  /// contains it — the off-screen capture renders exactly one frame.
  final ui.Image? logo;

  /// White space around the content. The printer needs none at the sides
  /// (the paper margin is physical); a shared image gets some.
  final EdgeInsets padding;

  /// This is a REPRINT or a re-share from the archive, not the original
  /// receipt handed over at the till. It gets a "COPY / نسخة" mark at the
  /// top so nobody can present it as a second sale.
  final bool isCopy;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l10n = lookupAppLocalizations(Locale(s.language));
    final money = InvoiceMoney(
      currencies: currencies,
      display: s.currencyDisplay,
      locale: s.language,
    );
    final base = s.baseFontSize.toDouble();
    final gap = base * 0.4;
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
    final bold = body.copyWith(fontWeight: FontWeight.w700);
    final small = body.copyWith(fontSize: base * 0.8);
    final rule = _DashedRule(thickness: base >= 28 ? 3 : 2, space: base * 0.4);

    final shopName = s.shopName.trim();
    final header = isolateSpacedNumbers(s.headerText.trim());
    final footer = isolateSpacedNumbers(s.footerText.trim());
    final customerName = invoice.customerName?.trim() ?? '';
    final customerPhone = invoice.customerPhone?.trim() ?? '';
    final accountNumber = invoice.accountNumber?.trim() ?? '';
    final accountProvider = invoice.accountProvider?.trim() ?? '';
    final rates = invoiceRatesUsed(invoice);

    final meta = <Widget>[
      if (s.showInvoiceNumber || s.showDateTime)
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: gap,
          children: [
            if (s.showInvoiceNumber)
              Text(
                l10n.invoiceNoLabel(
                  localizeDigits('${invoice.invoiceNo}', s.language),
                ),
                style: bold,
              ),
            if (s.showDateTime)
              Text(
                formatInvoiceDateTime(invoice.createdAt, locale: s.language),
                // A date is one left-to-right unit even on an Arabic invoice;
                // without this the bidi algorithm swaps the date and the time.
                textDirection: TextDirection.ltr,
              ),
          ],
        ),
      if (customersEnabled && s.showCustomerName && customerName.isNotEmpty)
        _Pair(label: l10n.invoiceCustomerLabel, gap: gap, value: Text(customerName)),
      if (customersEnabled && s.showCustomerPhone && customerPhone.isNotEmpty)
        _Pair(
          label: l10n.invoicePhoneLabel,
          gap: gap,
          value: Text(customerPhone, textDirection: TextDirection.ltr),
        ),
      if (accountsEnabled && s.showAccountNumber && accountNumber.isNotEmpty)
        _Pair(
          label: l10n.invoiceAccountLabel,
          gap: gap,
          // The provider and the number are separate text runs: the number
          // keeps its own left-to-right order, and a narrow paper wraps
          // between the two, never inside the number. The provider follows
          // the same toggle — it only says whose number this is.
          value: Wrap(
            alignment: WrapAlignment.end,
            spacing: gap * 0.6,
            children: [
              if (accountProvider.isNotEmpty) Text(accountProvider),
              Text(
                s.maskAccountNumber
                    ? maskAllButLast4(accountNumber)
                    : accountNumber,
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
        ),
    ];

    final hasHeader = logo != null || shopName.isNotEmpty || header.isNotEmpty;

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
                    _CopyMark(label: l10n.invoiceCopyMark, style: bold, base: base),
                    SizedBox(height: gap),
                  ],
                  if (logo != null)
                    Padding(
                      padding: EdgeInsets.only(bottom: gap),
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
                      style: bold.copyWith(fontSize: base * 1.45, height: 1.25),
                    ),
                  if (header.isNotEmpty)
                    Text(header, textAlign: TextAlign.center),
                  if (hasHeader) rule,
                  ...meta,
                  if (meta.isNotEmpty) rule,
                  for (final item in invoice.items)
                    _ItemBlock(
                      item: item,
                      text: describeInvoiceLine(
                        item,
                        invoiceCurrencyCode: invoice.currencyCode,
                        money: money,
                        showUnit: s.showUnit,
                        showUnitPrice: s.showUnitPrice,
                      ),
                      showCode: s.showItemCode,
                      gap: gap,
                      bold: bold,
                    ),
                  rule,
                  if (discountEnabled && invoice.discountMinor != 0) ...[
                    _Pair(
                      label: l10n.subtotalLabel,
                      gap: gap,
                      colon: false,
                      value: Text(money.amount(
                        invoice.subtotalMinor,
                        invoice.currencyCode,
                        withCurrency: false,
                      )),
                    ),
                    _Pair(
                      label: invoice.discountType == DiscountType.percent &&
                              invoice.discountValue != null
                          ? '${l10n.discountLabel} '
                              '${formatBasisPoints(invoice.discountValue!, locale: s.language)}%'
                          : l10n.discountLabel,
                      gap: gap,
                      colon: false,
                      value: Text(money.amount(
                        invoice.discountMinor,
                        invoice.currencyCode,
                        withCurrency: false,
                      )),
                    ),
                  ],
                  _Pair(
                    label: l10n.totalLabel,
                    gap: gap,
                    colon: false,
                    labelStyle: bold.copyWith(fontSize: base * 1.3),
                    value: Text(
                      money.amount(invoice.totalMinor, invoice.currencyCode),
                      style: bold.copyWith(fontSize: base * 1.3),
                    ),
                  ),
                  for (final extra in invoice.extraTotals)
                    _Atoms(
                      gap: gap * 0.6,
                      alignEnd: true,
                      children: [
                        const Text('≈'),
                        Text(money.amount(extra.totalMinor, extra.currencyCode)),
                      ],
                    ),
                  for (final rate in rates)
                    _Atoms(
                      gap: gap * 0.6,
                      alignEnd: true,
                      style: small,
                      children: [
                        // Separate atoms so each "number + currency" pair
                        // keeps its internal order in both directions.
                        Text('${localizeDigits('1', s.language)} '
                            '${money.label(rate.code)}'),
                        const Text('='),
                        Text('${formatRateValue(rate.rate, locale: s.language)} '
                            '${money.label(invoice.baseCurrencyCode)}'),
                      ],
                    ),
                  if (voucherStockEnabled)
                    for (final code in codes) ...[
                      rule,
                      InvoiceCodeBlock(
                        code: code,
                        base: base,
                        language: s.language,
                        showQr: s.printCodeQr,
                      ),
                    ],
                  if (footer.isNotEmpty) ...[
                    rule,
                    Text(footer, textAlign: TextAlign.center),
                  ],
                  if (s.showPoweredBy)
                    Padding(
                      padding: EdgeInsets.only(top: gap),
                      child: Text(
                        l10n.poweredByFooter,
                        textAlign: TextAlign.center,
                        style: small,
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

/// One item: its name (with the code when enabled), then the detail line —
/// "qty × price" at the start and the line total at the end. No "=" between
/// them: on a cross-currency line the two amounts are in different
/// currencies, and even on a plain line the equals sign only adds ink.
class _ItemBlock extends StatelessWidget {
  const _ItemBlock({
    required this.item,
    required this.text,
    required this.showCode,
    required this.gap,
    required this.bold,
  });

  final InvoiceItem item;
  final InvoiceLineText text;
  final bool showCode;
  final double gap;
  final TextStyle bold;

  @override
  Widget build(BuildContext context) {
    final code = item.productCode;
    final unitPrice = text.unitPrice;
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
              Expanded(child: Text(item.productName, style: bold)),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                // Every part is its own text run, so "5,000 SYP" can never
                // be split or reordered by a neighbouring Arabic word, and a
                // narrow paper wraps between parts, not inside one.
                child: Wrap(
                  spacing: gap * 0.6,
                  children: [
                    Text(text.quantity),
                    if (unitPrice != null) ...[
                      const Text('×'),
                      Text(unitPrice),
                    ],
                  ],
                ),
              ),
              SizedBox(width: gap),
              Text(text.total, style: bold),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Label: ........ value", the value pushed to the end edge.
class _Pair extends StatelessWidget {
  const _Pair({
    required this.label,
    required this.value,
    required this.gap,
    this.colon = true,
    this.labelStyle,
  });

  final String label;
  final Widget value;
  final double gap;
  final bool colon;
  final TextStyle? labelStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(colon ? '$label:' : label, style: labelStyle),
        SizedBox(width: gap),
        Expanded(
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: value,
          ),
        ),
      ],
    );
  }
}

/// A run of separate text parts on one (wrapping) line.
class _Atoms extends StatelessWidget {
  const _Atoms({
    required this.children,
    required this.gap,
    this.alignEnd = false,
    this.style,
  });

  final List<Widget> children;
  final double gap;
  final bool alignEnd;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final wrap = Wrap(
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      spacing: gap,
      children: children,
    );
    return style == null ? wrap : DefaultTextStyle.merge(style: style, child: wrap);
  }
}

/// A dashed separator drawn on whole pixels with antialiasing off, so every
/// dash is solid black after the 1-bit conversion.
class _DashedRule extends StatelessWidget {
  const _DashedRule({required this.thickness, required this.space});

  final double thickness;
  final double space;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: space),
      child: SizedBox(
        height: thickness,
        child: CustomPaint(painter: _DashPainter()),
      ),
    );
  }
}

class _DashPainter extends CustomPainter {
  static const double _dash = 8;
  static const double _gap = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..isAntiAlias = false;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      final end = x + _dash > size.width ? size.width : x + _dash;
      canvas.drawRect(Rect.fromLTRB(x, 0, end, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => false;
}

/// The "COPY / نسخة" mark on a reprint: a boxed, letter-spaced line across
/// the top of the paper. A box rather than a colour or a shade, because the
/// only ink a thermal printer has is black and a grey wash comes out as
/// noise after the 1-bit conversion.
class _CopyMark extends StatelessWidget {
  const _CopyMark({
    required this.label,
    required this.style,
    required this.base,
  });

  final String label;
  final TextStyle style;
  final double base;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _ink, width: base >= 28 ? 3 : 2),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: base * 0.2),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: style.copyWith(
            fontSize: base * 1.1,
            letterSpacing: base * 0.15,
          ),
        ),
      ),
    );
  }
}

/// "2026/12/31" — numeric, the same in every language (only the digit shapes
/// follow [locale]).
String formatInvoiceDate(DateTime day, {required String locale}) {
  String two(int v) => v.toString().padLeft(2, '0');
  return localizeDigits('${day.year}/${two(day.month)}/${two(day.day)}', locale);
}

/// One sold card on the paper: the product name, the code in a large
/// fixed-pitch block grouped in fours ("1234 5678 9012 3456"), its serial,
/// its expiry and — when the setting is on — a QR code of the code.
///
/// The code is what the customer will type into the provider's page, often
/// reading it off a thermal print in poor light. So it is big and bold, every
/// character sits in a cell of the same width (the invoice font is not a
/// monospace one; the cells make it read like one), the groups never break
/// in the middle — a narrow paper wraps BETWEEN groups — and the block is
/// left-to-right even on an Arabic invoice.
class InvoiceCodeBlock extends StatelessWidget {
  const InvoiceCodeBlock({
    super.key,
    required this.code,
    required this.base,
    required this.language,
    required this.showQr,
  });

  final InvoiceCode code;

  /// The invoice's base font size, in printer dots.
  final double base;

  /// The INVOICE language.
  final String language;
  final bool showQr;

  @override
  Widget build(BuildContext context) {
    final l10n = lookupAppLocalizations(Locale(language));
    final plain = code.code;
    final small = TextStyle(fontSize: base * 0.8);
    final digits = base * 1.5;
    final serial = code.serial?.trim() ?? '';
    final expiry = code.expiryAt;
    // The masked form is already grouped: "•••• •••• 3456".
    final groups = plain == null ? code.masked.split(' ') : codeGroups(plain);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: base * 0.1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            code.productName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: base * 0.2),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: digits * 0.45,
              runSpacing: digits * 0.1,
              children: [
                for (final group in groups)
                  _CodeGroup(text: group, fontSize: digits),
              ],
            ),
          ),
          if (code.unreadable)
            Text(
              l10n.invoiceCodeUnreadable,
              textAlign: TextAlign.center,
              style: small,
            ),
          if (serial.isNotEmpty)
            DefaultTextStyle.merge(
              style: small,
              // Two runs: the serial keeps its own order beside Arabic.
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: base * 0.3,
                children: [
                  Text('${l10n.invoiceSerialLabel}:'),
                  Text(serial, textDirection: TextDirection.ltr),
                ],
              ),
            ),
          if (expiry != null)
            Text(
              l10n.invoiceExpiryLabel(
                formatInvoiceDate(expiryLastDay(expiry), locale: language),
              ),
              textAlign: TextAlign.center,
              style: small,
            ),
          if (showQr && plain != null)
            Padding(
              padding: EdgeInsets.only(top: base * 0.3),
              child: Center(
                child: _CodeQr(
                  data: stripCodeSeparators(plain),
                  target: base * 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// One group of the code, each character centred in a cell of the same
/// width. A wide letter is scaled down to its cell rather than pushing its
/// neighbours aside.
class _CodeGroup extends StatelessWidget {
  const _CodeGroup({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final cell = (fontSize * 0.64).roundToDouble();
    final style = TextStyle(
      fontSize: fontSize,
      height: 1.15,
      fontWeight: FontWeight.w700,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final char in text.split(''))
          SizedBox(
            width: cell,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(char, style: style),
            ),
          ),
      ],
    );
  }
}

/// A QR code of the card code, drawn on whole printer dots with antialiasing
/// off — every module is solid black after the 1-bit conversion — and with
/// the quiet zone a scanner needs around it.
class _CodeQr extends StatelessWidget {
  const _CodeQr({required this.data, required this.target});

  final String data;

  /// The side the symbol may take, quiet zone included, in dots.
  final double target;

  static const int _quietModules = 4;

  @override
  Widget build(BuildContext context) {
    final QrImage image;
    try {
      image = QrImage(
        QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
    } on Exception {
      // Longer than a QR code can hold: the digits above are the code.
      return const SizedBox.shrink();
    }
    final modules = image.moduleCount;
    var dot = (target / (modules + 2 * _quietModules)).floorToDouble();
    if (dot < 3) dot = 3;
    return Padding(
      padding: EdgeInsets.all(dot * _quietModules),
      child: SizedBox(
        width: dot * modules,
        height: dot * modules,
        child: CustomPaint(painter: _QrPainter(image, dot)),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image, this.dot);

  final QrImage image;
  final double dot;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..isAntiAlias = false;
    for (var row = 0; row < image.moduleCount; row++) {
      for (var col = 0; col < image.moduleCount; col++) {
        if (!image.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(col * dot, row * dot, dot, dot),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.dot != dot;
}

/// One sold card on a slip of its own — the "print each card on a separate
/// slip" option: for the customer who buys five cards to hand out. The shop
/// name, the card, and the invoice it belongs to.
///
/// Self-contained exactly like [InvoiceView], because it goes through the
/// same off-screen capture.
class CodeSlipView extends StatelessWidget {
  const CodeSlipView({
    super.key,
    required this.invoice,
    required this.code,
    required this.settings,
    this.isCopy = false,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  final Invoice invoice;
  final InvoiceCode code;
  final InvoiceSettings settings;
  final bool isCopy;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l10n = lookupAppLocalizations(Locale(s.language));
    final base = s.baseFontSize.toDouble();
    final gap = base * 0.4;
    final body = TextStyle(
      fontFamily: 'Tajawal',
      fontSize: base,
      height: 1.3,
      color: _ink,
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    );
    final bold = body.copyWith(fontWeight: FontWeight.w700);
    final rule = _DashedRule(thickness: base >= 28 ? 3 : 2, space: base * 0.4);
    final shopName = s.shopName.trim();

    return MediaQuery(
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
                    _CopyMark(label: l10n.invoiceCopyMark, style: bold, base: base),
                    SizedBox(height: gap),
                  ],
                  if (shopName.isNotEmpty) ...[
                    Text(
                      shopName,
                      textAlign: TextAlign.center,
                      style: bold.copyWith(fontSize: base * 1.2, height: 1.25),
                    ),
                    rule,
                  ],
                  InvoiceCodeBlock(
                    code: code,
                    base: base,
                    language: s.language,
                    showQr: s.printCodeQr,
                  ),
                  rule,
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: gap,
                    children: [
                      Text(
                        l10n.invoiceNoLabel(
                          localizeDigits('${invoice.invoiceNo}', s.language),
                        ),
                        style: TextStyle(fontSize: base * 0.8),
                      ),
                      Text(
                        formatInvoiceDateTime(
                          invoice.createdAt,
                          locale: s.language,
                        ),
                        textDirection: TextDirection.ltr,
                        style: TextStyle(fontSize: base * 0.8),
                      ),
                    ],
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

/// The PIN recovery code on a slip of paper, to be kept away from the phone:
/// the shop name, what the code is, the code itself in the same large
/// fixed-pitch block a card code gets (three groups of four), and the date.
///
/// Self-contained exactly like [InvoiceView]: it goes through the same
/// off-screen capture. Worded in the INVOICE language, like everything else
/// that comes out of the printer.
class RecoverySlipView extends StatelessWidget {
  const RecoverySlipView({
    super.key,
    required this.code,
    required this.settings,
    required this.printedAt,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
  });

  /// The recovery code, with or without its dashes.
  final String code;
  final InvoiceSettings settings;
  final DateTime printedAt;
  final EdgeInsets padding;

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
      fontWeight: FontWeight.w500,
      decoration: TextDecoration.none,
    );
    final bold = body.copyWith(fontWeight: FontWeight.w700);
    final rule = _DashedRule(thickness: base >= 28 ? 3 : 2, space: base * 0.4);
    final shopName = s.shopName.trim();

    return MediaQuery(
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
                  if (shopName.isNotEmpty)
                    Text(
                      shopName,
                      textAlign: TextAlign.center,
                      style: bold.copyWith(fontSize: base * 1.2, height: 1.25),
                    ),
                  rule,
                  InvoiceCodeBlock(
                    code: InvoiceCode(
                      id: 0,
                      productName: l10n.recoverySlipTitle,
                      code: code,
                      masked: '',
                    ),
                    base: base,
                    language: s.language,
                    showQr: false,
                  ),
                  rule,
                  Text(l10n.recoverySlipHint, textAlign: TextAlign.center),
                  SizedBox(height: base * 0.3),
                  Text(
                    formatInvoiceDateTime(printedAt, locale: s.language),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: base * 0.8),
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
