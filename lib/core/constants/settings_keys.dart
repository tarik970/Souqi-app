/// Keys for the `settings` table, with code-level defaults.
///
/// Only `base_currency_code`, `app_language` and `invoice_language` are
/// seeded into the database by migration v1; every other key falls back to
/// [defaults] until the user changes it.
library;

abstract final class SettingsKeys {
  static const baseCurrencyCode = 'base_currency_code';
  static const appLanguage = 'app_language';
  static const invoiceLanguage = 'invoice_language';
  static const shopType = 'shop_type'; // GROCERY / CARDS / BOTH
  static const shopName = 'shop_name';
  static const shopLogoBase64 = 'shop_logo_base64';

  // Invoice / printer settings.
  static const paperWidthMm = 'paper_width_mm';
  static const printerDpi = 'printer_dpi';
  static const marginLeftMm = 'margin_left_mm';
  static const marginRightMm = 'margin_right_mm';
  static const baseFontSize = 'base_font_size';
  static const headerText = 'header_text';
  static const footerText = 'footer_text';
  static const showItemCode = 'show_item_code';
  static const showUnit = 'show_unit';
  static const showUnitPrice = 'show_unit_price';
  static const showDateTime = 'show_date_time';
  static const showInvoiceNumber = 'show_invoice_number';
  static const extraTotalCurrencies = 'extra_total_currencies'; // JSON list, max 2
  static const maskAccountNumber = 'mask_account_number';
  static const printerMac = 'printer_mac';
  static const printerName = 'printer_name';

  // Archive / security.
  static const autoDeleteDays = 'auto_delete_days'; // '0' = off
  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt';

  /// Defaults applied when a key is missing from the table.
  static const Map<String, String> defaults = {
    baseCurrencyCode: 'SYP',
    appLanguage: 'ar',
    invoiceLanguage: 'ar',
    shopType: 'GROCERY',
    shopName: '',
    paperWidthMm: '80',
    printerDpi: '203',
    marginLeftMm: '0',
    marginRightMm: '0',
    baseFontSize: '22',
    headerText: '',
    footerText: '',
    showItemCode: '0',
    showUnit: '1',
    showUnitPrice: '1',
    showDateTime: '1',
    showInvoiceNumber: '1',
    extraTotalCurrencies: '[]',
    maskAccountNumber: '0',
    autoDeleteDays: '0',
  };
}
