import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../config/features.dart';
import '../../core/money/money_format.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
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
  });

  final Invoice invoice;
  final InvoiceSettings settings;

  /// The currency table by code (symbols and decimal places).
  final Map<String, Currency> currencies;

  /// The decoded shop logo. Decoded by the caller so the first frame already
  /// contains it — the off-screen capture renders exactly one frame.
  final ui.Image? logo;

  /// White space around the content. The printer needs none at the sides
  /// (the paper margin is physical); a shared image gets some.
  final EdgeInsets padding;

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
          value: Text(
            s.maskAccountNumber ? maskAllButLast4(accountNumber) : accountNumber,
            textDirection: TextDirection.ltr,
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
/// "qty × price" at the start and "= total" at the end.
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
              if (unitPrice != null) ...[
                const Text('='),
                SizedBox(width: gap * 0.6),
              ],
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
