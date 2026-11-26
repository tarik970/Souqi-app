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

  // Printer compatibility (the printer diagnostics screen).
  /// The command language of each printer ever chosen, as a JSON object
  /// `{"<MAC address>": "ESCPOS" | "TSPL"}` — remembered per printer, so
  /// going back to an earlier printer brings its language back with it.
  static const printerLanguages = 'printer_languages';

  /// The calibration of each printer, the same way: a JSON object
  /// `{"<MAC address>": <dots>}` — how far the print is moved to the right
  /// (negative = left), a multiple of 8 within ±64. Missing = 0.
  static const printerOffsets = 'printer_offsets';

  /// How the picture is sent in ESC/POS: GS_V0 / ESC_STAR / GS_L.
  static const escPosImageMode = 'escpos_image_mode';

  /// Bytes written to the printer at a time (1024 / 512 / 256) and the
  /// pause between two writes in milliseconds (12 / 30 / 60).
  static const printChunkSize = 'print_chunk_size';
  static const printChunkDelayMs = 'print_chunk_delay_ms';

  /// '1' for the few TSPL firmwares where a 1 bit in BITMAP data is a black
  /// dot (the label test comes out white on black without it).
  static const tsplOneIsBlack = 'tspl_one_is_black';

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

  // Debt lines on the invoice (only for a sale that left a debt or used a
  // credit balance; the two balances only with a customer attached).
  static const showPaidAmount = 'show_paid_amount';
  static const showRemainingAmount = 'show_remaining_amount';
  static const showPreviousBalance = 'show_previous_balance';
  static const showNewBalance = 'show_new_balance';
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

  /// Show the small "cash received" field under the total on the sale
  /// screen (it works out the change to give back). Off by default.
  static const showCashReceived = 'show_cash_received';

  /// Unit of the last new item typed into a sale: a unit id, '0' for
  /// "no unit", '' until the first one (then the preset "piece").
  static const lastNewItemUnitId = 'last_new_item_unit_id';

  // Archive / security.
  static const autoDeleteDays = 'auto_delete_days'; // '0' = off

  /// Epoch milliseconds of the last retention sweep. The sweep runs on app
  /// start at most once a day, and this is what 'already today' is read from.
  static const autoDeleteLastRunAt = 'auto_delete_last_run_at';
  /// `pbkdf2-sha256$<iterations>$<base64>`; '' = no PIN. See `pin_hash.dart`.
  static const pinHash = 'pin_hash';
  static const pinSalt = 'pin_salt'; // base64

  /// Wrong PIN attempts in a row, and the epoch milliseconds a lock-out ends
  /// at. In the database, so closing the app does not reset the count.
  static const pinFailedAttempts = 'pin_failed_attempts';
  static const pinLockedUntil = 'pin_locked_until';

  /// The one-time recovery code made with every new PIN, stored like the PIN
  /// itself: a salted hash, never the code. '' = none. Wrong recovery
  /// attempts have their own counter and lock-out, with the PIN's rules.
  static const pinRecoveryHash = 'pin_recovery_hash';
  static const pinRecoverySalt = 'pin_recovery_salt'; // base64
  static const pinRecoveryFailedAttempts = 'pin_recovery_failed_attempts';
  static const pinRecoveryLockedUntil = 'pin_recovery_locked_until';

  /// '1' once a PIN prompt has offered "create a recovery code now" to a PIN
  /// that has none (one chosen before recovery codes existed). The offer on
  /// the prompt is made once; the banner in the settings stays until a code
  /// exists.
  static const pinRecoveryOfferShown = 'pin_recovery_offer_shown';

  // Prepaid card codes on the invoice.
  /// Print a QR code of each sold card code under its digits.
  static const printCodeQr = 'print_code_qr';

  /// Print every sold card on its own slip (feed / cut between slips)
  /// instead of on the invoice itself.
  static const codesOnSeparateSlips = 'codes_on_separate_slips';

  // Customers / renewals.
  /// The "due in the next N days" window of the due-for-renewal list.
  static const dueSoonDays = 'due_soon_days';

  /// The WhatsApp renewal reminder. '' = the built-in text in the invoice
  /// language (Arabic or English).
  static const renewalReminderText = 'renewal_reminder_text';

  /// Minutes without a touch after which everything the PIN opened locks
  /// again: 1, 5 or 15. (It also locks at once when the app goes to the
  /// background.)
  static const pinAutoLockMinutes = 'pin_auto_lock_minutes';

  // Debt ledger.
  /// Days a new debt is given before it counts as overdue, for a customer
  /// without due days of their own.
  static const debtDefaultDueDays = 'debt_default_due_days';

  /// Ask for the PIN before the debtors list and a customer's account open.
  static const debtRequirePin = 'debt_require_pin';

  /// The WhatsApp debt reminder. '' = the built-in text in the invoice
  /// language (Arabic or English).
  static const debtReminderText = 'debt_reminder_text';

  // The daily debt report (phase 4e). Its STATUS (last run, outcome) is not
  // here: the background job keeps it on the Android side, see
  // `ReportPlatform.saveStatus`.
  static const debtReportEnabled = 'debt_report_enabled';

  /// Minutes after midnight, local time (1320 = 22:00).
  static const debtReportMinute = 'debt_report_minute';

  /// Comma-separated: XLSX, PDF. Never empty.
  static const debtReportFormats = 'debt_report_formats';

  /// The Storage Access Framework tree chosen with the folder picker, its
  /// name and kind (PHONE / REMOVABLE / CLOUD / OTHER). '' = Downloads.
  static const debtReportFolderUri = 'debt_report_folder_uri';
  static const debtReportFolderName = 'debt_report_folder_name';
  static const debtReportFolderKind = 'debt_report_folder_kind';

  /// How many days of reports stay in the folder.
  static const debtReportKeepDays = 'debt_report_keep_days';
  static const debtReportNotify = 'debt_report_notify';

  /// Epoch milliseconds of the last time the report was turned on; the
  /// catch-up rule owes no report from before it.
  static const debtReportEnabledAt = 'debt_report_enabled_at';

  // Backup (phase 5). The daily automatic backup is a second output of the
  // daily job above: same time, same folder, its own on/off and keep-N. Its
  // PASSWORD is not here — only a key derived from it, in the Keystore
  // (`autoBackupKeyName`): a backup must never carry what opens it.
  static const backupAutoEnabled = 'backup_auto_enabled';
  static const backupAutoKeepDays = 'backup_auto_keep_days';

  /// Epoch milliseconds; like [debtReportEnabledAt] for the catch-up rule.
  static const backupAutoEnabledAt = 'backup_auto_enabled_at';

  /// Epoch milliseconds of the last backup made in the app (by hand) or
  /// restored — for the "no backup for 7 days" reminder. The daily backup,
  /// made by the background engine that only reads the database, keeps its
  /// date in the job status instead.
  static const backupLastAt = 'backup_last_at';

  // Licensing (phase 5b). Neither key has a default: absent = none. Both are
  // COPIES — the Keystore holds the same (`LicenseStore`) — kept here so a
  // Keystore that loses its entries does not lose the activation.
  /// The activation code of THIS device. It is signed for one device hash,
  /// so a copy on another phone is worth nothing — and it never travels: a
  /// backup leaves it out and a restore keeps the phone's own
  /// ([deviceBoundKeys]).
  static const licenseCode = 'license_code';

  /// JSON: when the trial began (and the invoice counter then), the latest
  /// time ever seen (the clock guard), the newest license ever activated and
  /// the PIN reset codes already used. This one DOES travel with a backup:
  /// a trial that is used up stays used up after a restore.
  static const licenseState = 'license_state';

  /// Settings that belong to the DEVICE, not to the shop's data: a backup
  /// does not carry them and a restore does not replace them.
  static const List<String> deviceBoundKeys = [licenseCode];

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
    // 80 mm paper prints 512 dots by default: with the brief's formula
    // round((80 - 2 × 7.5) × 203 / 25.4) = 519 → 512 dots. The whole 72 mm
    // head (3.5 mm → 576 dots) was cut off on a real printer; see
    // defaultSideMargin80Mm in print_geometry.dart, which this must match.
    // An 8 mm margin would land on 511 → 504, because 203 dpi is slightly
    // under 8 dots/mm.
    sideMarginMm: '7.5',
    printableDotsOverride: '',
    feedLines: '3',
    cutPaper: '0',
    printerMac: '',
    printerName: '',
    printerLanguages: '{}',
    printerOffsets: '{}',
    escPosImageMode: 'GS_V0',
    printChunkSize: '1024',
    printChunkDelayMs: '12',
    tsplOneIsBlack: '0',
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
    showPaidAmount: '1',
    showRemainingAmount: '1',
    showPreviousBalance: '0',
    showNewBalance: '0',
    currencyDisplay: 'SYMBOL',
    extraTotalCurrencies: '[]',
    outputMode: 'PRINT',
    shareWidthMm: '',
    defaultCountryCode: '963',
    saveNewItemsAsProducts: '1',
    updateProductPriceFromSales: '1',
    autoFavorites: '1',
    showCashReceived: '0',
    lastNewItemUnitId: '',
    autoDeleteDays: '0',
    autoDeleteLastRunAt: '0',
    pinHash: '',
    pinSalt: '',
    pinFailedAttempts: '0',
    pinLockedUntil: '0',
    pinRecoveryHash: '',
    pinRecoverySalt: '',
    pinRecoveryFailedAttempts: '0',
    pinRecoveryLockedUntil: '0',
    pinRecoveryOfferShown: '0',
    printCodeQr: '0',
    codesOnSeparateSlips: '0',
    dueSoonDays: '3',
    renewalReminderText: '',
    pinAutoLockMinutes: '5',
    debtDefaultDueDays: '30',
    debtRequirePin: '0',
    debtReminderText: '',
    debtReportEnabled: '0',
    debtReportMinute: '1320',
    debtReportFormats: 'XLSX,PDF',
    debtReportFolderUri: '',
    debtReportFolderName: '',
    debtReportFolderKind: '',
    debtReportKeepDays: '30',
    debtReportNotify: '1',
    debtReportEnabledAt: '0',
    backupAutoEnabled: '0',
    backupAutoKeepDays: '7',
    backupAutoEnabledAt: '0',
    backupLastAt: '0',
  };
}
