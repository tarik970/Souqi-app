/// The WhatsApp renewal reminder, as plain text. No widgets, so the wording
/// rules are unit-tested directly.
library;

import 'dart:ui' show Locale;

import '../../core/money/money_format.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';

/// The placeholders a reminder may contain, in the order the settings
/// dialog lists them. Square brackets, so they are easy to type on a phone
/// keyboard in either language.
const List<String> reminderPlaceholders = [
  '[name]',
  '[account]',
  '[provider]',
  '[package]',
  '[date]',
  '[shop]',
];

/// The built-in reminder in [language] ('ar' / 'en'), with its placeholders
/// still in it — what the settings dialog shows until the shop writes its
/// own, and what "Use default" goes back to.
String defaultReminderTemplate(String language) =>
    lookupAppLocalizations(Locale(language == 'en' ? 'en' : 'ar'))
        .reminderDefaultText('[name]', '[account]', '[date]');

/// "2026/12/01": numeric, the same shape in every language, only the digit
/// shapes follow [language].
String formatReminderDate(DateTime day, {required String language}) {
  final t = day.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return localizeDigits('${t.year}/${two(t.month)}/${two(t.day)}', language);
}

/// Fills [template] for one account. An empty [template] means the default
/// for [language]. Placeholders with nothing to say (no provider, no due
/// date) are simply removed.
String buildReminderText({
  required String template,
  required CustomerHit hit,
  required String language,
  String shopName = '',
}) {
  final account = hit.account;
  final dueDay = account?.nextDueAt;
  final values = <String, String>{
    '[name]': hit.customer.name.trim(),
    '[account]': account?.accountNumber.trim() ?? '',
    '[provider]': account?.provider?.trim() ?? '',
    '[package]': hit.packageName?.trim() ?? '',
    '[date]':
        dueDay == null ? '' : formatReminderDate(dueDay, language: language),
    '[shop]': shopName.trim(),
  };
  var text =
      template.trim().isEmpty ? defaultReminderTemplate(language) : template;
  for (final entry in values.entries) {
    text = text.replaceAll(entry.key, entry.value);
  }
  // An empty placeholder leaves "()" or a doubled space behind.
  return text
      .replaceAll(RegExp(r'\(\s*\)'), '')
      .replaceAll(RegExp(' {2,}'), ' ')
      .replaceAllMapped(RegExp(r' +([.,،])'), (match) => match[1]!)
      .trim();
}
