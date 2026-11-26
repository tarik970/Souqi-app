/// Where a shop reaches the developer.
library;

/// The developer's WhatsApp number as it is written on a card:
/// "+963 9XX XXX XXX". With a real number here, "Send on WhatsApp" on the
/// activation screen opens that chat directly with the request code already
/// typed.
///
/// STILL A PLACEHOLDER: the X's stand for digits that have not been filled
/// in. Until they are, [developerWhatsAppNumber] is empty and WhatsApp opens
/// for the shop to choose the chat itself — exactly as with no number at
/// all. Replace the X's with the real digits; nothing else has to change.
const String developerWhatsApp = '+963XXXXXXXXX';

/// [developerWhatsApp] in the form WhatsApp takes — international, digits
/// only ("9639XXXXXXXX") — or '' when it is not a usable number: empty,
/// still holding placeholder letters, or too short to be a phone number.
/// A '+', spaces and dashes in the constant are fine.
String get developerWhatsAppNumber => whatsAppNumberOf(developerWhatsApp);

/// See [developerWhatsAppNumber].
String whatsAppNumberOf(String written) {
  final compact = written.replaceAll(RegExp(r'[\s\-()]'), '');
  final digits = compact.startsWith('+') ? compact.substring(1) : compact;
  return RegExp(r'^[1-9][0-9]{7,14}$').hasMatch(digits) ? digits : '';
}
