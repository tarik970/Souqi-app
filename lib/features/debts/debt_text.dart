/// The words of the debt ledger, as plain strings. No widgets here, so the
/// wording rules are unit-tested directly and shared by the screens, the
/// receipt, the statement and the WhatsApp reminder.
library;

import 'dart:ui' show Locale;

import '../../core/money/money_format.dart';
import '../../domain/models/debt.dart';
import '../../l10n/generated/app_localizations.dart';
import '../customers/reminder_text.dart' show formatReminderDate;

/// A balance in words: "عليه 5,000 ل.س" (the customer owes), "له 2,000 ل.س"
/// (the shop owes the customer), or "no balance". [money] formats the
/// absolute amount.
String balanceInWords(
  AppLocalizations l10n,
  int balanceBaseMinor,
  String Function(int minor) money,
) {
  if (balanceBaseMinor > 0) return l10n.balanceOwes(money(balanceBaseMinor));
  if (balanceBaseMinor < 0) return l10n.balanceCredit(money(-balanceBaseMinor));
  return l10n.balanceSettled;
}

/// What a ledger line is, in a few words: "فاتورة 152", "سند قبض 37",
/// "رصيد افتتاحي"… A reversal says what it cancels.
String describeEntry(
  AppLocalizations l10n,
  DebtEntry entry, {
  required String locale,
}) {
  String number(int value) => localizeDigits('$value', locale);
  String of(DebtEntryType type, {int? invoiceNo, int? receiptNo}) =>
      switch (type) {
        DebtEntryType.debt => invoiceNo == null
            ? l10n.entryManualDebt
            : l10n.entryInvoice(number(invoiceNo)),
        DebtEntryType.manualDebt => l10n.entryManualDebt,
        DebtEntryType.payment => receiptNo == null
            ? l10n.entryPayment
            : l10n.entryReceipt(number(receiptNo)),
        DebtEntryType.openingBalance => l10n.openingBalance,
        DebtEntryType.adjustment => l10n.adjustment,
        DebtEntryType.reversal => l10n.reverseEntry,
      };

  if (entry.isReversal) {
    final reversed = entry.reversedType;
    if (reversed == null) return l10n.reverseEntry;
    return l10n.entryReversalOf(of(
      reversed,
      invoiceNo: entry.reversedInvoiceNo,
      receiptNo: entry.reversedReceiptNo,
    ));
  }
  return of(entry.type, invoiceNo: entry.invoiceNo, receiptNo: entry.receiptNo);
}

/// For a REVERSAL: what the entry it cancels is called ("سند قبض 37") —
/// the text of the link from a reversal back to its original.
String describeReversedOriginal(
  AppLocalizations l10n,
  DebtEntry reversal, {
  required String locale,
}) {
  final type = reversal.reversedType;
  if (type == null) return l10n.reverseEntry;
  return describeEntry(
    l10n,
    DebtEntry(
      id: reversal.reversesId ?? 0,
      customerId: reversal.customerId,
      type: type,
      direction: -reversal.direction,
      amountBaseMinor: reversal.amountBaseMinor,
      invoiceNo: reversal.reversedInvoiceNo,
      receiptNo: reversal.reversedReceiptNo,
      createdAt: reversal.createdAt,
      recordedAt: reversal.recordedAt,
    ),
    locale: locale,
  );
}

String paymentMethodLabel(AppLocalizations l10n, PaymentMethod method) =>
    switch (method) {
      PaymentMethod.cash => l10n.methodCash,
      PaymentMethod.transfer => l10n.methodTransfer,
      PaymentMethod.other => l10n.methodOther,
    };

String agingBucketLabel(AppLocalizations l10n, AgingBucket bucket) =>
    switch (bucket) {
      AgingBucket.current => l10n.aging0to30,
      AgingBucket.days31to60 => l10n.aging31to60,
      AgingBucket.days61to90 => l10n.aging61to90,
      AgingBucket.over90 => l10n.agingOver90,
    };

// ---- The WhatsApp reminder -----------------------------------------------

/// The placeholders a debt reminder may contain, in the order the settings
/// dialog lists them.
const List<String> debtReminderPlaceholders = [
  '{name}',
  '{balance}',
  '{shop}',
  '{last_payment_date}',
];

/// The built-in reminder in [language] ('ar' / 'en'), with its placeholders
/// still in it — what the settings dialog shows until the shop writes its
/// own, and what "Use default" goes back to.
String defaultDebtReminderTemplate(String language) =>
    lookupAppLocalizations(Locale(language == 'en' ? 'en' : 'ar'))
        .debtReminderDefaultText(
      '{name}',
      '{shop}',
      '{balance}',
      '{last_payment_date}',
    );

/// Fills [template] for one customer. An empty [template] means the default
/// for [language]. [balance] is the amount already formatted with its
/// currency.
///
/// A placeholder with nothing to say takes its whole sentence with it when
/// it stood alone in one ("Last payment: ." is not a thing to send), and is
/// otherwise simply removed.
String buildDebtReminderText({
  required String template,
  required String name,
  required String balance,
  required String language,
  String shopName = '',
  DateTime? lastPaymentAt,
}) {
  final values = <String, String>{
    '{name}': name.trim(),
    '{balance}': balance.trim(),
    '{shop}': shopName.trim(),
    '{last_payment_date}': lastPaymentAt == null
        ? ''
        : formatReminderDate(lastPaymentAt, language: language),
  };
  var text = template.trim().isEmpty
      ? defaultDebtReminderTemplate(language)
      : template;
  for (final entry in values.entries) {
    if (entry.value.isEmpty) {
      // "…. Last payment: {x}. …" → the sentence goes with the placeholder.
      final sentence = RegExp(
        '[^.!؟?\\n]*:\\s*${RegExp.escape(entry.key)}\\s*[.!]?',
      );
      text = text.replaceAll(sentence, '');
      // "a reminder from {shop}:" → "a reminder:".
      text = text.replaceAll(
        RegExp('\\s+(from|من)\\s+${RegExp.escape(entry.key)}'),
        '',
      );
    }
    text = text.replaceAll(entry.key, entry.value);
  }
  return text
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .replaceAll(RegExp(' {2,}'), ' ')
      .replaceAllMapped(RegExp(r' +([.,،:])'), (match) => match[1]!)
      .trim();
}
