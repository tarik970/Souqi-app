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
  static const setupDone = 'setup_done';
  static const shopName = 'shop_name';

  /// The logo as a base64 PNG, already downscaled. Kept in the database (not
  /// as a loose file) so it travels with backup/restore.
  static const shopLogoBase64 = 'shop_logo_base64';

  // Paper / printer geometry. Millimetre values are decimal text ("3.5").
  static const paperWidthMm = 'paper_width_mm';
  static const printerDpi = 'printer_dpi';
  static const sideMarginMm = 'side_margin_mm';
  static const printableDotsOverride = 'printable_dots_override'; // '' = computed
  static const feedLines = 'feed_lines';
  static const cutPaper = 'cut_paper';
  static const printerMac = 'printer_mac';
  static const printerName = 'printer_name';

  // Invoice content.
  static const baseFontSize = 'base_font_size';
  static const headerText = 'header_text';
  static const footerText = 'footer_text';
  static const showItemCode = 'show_item_code';
  static const showUnit = 'show_unit';
  static const showUnitPrice = 'show_unit_price';
  static const showDateTime = 'show_date_time';
  static const showInvoiceNumber = 'show_invoice_number';
  static const showCustomerName = 'show_customer_name';
  static const showCustomerPhone = 'show_customer_phone';
  static const showAccountNumber = 'show_account_number';
  static const maskAccountNumber = 'mask_account_number';
  static const showPoweredBy = 'show_powered_by'; // one text line, no image
  static const currencyDisplay = 'currency_display'; // SYMBOL / CODE
  static const extraTotalCurrencies = 'extra_total_currencies'; // JSON list, max 2

  // Output / sharing.
  static const outputMode = 'output_mode'; // PRINT / SHARE / BOTH
  static const shareWidthMm = 'share_width_mm'; // '' = same as the paper
  static const defaultCountryCode = 'default_country_code';

  // Selling ("type-to-sell").
  /// An item typed during a sale becomes a product when the invoice is saved.
  static const saveNewItemsAsProducts = 'save_new_items_as_products';

  /// A unit price changed during a sale becomes the product's saved price.
  static const updateProductPriceFromSales = 'update_product_price_from_sales';

  /// The favorites bar is topped up with the best sellers of the last 30 days.
  static const autoFavorites = 'auto_favorites';

  /// Unit of the last new item typed into a sale: a unit id, '0' for
  /// "no unit", '' until the first one (then the preset "piece").
  static const lastNewItemUnitId = 'last_new_item_unit_id';

  // Archive / security.
  static const autoDeleteDays = 'auto_delete_days'; // '0' = off

  /// Epoch milliseconds of the last retention sweep. The sweep runs on app
  /// start at most once a day, and this is what 'already today' is read from.
  static const autoDeleteLastRunAt = 'auto_delete_last_run_at';
  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt';

  // Customers / renewals.
  /// The "due in the next N days" window of the due-for-renewal list.
  static const dueSoonDays = 'due_soon_days';

  /// The WhatsApp renewal reminder. '' = the built-in text in the invoice
  /// language (Arabic or English).
  static const renewalReminderText = 'renewal_reminder_text';

  /// Defaults applied when a key is missing from the table.
  static const Map<String, String> defaults = {
    baseCurrencyCode: 'SYP',
    appLanguage: 'ar',
    invoiceLanguage: 'ar',
    shopType: 'GROCERY',
    setupDone: '0',
    shopName: '',
    shopLogoBase64: '',
    paperWidthMm: '80',
    printerDpi: '203',
    // 80 mm paper has a 72 mm print head: with the brief's formula
    // round((80 - 2 × 3.5) × 203 / 25.4) = 583 → 576 dots. A 4 mm margin
    // would land on 575 → 568 because 203 dpi is slightly under 8 dots/mm.
    sideMarginMm: '3.5',
    printableDotsOverride: '',
    feedLines: '3',
    cutPaper: '0',
    printerMac: '',
    printerName: '',
    baseFontSize: '22',
    headerText: '',
    footerText: '',
    showItemCode: '0',
    showUnit: '1',
    showUnitPrice: '1',
    showDateTime: '1',
    showInvoiceNumber: '1',
    showCustomerName: '1',
    showCustomerPhone: '1',
    showAccountNumber: '1',
    maskAccountNumber: '0',
    showPoweredBy: '1',
    currencyDisplay: 'SYMBOL',
    extraTotalCurrencies: '[]',
    outputMode: 'PRINT',
    shareWidthMm: '',
    defaultCountryCode: '963',
    saveNewItemsAsProducts: '1',
    updateProductPriceFromSales: '1',
    autoFavorites: '1',
    lastNewItemUnitId: '',
    autoDeleteDays: '0',
    autoDeleteLastRunAt: '0',
    dueSoonDays: '3',
    renewalReminderText: '',
  };
}
