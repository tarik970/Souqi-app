import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/utils/normalize.dart';
import '../../domain/models/customer.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';
import 'customers_providers.dart';
import 'reminder_text.dart';

/// Both WhatsApp and WhatsApp Business are installed: asks which one.
/// Returns the chosen package name, or null when dismissed.
Future<String?> askWhatsAppPackage(
  BuildContext context,
  List<String> packages,
) {
  final l10n = AppLocalizations.of(context);
  return showDialog<String>(
    context: context,
    builder: (context) => SimpleDialog(
      key: const ValueKey('whatsapp-package-dialog'),
      title: Text(l10n.whatsAppChooseTitle),
      children: [
        for (final package in packages)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(package),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(package == whatsAppBusinessPackage
                  ? l10n.whatsAppBusiness
                  : l10n.whatsAppRegular),
            ),
          ),
      ],
    ),
  );
}

void _snack(ScaffoldMessengerState messenger, String message) {
  if (!messenger.mounted) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Opens the phone's dialer on the customer's number. Works with no
/// network: it is the phone that calls, not the app.
Future<void> callCustomer(BuildContext context, String phone) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  // Everything is taken from the context before the first await.
  final bridge = ProviderScope.containerOf(context, listen: false)
      .read(nativeBridgeProvider);
  var opened = false;
  try {
    opened = await bridge.dial(phone.trim());
  } on OutputException {
    opened = false;
  }
  if (!opened) _snack(messenger, l10n.cannotDial);
}

/// Opens the customer's WhatsApp chat, with [text] already typed into the
/// message box when given. Nothing is sent by the app: the seller reads the
/// message, edits it if needed and presses send in WhatsApp.
///
/// The number is completed with the default country code the same way the
/// invoice "Send on WhatsApp" button does it.
Future<void> openCustomerChat(
  BuildContext context, {
  required String phone,
  String? text,
}) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final container = ProviderScope.containerOf(context, listen: false);
  final bridge = container.read(nativeBridgeProvider);

  final countryCode = await container.read(defaultCountryCodeProvider.future);
  final international =
      toInternationalPhone(phone, defaultCountryCode: countryCode);
  if (international == null) {
    _snack(messenger, l10n.invalidPhone);
    return;
  }

  List<String> packages;
  try {
    packages = await bridge.whatsAppPackages();
  } on OutputException {
    packages = const [];
  }
  if (packages.isEmpty) {
    _snack(messenger, l10n.whatsAppChatNotInstalled);
    return;
  }
  var package = packages.first;
  if (packages.length > 1) {
    if (!context.mounted) return;
    final picked = await askWhatsAppPackage(context, packages);
    if (picked == null) return;
    package = picked;
  }

  var opened = false;
  try {
    opened = await bridge.openWhatsAppChat(
      package: package,
      internationalPhone: international,
      text: text,
    );
  } on OutputException {
    opened = false;
  }
  if (!opened) _snack(messenger, l10n.whatsAppChatFailed);
}

/// The due list's reminder button: opens the customer's chat with the
/// reminder text (the shop's own, or the default in the invoice language)
/// filled in for this account.
Future<void> sendRenewalReminder(BuildContext context, CustomerHit hit) async {
  final phone = hit.customer.phone;
  if (phone == null || phone.trim().isEmpty) return;
  final container = ProviderScope.containerOf(context, listen: false);
  final settings = await container.read(invoiceSettingsProvider.future);
  final template = await container.read(reminderTemplateProvider.future);
  if (!context.mounted) return;
  await openCustomerChat(
    context,
    phone: phone,
    text: buildReminderText(
      template: template,
      hit: hit,
      language: settings.language,
      shopName: settings.shopName,
    ),
  );
}
