/// Where a shop reaches the developer.
library;

/// The developer's WhatsApp number as it is written on a card, in
/// international form: "+963 9XX XXX XXX". "Send on WhatsApp" on the
/// activation screen opens that chat directly, with the request code already
/// typed.
///
/// To change it, write the new number here; nothing else has to change. A
/// value that is not a usable number — empty, or with letters left in it
/// like the X's above — leaves [developerWhatsAppNumber] empty, and WhatsApp
/// then opens for the shop to choose the chat itself.
const String developerWhatsApp = '+963962080317';

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
