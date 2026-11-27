/// The two optional blocks a shop can add to its papers: the payment QR
/// ("رمز الدفع") and the contact numbers. Both are invoice settings, stored
/// in the `settings` table with the rest (see [SettingsKeys]), so backups
/// carry them.
library;

import 'dart:convert';

/// Which invoices print the payment QR.
enum PaymentQrWhen {
  /// Every invoice (the default).
  always('ALWAYS'),

  /// Only an invoice that leaves something to pay: a sale on credit or
  /// partly paid.
  unpaidOnly('UNPAID');

  const PaymentQrWhen(this.db);

  final String db;

  static PaymentQrWhen fromDb(String? value) =>
      values.firstWhere((w) => w.db == value, orElse: () => PaymentQrWhen.always);
}

/// Where the contact numbers are printed.
enum ContactsPosition {
  /// Under the shop name and header text (the default).
  header('HEADER'),

  /// Just above the footer text.
  footer('FOOTER');

  const ContactsPosition(this.db);

  final String db;

  static ContactsPosition fromDb(String? value) => values
      .firstWhere((p) => p.db == value, orElse: () => ContactsPosition.header);
}

/// One contact line: "أبو أحمد: 0944 123 456". The phone is kept exactly as
/// typed (Arabic-Indic digits included); it is normalised only when printed.
class InvoiceContact {
  const InvoiceContact({this.name = '', required this.phone});

  final String name;
  final String phone;

  /// A paper holds at most this many.
  static const int max = 3;

  Map<String, String> toJson() => {'name': name, 'phone': phone};

  @override
  bool operator ==(Object other) =>
      other is InvoiceContact && other.name == name && other.phone == phone;

  @override
  int get hashCode => Object.hash(name, phone);

  /// The stored list; anything unreadable is dropped, never thrown.
  static List<InvoiceContact> listFromJson(String raw) {
    if (raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map &&
              item['phone'] is String &&
              (item['phone'] as String).trim().isNotEmpty)
            InvoiceContact(
              name: item['name'] is String ? (item['name'] as String).trim() : '',
              phone: (item['phone'] as String).trim(),
            ),
      ].take(max).toList(growable: false);
    } on FormatException {
      return const [];
    }
  }

  static String listToJson(List<InvoiceContact> contacts) =>
      jsonEncode([for (final c in contacts.take(max)) c.toJson()]);
}
