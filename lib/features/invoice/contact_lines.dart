import 'package:flutter/widgets.dart';

import '../../core/money/money_format.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/invoice_extras.dart';

/// [phone] as it is printed: Arabic-Indic or Persian digits typed by the
/// shop become the digits of the INVOICE language (the same digits its
/// invoice number and amounts use); spaces, "+" and dashes stay where they
/// were typed.
String contactPhoneForPaper(String phone, String language) {
  final out = StringBuffer();
  for (final char in normalizeDigits(phone.trim()).split('')) {
    final unit = char.codeUnitAt(0);
    out.write(unit >= 0x30 && unit <= 0x39 ? localizeDigits(char, language) : char);
  }
  return out.toString();
}

/// The shop's contact numbers, one centred line each: "أبو أحمد: 0944 123
/// 456". The name and the number are two separate text runs and the number
/// is laid out left to right, so its digits keep their order inside an
/// Arabic line, and a narrow paper wraps between the two, not inside the
/// number.
class PaperContactLines extends StatelessWidget {
  const PaperContactLines({
    super.key,
    required this.contacts,
    required this.language,
    required this.gap,
  });

  final List<InvoiceContact> contacts;

  /// The INVOICE language.
  final String language;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('paper-contacts'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < contacts.length; i++)
          Wrap(
            key: ValueKey('paper-contact-$i'),
            alignment: WrapAlignment.center,
            spacing: gap * 0.5,
            children: [
              if (contacts[i].name.trim().isNotEmpty)
                Text('${contacts[i].name.trim()}:'),
              Text(
                contactPhoneForPaper(contacts[i].phone, language),
                key: ValueKey('paper-contact-phone-$i'),
                textDirection: TextDirection.ltr,
              ),
            ],
          ),
      ],
    );
  }
}
