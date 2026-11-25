import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../../core/printing/print_geometry.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_settings.dart';
import '../../domain/models/voucher.dart';
import 'invoice_view.dart';

/// The invoice on a strip of "paper", scaled down to fit the available
/// width. The strip keeps the real proportions: the paper is as wide as the
/// printable area plus the side margins, so changing the paper width, the
/// margins or the font size shows what will actually come out.
///
/// The [InvoiceView] inside is laid out at its true size in dots and only
/// scaled visually, so line breaks match the print exactly.
class InvoicePaperPreview extends StatelessWidget {
  const InvoicePaperPreview({
    super.key,
    required this.invoice,
    required this.settings,
    required this.currencies,
    this.logo,
    this.maxWidth = 340,
    this.isCopy = false,
    this.codes = const [],
  });

  /// The card codes the invoice sold, WITHOUT the secret
  /// ([InvoiceCode.hidden]): the preview shows them masked, where the print
  /// shows the digits.
  final List<InvoiceCode> codes;

  final Invoice invoice;
  final InvoiceSettings settings;
  final Map<String, Currency> currencies;
  final ui.Image? logo;

  /// The paper never grows wider than this on screen.
  final double maxWidth;

  /// Shows the "COPY / نسخة" mark, so the archive preview looks exactly
  /// like the reprint the buttons underneath produce.
  final bool isCopy;

  @override
  Widget build(BuildContext context) {
    final dots = settings.printableDots.toDouble();
    final margin =
        mmToDots(settings.sideMarginMm, settings.printerDpi).roundToDouble();
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: FittedBox(
            fit: BoxFit.fitWidth,
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: dots + 2 * margin,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: margin),
                child: InvoiceView(
                  invoice: invoice,
                  settings: settings,
                  currencies: currencies,
                  logo: logo,
                  isCopy: isCopy,
                  codes: codes,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
