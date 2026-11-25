import 'package:flutter/widgets.dart';

import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_text.dart';
import 'invoice_view.dart';

const _ink = Color(0xFF000000);
const _paper = Color(0xFFFFFFFF);

/// The slip a printer test prints: short, so trying several modes wastes
/// little paper, and always with a line of ARABIC on it — joined letters
/// are what a wrong mode or a dropped byte breaks first.
///
/// [label] says which test it is ("ESC/POS · GS v 0", "TSPL"), so slips
/// from different modes can be told apart once they are on the counter.
class PrinterTestSlipView extends StatelessWidget {
  const PrinterTestSlipView({
    super.key,
    required this.settings,
    required this.label,
    required this.printedAt,
  });

  final InvoiceSettings settings;
  final String label;
  final DateTime printedAt;

  /// Printed when the shop has no name yet.
  static const fallbackShopName = 'سوقي';

  @override
  Widget build(BuildContext context) {
    final s = settings;
    // Arabic whatever the invoice language is: the test is about Arabic.
    final arabic = lookupAppLocalizations(const Locale('ar'));
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
    final rule = PaperRule(thickness: base >= 28 ? 3 : 2, space: base * 0.4);
    final shopName = s.shopName.trim();

    return MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: ColoredBox(
          color: _paper,
          child: DefaultTextStyle(
            style: body,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    shopName.isEmpty ? fallbackShopName : shopName,
                    textAlign: TextAlign.center,
                    style: bold.copyWith(fontSize: base * 1.2, height: 1.25),
                  ),
                  rule,
                  Text(arabic.printerTestSlipTitle, textAlign: TextAlign.center),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: bold,
                  ),
                  rule,
                  Text(
                    '${s.printableDots} dots · '
                    '${formatInvoiceDateTime(printedAt, locale: 'en')}',
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
