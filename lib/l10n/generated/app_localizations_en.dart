// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Souqi';

  @override
  String get navSale => 'Sale';

  @override
  String get navProducts => 'Products';

  @override
  String get navArchive => 'Archive';

  @override
  String get navStats => 'Statistics';

  @override
  String get navSettings => 'Settings';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get fieldRequired => 'This field is required';

  @override
  String get activeLabel => 'Active';

  @override
  String get setupWelcome => 'Welcome to Souqi';

  @override
  String get setupIntro =>
      'Choose the app language and your shop type. You can change both later in Settings.';

  @override
  String get setupLanguage => 'App language';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get setupShopType => 'Shop type';

  @override
  String get shopTypeGrocery => 'Grocery';

  @override
  String get shopTypeCards => 'Cards & subscriptions';

  @override
  String get shopTypeBoth => 'Both';

  @override
  String get setupStart => 'Start';

  @override
  String get searchProductsHint => 'Search by name or code';

  @override
  String get filterAll => 'All';

  @override
  String get filterGoods => 'Goods';

  @override
  String get filterServices => 'Cards & services';

  @override
  String get addProduct => 'Add product';

  @override
  String get editProduct => 'Edit product';

  @override
  String get productName => 'Name';

  @override
  String get productCode => 'Code (optional)';

  @override
  String get productCodeTaken => 'This code is already used';

  @override
  String get productKind => 'Type';

  @override
  String get kindGoods => 'Goods';

  @override
  String get kindService => 'Card / service';

  @override
  String get productUnit => 'Unit';

  @override
  String get productPrice => 'Price';

  @override
  String get invalidPrice => 'Invalid price';

  @override
  String get productCurrency => 'Price currency';

  @override
  String get favoriteLabel => 'Favorite';

  @override
  String get requiresAccount => 'Requires customer account';

  @override
  String get requiresAccountHint =>
      'A sale of this item must be linked to a customer\'s card or account number';

  @override
  String get showInactive => 'Show inactive';

  @override
  String get inactiveBadge => 'Inactive';

  @override
  String get deleteProductTitle => 'Delete product?';

  @override
  String deleteProductMessage(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get productDeactivatedMessage =>
      'This product is used in invoices or as an account\'s default package, so it was deactivated instead of deleted.';

  @override
  String get noProducts => 'No products yet';

  @override
  String get unitsTitle => 'Units';

  @override
  String get addUnit => 'Add unit';

  @override
  String get editUnit => 'Edit unit';

  @override
  String get unitName => 'Unit name';

  @override
  String get presetBadge => 'Preset';

  @override
  String get deleteUnitTitle => 'Delete unit?';

  @override
  String deleteUnitMessage(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String unitInUse(int count) {
    return 'Cannot delete: $count product(s) use this unit';
  }

  @override
  String get settingsCurrencies => 'Currencies & exchange rates';

  @override
  String get showPoweredBy => 'Show \"Powered by Souqi\" on invoices';

  @override
  String get poweredByFooter => 'Powered by Souqi';

  @override
  String get aboutTitle => 'About Souqi';

  @override
  String get aboutTagline => 'Souqi — Sales & invoicing system';

  @override
  String versionLabel(String version) {
    return 'Version $version';
  }

  @override
  String get currenciesTitle => 'Currencies';

  @override
  String get addCurrency => 'Add currency';

  @override
  String get editCurrency => 'Edit currency';

  @override
  String get currencyCode => 'Code (e.g. USD)';

  @override
  String get currencyCodeExists => 'This code already exists';

  @override
  String get currencyNameAr => 'Arabic name';

  @override
  String get currencyNameEn => 'English name';

  @override
  String get currencySymbol => 'Symbol';

  @override
  String get currencyDecimals => 'Decimal places';

  @override
  String get exchangeRate => 'Exchange rate';

  @override
  String rateHint(String code, String base) {
    return '1 $code = ? $base';
  }

  @override
  String rateDisplay(String code, String value, String base) {
    return '1 $code = $value $base';
  }

  @override
  String get invalidRate => 'Invalid exchange rate';

  @override
  String rateUpdatedAt(String date) {
    return 'Rate updated: $date';
  }

  @override
  String get rateNeverUpdated => 'Rate not set yet';

  @override
  String get updateRate => 'Update rate';

  @override
  String get baseBadge => 'Base';

  @override
  String get setAsBase => 'Set as base currency';

  @override
  String get baseChangeTitle => 'Change base currency?';

  @override
  String baseChangeWarning(String code) {
    return 'All totals and statistics use the base currency. Exchange rates of the other currencies must be entered again against $code.';
  }

  @override
  String get baseChangeLocked =>
      'The base currency is locked because invoices or debts already exist.';

  @override
  String get cannotDisableBase => 'The base currency cannot be disabled.';

  @override
  String get saleFavorites => 'Favorites';

  @override
  String get saleFavoritesHint =>
      'Starred products and your best sellers appear here as one-tap buttons';

  @override
  String get saleSearchHint => 'Type an item name or code';

  @override
  String get cartEmpty => 'Cart is empty';

  @override
  String get cartEmptyHint => 'Type an item name to sell it, or tap a favorite';

  @override
  String get noMatchingProducts => 'No matching products';

  @override
  String codeNotFound(String code) {
    return 'No item with code $code';
  }

  @override
  String get invoiceCurrency => 'Invoice currency';

  @override
  String get subtotalLabel => 'Subtotal';

  @override
  String get discountLabel => 'Discount';

  @override
  String get totalLabel => 'Total';

  @override
  String itemsCount(int count) {
    return 'Items: $count';
  }

  @override
  String get quantityLabel => 'Quantity';

  @override
  String get unitPriceLabel => 'Unit price';

  @override
  String get unitPriceThisSaleOnly =>
      'This sale only — the saved product price does not change';

  @override
  String get lineTotalLabel => 'Line total';

  @override
  String get addToCart => 'Add';

  @override
  String get updateLine => 'Update';

  @override
  String get clearCartTitle => 'Clear cart?';

  @override
  String get clearCartMessage => 'All items in this sale will be removed.';

  @override
  String get clearCart => 'Clear cart';

  @override
  String get removeLine => 'Remove';

  @override
  String get invalidQuantity => 'Invalid quantity';

  @override
  String get quantityMustBePositive => 'Quantity must be greater than zero';

  @override
  String get discountTitle => 'Invoice discount';

  @override
  String get discountTypeAmount => 'Amount';

  @override
  String get discountTypePercent => 'Percent';

  @override
  String get discountNone => 'No discount';

  @override
  String get invalidDiscount => 'Invalid discount';

  @override
  String get discountCappedNote => 'The discount cannot exceed the subtotal.';

  @override
  String get quickItemTitle => 'Quick item';

  @override
  String get quickItemHint => 'Sold once, without saving a product';

  @override
  String get quickItemName => 'Item name';

  @override
  String get saveAsProduct => 'Save as a product too';

  @override
  String get unitOptional => 'Unit (optional)';

  @override
  String get unitNone => 'No unit';

  @override
  String get ratesTitle => 'Exchange rates';

  @override
  String rateNeeded(String code) {
    return 'Set the exchange rate for $code before saving this sale';
  }

  @override
  String get secondaryTotalTitle => 'Secondary total';

  @override
  String get secondaryTotalNone => 'None';

  @override
  String get done => 'Done';

  @override
  String addNewItem(String name) {
    return 'Add «$name»';
  }

  @override
  String get newItemDontSave => 'Don\'t save as a product';

  @override
  String get newItemMore => 'More';

  @override
  String get newItemLess => 'Less';

  @override
  String get unitPriceUpdatesProduct =>
      'A changed price is also saved to the product when the invoice is saved';

  @override
  String get cartNewProduct => 'New product';

  @override
  String get cartPriceWillUpdate => 'New price will be saved';

  @override
  String get sectionSelling => 'Selling';

  @override
  String get settingSaveNewItems => 'Save new items as products';

  @override
  String get settingSaveNewItemsHint =>
      'An item typed during a sale is saved when its invoice is saved';

  @override
  String get settingUpdatePrices => 'Update product price from sales';

  @override
  String get settingUpdatePricesHint =>
      'A price changed during a sale becomes the product\'s saved price';

  @override
  String get settingAutoFavorites => 'Automatic favorites';

  @override
  String get settingAutoFavoritesHint =>
      'After your starred products, the favorites bar shows the best sellers of the last 30 days';

  @override
  String get invoiceSavedTitle => 'Invoice saved';

  @override
  String invoiceNoLabel(String no) {
    return 'Invoice no. $no';
  }

  @override
  String get printInvoice => 'Print';

  @override
  String get sharePdf => 'Share as PDF';

  @override
  String get newSale => 'New sale';

  @override
  String get backToHome => 'Back to home';

  @override
  String get setupPrinterQuestion => 'Do you have a receipt printer?';

  @override
  String get setupPrinterYes => 'Yes, I print invoices';

  @override
  String get setupPrinterNo => 'No, I share them (image / WhatsApp)';

  @override
  String get invoiceSettingsTitle => 'Invoice & printing';

  @override
  String get previewTitle => 'Preview';

  @override
  String get sectionOutput => 'After saving a sale';

  @override
  String get outputModePrint => 'Print';

  @override
  String get outputModeShare => 'Share';

  @override
  String get outputModeBoth => 'Print + Share';

  @override
  String get outputModeHint =>
      'Sets the main button after a sale is saved. The other actions stay in the menu.';

  @override
  String get sectionPrinter => 'Bluetooth printer';

  @override
  String get printerNone => 'No printer selected';

  @override
  String get choosePrinter => 'Choose printer';

  @override
  String get forgetPrinter => 'Forget this printer';

  @override
  String get pairedDevicesTitle => 'Paired devices';

  @override
  String get noPairedDevices =>
      'No paired devices. Pair the printer in the phone\'s Bluetooth settings first (the PIN is usually 0000 or 1234), then come back.';

  @override
  String get openBluetoothSettings => 'Bluetooth settings';

  @override
  String get openAppSettings => 'App settings';

  @override
  String get refresh => 'Refresh';

  @override
  String get testPrint => 'Test print';

  @override
  String get feedLinesLabel => 'Blank lines after printing';

  @override
  String get cutPaperLabel => 'Cut the paper after printing';

  @override
  String get cutPaperHint => 'Only for printers with a cutter';

  @override
  String get sectionPaper => 'Paper';

  @override
  String get paperWidthLabel => 'Paper width';

  @override
  String paperWidthPreset(String mm) {
    return '$mm mm';
  }

  @override
  String get paperCustom => 'Custom';

  @override
  String get paperWidthMmLabel => 'Paper width (mm)';

  @override
  String get printerDpiLabel => 'Printer resolution (DPI)';

  @override
  String get sideMarginLabel => 'Side margin (mm)';

  @override
  String printableWidthInfo(String dots, String mm) {
    return 'Printable width: $dots dots ($mm mm)';
  }

  @override
  String get advancedSection => 'Advanced';

  @override
  String get printableDotsOverrideLabel => 'Printable width (dots)';

  @override
  String get printableDotsOverrideHint =>
      'Leave empty to compute it from the paper width, margin and DPI';

  @override
  String get invalidNumber => 'Invalid number';

  @override
  String get sectionShop => 'Shop details';

  @override
  String get shopNameLabel => 'Shop name';

  @override
  String get logoLabel => 'Logo';

  @override
  String get logoHint => 'A simple dark logo on a white background prints best';

  @override
  String get pickLogo => 'Choose image';

  @override
  String get removeLogo => 'Remove';

  @override
  String get logoError => 'This image could not be read';

  @override
  String get headerTextLabel => 'Header text';

  @override
  String get footerTextLabel => 'Footer text';

  @override
  String get sectionContent => 'Invoice content';

  @override
  String get invoiceLanguageLabel => 'Invoice language';

  @override
  String get baseFontSizeLabel => 'Font size';

  @override
  String get showItemCodeLabel => 'Item code';

  @override
  String get showUnitLabel => 'Unit';

  @override
  String get showUnitPriceLabel => 'Unit price';

  @override
  String get showDateTimeLabel => 'Date and time';

  @override
  String get showInvoiceNumberLabel => 'Invoice number';

  @override
  String get showCustomerNameLabel => 'Customer name';

  @override
  String get showCustomerPhoneLabel => 'Customer phone';

  @override
  String get showAccountNumberLabel => 'Account / card number';

  @override
  String get maskAccountLabel => 'Hide all but the last 4 digits';

  @override
  String get sectionCurrency => 'Currencies on the invoice';

  @override
  String get currencyDisplayLabel => 'Write the currency as';

  @override
  String get currencyDisplaySymbol => 'Symbol';

  @override
  String get currencyDisplayCode => 'Code';

  @override
  String get extraCurrenciesLabel => 'Also show the total in';

  @override
  String get extraCurrenciesHint =>
      'Up to 2 currencies. The exchange rate used is printed under the total.';

  @override
  String get extraCurrenciesNone =>
      'Set the exchange rate of another currency to use this.';

  @override
  String get sectionSharing => 'Sharing';

  @override
  String get shareWidthLabel => 'Width of the shared image';

  @override
  String get shareWidthSameAsPaper => 'Same as the paper';

  @override
  String get shareWidthMmLabel => 'Share width (mm)';

  @override
  String get defaultCountryCodeLabel => 'Default country code';

  @override
  String defaultCountryCodeHint(String code) {
    return 'For sending on WhatsApp: a number typed as 09… is sent to +$code 9…';
  }

  @override
  String get invoiceCustomerLabel => 'Customer';

  @override
  String get invoicePhoneLabel => 'Phone';

  @override
  String get invoiceAccountLabel => 'Account no.';

  @override
  String get sampleItemSugar => 'Sugar';

  @override
  String get sampleItemTea => 'Tea';

  @override
  String get sampleItemPackage => 'Internet package 100 GB';

  @override
  String get sampleUnitKg => 'kg';

  @override
  String get sampleUnitBox => 'box';

  @override
  String get sampleCustomerName => 'Ahmad';

  @override
  String get shareInvoice => 'Share';

  @override
  String get shareAsImage => 'Share as image';

  @override
  String get sendOnWhatsApp => 'Send on WhatsApp';

  @override
  String get saveImageToPhone => 'Save image to phone';

  @override
  String get savePdfToPhone => 'Save PDF to phone';

  @override
  String get moreActions => 'More';

  @override
  String get printSent => 'Sent to the printer';

  @override
  String savedToPhone(String path) {
    return 'Saved to $path';
  }

  @override
  String get whatsAppNotInstalled =>
      'WhatsApp is not installed — opening the share menu instead';

  @override
  String get whatsAppUnsupported =>
      'Could not open the chat directly — opening the share menu instead';

  @override
  String get whatsAppChooseTitle => 'Send with';

  @override
  String get whatsAppRegular => 'WhatsApp';

  @override
  String get whatsAppBusiness => 'WhatsApp Business';

  @override
  String get whatsAppPhoneTitle => 'WhatsApp number';

  @override
  String get whatsAppPhoneHint => 'e.g. 0944 123 456';

  @override
  String get invalidPhone => 'Invalid phone number';

  @override
  String get send => 'Send';

  @override
  String get errorNoPrinter =>
      'No printer selected. Choose one in Settings → Invoice & printing.';

  @override
  String get errorBluetoothUnsupported => 'This device has no Bluetooth.';

  @override
  String get errorBluetoothOff => 'Bluetooth is off. Turn it on and try again.';

  @override
  String get errorBluetoothPermission =>
      'Souqi is not allowed to use Bluetooth. Allow \"Nearby devices\" in the app settings.';

  @override
  String errorPrinterUnreachable(String name) {
    return 'Cannot reach the printer $name. Check that it is switched on, close by and paired.';
  }

  @override
  String get errorPrinterWrite =>
      'The connection to the printer dropped while printing. Try again.';

  @override
  String get errorStoragePermission =>
      'Souqi is not allowed to save files. Allow storage access in the app settings.';

  @override
  String errorOutputUnknown(String detail) {
    return 'Something went wrong: $detail';
  }

  @override
  String get storageTitle => 'Storage';

  @override
  String get storageInvoiceCount => 'Invoices stored';

  @override
  String get storageDatabaseSize => 'Database size';

  @override
  String get optimizingStorage => 'Optimizing…';

  @override
  String sizeInBytes(String size) {
    return '$size B';
  }

  @override
  String sizeInKilobytes(String size) {
    return '$size KB';
  }

  @override
  String sizeInMegabytes(String size) {
    return '$size MB';
  }

  @override
  String get archiveSearchProductHint => 'Product sold';

  @override
  String get archiveSearchCustomerHint => 'Customer, phone or card number';

  @override
  String get archiveInvoiceNoHint => 'Invoice no.';

  @override
  String get archiveFilters => 'Filters';

  @override
  String get archiveClearFilters => 'Clear filters';

  @override
  String get periodAll => 'All';

  @override
  String get periodToday => 'Today';

  @override
  String get periodYesterday => 'Yesterday';

  @override
  String get periodThisWeek => 'This week';

  @override
  String get periodThisMonth => 'This month';

  @override
  String get periodCustom => 'Custom';

  @override
  String periodRangeLabel(String from, String to) {
    return '$from — $to';
  }

  @override
  String get archiveNoInvoices => 'No invoices yet';

  @override
  String get archiveNoMatches => 'No invoice matches these filters';

  @override
  String archiveItemsLabel(String count) {
    return 'Items: $count';
  }

  @override
  String archiveMatchCount(String count, String total) {
    return '$count invoices · $total';
  }

  @override
  String get archiveDeleteRange => 'Delete these invoices';

  @override
  String get archiveDeleteRangeTitle => 'Delete invoices?';

  @override
  String archiveDeleteRangeMessage(String count, String total) {
    return '$count invoices totalling $total will be deleted. Products, invoice numbering and sold card codes are kept.';
  }

  @override
  String get archiveDeleteWholeArchive =>
      'No date range is set, so this deletes EVERY invoice in the archive.';

  @override
  String get archiveDeleteRangeEmpty => 'There are no invoices in this range.';

  @override
  String archiveDeletedMessage(String count) {
    return '$count invoices deleted';
  }

  @override
  String get deleteInvoiceTitle => 'Delete invoice?';

  @override
  String deleteInvoiceMessage(String number) {
    return 'Invoice $number will be deleted. Products and sold card codes are kept, and the number is never reused.';
  }

  @override
  String invoiceDeletedMessage(String number) {
    return 'Invoice $number deleted';
  }

  @override
  String get invoiceNotFound => 'This invoice is no longer in the archive.';

  @override
  String get invoiceCopyMark => 'COPY';

  @override
  String get invoiceCopyNotice =>
      'Anything printed or shared from here is marked as a copy.';

  @override
  String get sectionArchive => 'Archive';

  @override
  String get settingAutoDelete => 'Auto-delete old invoices';

  @override
  String get settingAutoDeleteHint =>
      'Invoices older than this are deleted on the first launch of each day. Products, invoice numbering and sold card codes are kept.';

  @override
  String get retentionOff => 'Off';

  @override
  String retentionDays(String days) {
    return 'After $days days';
  }

  @override
  String get retentionCustom => 'Custom…';

  @override
  String get retentionCustomTitle => 'Delete invoices older than';

  @override
  String get retentionCustomHint => 'Days';

  @override
  String retentionNotice(String count, String days) {
    return '$count invoices older than $days days were deleted';
  }

  @override
  String statsBaseCurrencyNote(String code) {
    return 'All amounts in $code, at the exchange rate stored with each invoice.';
  }

  @override
  String get statsTotalSales => 'Total sales';

  @override
  String get statsInvoiceCount => 'Invoices';

  @override
  String get statsAverageInvoice => 'Average invoice';

  @override
  String get statsTotalDiscounts => 'Discounts';

  @override
  String statsPreviousValue(String value) {
    return 'Previous period: $value';
  }

  @override
  String statsTrendUp(String percent) {
    return 'Up $percent%';
  }

  @override
  String statsTrendDown(String percent) {
    return 'Down $percent%';
  }

  @override
  String get statsTrendFlat => 'Unchanged';

  @override
  String get statsTrendNew => 'New — there was none in the previous period';

  @override
  String get statsTrendGone => 'None in this period';

  @override
  String get statsTopBySales => 'Top 10 by number of sales';

  @override
  String get statsTopByAmount => 'Top 10 by amount';

  @override
  String statsSalesCount(String count) {
    return '$count sales';
  }

  @override
  String get statsUnsavedItemBadge => 'not a product';

  @override
  String get statsNoData => 'No sales in this period';

  @override
  String get statsByCurrency => 'Sales by invoice currency';

  @override
  String get statsShowByCurrency => 'Break down by invoice currency';

  @override
  String get debugTools => 'Developer tools (debug build)';

  @override
  String get debugSeedInvoices => 'Create test invoices';

  @override
  String get debugSeedTitle => 'How many invoices?';

  @override
  String get debugSeedHint =>
      'Spread over the last 365 days, for performance testing';

  @override
  String debugSeedDone(String count) {
    return '$count test invoices created';
  }

  @override
  String get archiveCounting => 'Counting…';

  @override
  String get archiveDeletingTitle => 'Deleting invoices';

  @override
  String get archiveDeletingHint => 'Keep the app open until this finishes.';

  @override
  String progressCount(String done, String total) {
    return '$done of $total';
  }

  @override
  String archiveDeletePartial(String deleted, String remaining) {
    return '$deleted invoices deleted, $remaining still there. Try again.';
  }

  @override
  String archiveDeleteFailed(String detail) {
    return 'The cleanup stopped: $detail';
  }

  @override
  String get housekeepingBusy => 'Another cleanup is still running.';

  @override
  String get debugSeedingTitle => 'Creating test invoices';

  @override
  String get archiveDeleteNeedsNoSearch =>
      'Clear the search to delete a period';

  @override
  String get navCustomers => 'Customers';

  @override
  String get navDue => 'Due for renewal';

  @override
  String get customerName => 'Name';

  @override
  String get customerPhone => 'Phone (optional)';

  @override
  String get notesLabel => 'Notes';

  @override
  String get addCustomer => 'Add customer';

  @override
  String get editCustomer => 'Edit customer';

  @override
  String get newCustomer => 'New customer';

  @override
  String get searchCustomersHint => 'Search by name or phone';

  @override
  String get noCustomers => 'No customers yet';

  @override
  String get deactivate => 'Deactivate';

  @override
  String get reactivate => 'Reactivate';

  @override
  String get deactivateCustomerTitle => 'Deactivate customer?';

  @override
  String deactivateCustomerMessage(String name) {
    return '\"$name\" will no longer appear in the search or in the due list. Their invoices and accounts are kept, and you can reactivate them at any time.';
  }

  @override
  String get customerNotFound => 'This customer is no longer there';

  @override
  String get callCustomer => 'Call';

  @override
  String get whatsAppCustomer => 'WhatsApp';

  @override
  String get cannotDial => 'Could not open the phone dialer';

  @override
  String get whatsAppChatNotInstalled =>
      'WhatsApp is not installed on this phone';

  @override
  String get whatsAppChatFailed => 'Could not open the WhatsApp chat';

  @override
  String get accountsTitle => 'Cards & accounts';

  @override
  String get addAccount => 'Add card / account';

  @override
  String get editAccount => 'Edit card / account';

  @override
  String get noAccounts => 'No cards or accounts yet';

  @override
  String accountsCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString cards / accounts',
      one: '1 card / account',
      zero: 'No cards',
    );
    return '$_temp0';
  }

  @override
  String get accountNumberLabel => 'Card / account number';

  @override
  String get accountLabelLabel => 'Type (e.g. internet card, ADSL line)';

  @override
  String get accountProviderLabel => 'Provider';

  @override
  String get accountPackageLabel => 'Default package';

  @override
  String get accountNoPackage => 'None';

  @override
  String get accountRenewalDaysLabel => 'Renewal period (days)';

  @override
  String get accountRenewalDaysHint => 'e.g. 30. Leave empty for no schedule.';

  @override
  String get accountLastRenewalLabel => 'Last renewal';

  @override
  String get accountNextDueLabel => 'Next due date';

  @override
  String get accountNextDueHint =>
      'Last renewal + period. You can also set it by hand.';

  @override
  String get accountNotSet => 'Not set';

  @override
  String get clearDate => 'Clear';

  @override
  String get accountDuplicateTitle => 'Number already registered';

  @override
  String accountDuplicateMessage(String number, String customer) {
    return '$number is already registered with the same provider for: $customer. Save it anyway?';
  }

  @override
  String get saveAnyway => 'Save anyway';

  @override
  String get firstAccountSection => 'First card / account (optional)';

  @override
  String get historyTitle => 'Purchases & renewals';

  @override
  String get noHistory => 'No invoices yet';

  @override
  String get showMore => 'Show more';

  @override
  String get customerInvoiceCount => 'Invoices';

  @override
  String get customerTotalSpent => 'Total';

  @override
  String get customerLastPurchase => 'Last purchase';

  @override
  String historyMoreItems(String count) {
    return '+$count more';
  }

  @override
  String get quickSearchHint => 'Customer, phone or card number';

  @override
  String quickSearchEmpty(String query) {
    return 'No customer or card matches \"$query\"';
  }

  @override
  String get quickSearchPrompt =>
      'Type a name, a phone number or a card / account number';

  @override
  String get renew => 'Renew';

  @override
  String packageLabel(String name) {
    return 'Package: $name';
  }

  @override
  String lastRenewalLabel(String date) {
    return 'Last renewal: $date';
  }

  @override
  String dueOverdueBy(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Overdue by $daysString days',
      one: 'Overdue by 1 day',
    );
    return '$_temp0';
  }

  @override
  String get dueToday => 'Due today';

  @override
  String dueInDays(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Due in $daysString days',
      one: 'Due tomorrow',
    );
    return '$_temp0';
  }

  @override
  String get dueOk => 'OK';

  @override
  String get dueNoDate => 'No due date';

  @override
  String dueSectionOverdue(String count) {
    return 'Overdue ($count)';
  }

  @override
  String dueSectionToday(String count) {
    return 'Due today ($count)';
  }

  @override
  String dueSectionSoon(int days, String count) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'Due in the next $daysString days ($count)',
      one: 'Due tomorrow ($count)',
    );
    return '$_temp0';
  }

  @override
  String get dueEmpty => 'Nothing is due for renewal';

  @override
  String dueSeeAll(String count) {
    return 'See all ($count)';
  }

  @override
  String get sendReminder => 'Remind on WhatsApp';

  @override
  String get sectionCustomers => 'Customers & renewals';

  @override
  String get settingDueSoonDays => 'Due-soon window';

  @override
  String get settingDueSoonDaysHint =>
      'Accounts due within this many days are listed under \"Due for renewal\"';

  @override
  String daysCount(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$daysString days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get settingReminderText => 'Renewal reminder message';

  @override
  String get settingReminderTextHint =>
      'Opened in the customer\'s WhatsApp chat from the due list. You can still edit it there before sending.';

  @override
  String get reminderDialogTitle => 'Reminder message';

  @override
  String reminderPlaceholdersHint(String placeholders) {
    return 'These are replaced for each customer: $placeholders';
  }

  @override
  String get reminderResetDefault => 'Use default';

  @override
  String reminderDefaultText(String name, String account, String date) {
    return 'Hello $name, this is a reminder that your subscription ($account) is due for renewal on $date.';
  }

  @override
  String get saleCustomerChip => 'Customer';

  @override
  String get saleCustomerRemove => 'Remove customer';

  @override
  String accountRequiredMessage(String name) {
    return '\"$name\" must be linked to a customer\'s card or account';
  }

  @override
  String get chooseAccount => 'Choose account';

  @override
  String get customerPickerTitle => 'Choose customer';

  @override
  String newCustomerNamed(String text) {
    return 'New customer \"$text\"';
  }

  @override
  String newCustomerWithPhone(String text) {
    return 'New customer with phone $text';
  }

  @override
  String newCustomerWithAccount(String text) {
    return 'New customer with card no. $text';
  }

  @override
  String packageChangedNotice(String name) {
    return 'This renewal sold \"$name\", which is not the account\'s default package.';
  }

  @override
  String get makeDefaultPackage =>
      'Make this the default package for this account';

  @override
  String get defaultPackageUpdated => 'Default package updated';

  @override
  String get renewNewSaleTitle => 'Start a new sale?';

  @override
  String get renewNewSaleMessage =>
      'There are items in the current sale. Starting the renewal will remove them.';

  @override
  String get renewNoPackage =>
      'This account has no default package. Add the item to sell.';

  @override
  String get statsRenewals => 'Renewals';

  @override
  String get statsTopPackages => 'Top packages';

  @override
  String get statsTopCustomers => 'Sales per customer';

  @override
  String statsInvoicesCount(String count) {
    return '$count invoices';
  }

  @override
  String get debugSeedCustomers => 'Create test customers';

  @override
  String get debugSeedCustomersHint =>
      'Each with 2 cards / accounts, for testing the quick search and the due list';

  @override
  String debugSeedCustomersDone(String count) {
    return '$count test customers created';
  }

  @override
  String get debugSeedingCustomersTitle => 'Creating test customers';

  @override
  String get sectionSecurity => 'Security';

  @override
  String get pinLockTitle => 'PIN lock';

  @override
  String get pinNotSet => 'No PIN set';

  @override
  String get pinIsSet => 'A PIN is set';

  @override
  String get pinSetTitle => 'Choose a PIN';

  @override
  String get pinChangeTitle => 'New PIN';

  @override
  String get pinSetIntro =>
      'The PIN protects card codes and other sensitive actions. Use 4 to 6 digits.';

  @override
  String get pinNeededIntro =>
      'A PIN is needed here and none is set yet. Choose one now: 4 to 6 digits.';

  @override
  String get pinNewLabel => 'PIN';

  @override
  String get pinConfirmLabel => 'Repeat the PIN';

  @override
  String get pinInvalid => 'The PIN must be 4 to 6 digits';

  @override
  String get pinMismatch => 'The two PINs are not the same';

  @override
  String get pinEnterTitle => 'Enter the PIN';

  @override
  String get pinLabel => 'PIN';

  @override
  String pinWrong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts left',
      one: '1 attempt left',
      zero: 'No attempts left',
    );
    return 'Wrong PIN. $_temp0';
  }

  @override
  String pinLocked(String time) {
    return 'Too many wrong attempts. Try again in $time.';
  }

  @override
  String get pinConfirmAction => 'Continue';

  @override
  String get pinForgetWarning =>
      'Next you will get a recovery code: the only way back in if the PIN is forgotten.';

  @override
  String get pinChangeAction => 'Change PIN';

  @override
  String get pinRemoveAction => 'Remove PIN';

  @override
  String get pinRemoveTitle => 'Remove the PIN?';

  @override
  String get pinRemoveMessage =>
      'Without a PIN, whoever holds this phone can choose a new one and then reveal or reprint card codes.';

  @override
  String get pinSaved => 'PIN saved';

  @override
  String get pinRemoved => 'PIN removed';

  @override
  String get pinReasonReprint =>
      'This invoice carries card codes. Printing or sharing it again needs the PIN and is marked as a copy.';

  @override
  String get pinReasonCodes => 'Card codes are protected by the PIN.';

  @override
  String get auditLogTitle => 'Audit log';

  @override
  String get auditLogHint =>
      'Codes revealed, reprinted, voided, loaded or exported';

  @override
  String get auditEmpty => 'No sensitive actions in this period';

  @override
  String get loadMore => 'Show more';

  @override
  String get auditCodeImport => 'Codes loaded';

  @override
  String get auditCodeReveal => 'Code shown on screen';

  @override
  String get auditCodeLookup => 'Search by code';

  @override
  String get auditCodeVoid => 'Code voided';

  @override
  String get auditCodeRestore => 'Code returned to stock';

  @override
  String get auditCodeExport => 'Codes exported';

  @override
  String get auditCodeExpiryChange => 'Expiry date changed';

  @override
  String get auditBatchDelete => 'Batch deleted';

  @override
  String get auditInvoiceReprint => 'Invoice with codes printed again';

  @override
  String get auditPinSet => 'PIN set';

  @override
  String get auditPinChange => 'PIN changed';

  @override
  String get auditPinRemove => 'PIN removed';

  @override
  String auditDetailFound(String count) {
    return '$count found';
  }

  @override
  String auditDetailReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String cardsCount(String count) {
    return '$count cards';
  }

  @override
  String serialLabel(String serial) {
    return 'S/N $serial';
  }

  @override
  String get navCardStock => 'Card stock';

  @override
  String get stockAvailable => 'Available';

  @override
  String get stockSold => 'Sold';

  @override
  String get stockVoid => 'Void';

  @override
  String get stockExpired => 'Expired';

  @override
  String stockCount(String count) {
    return 'In stock: $count';
  }

  @override
  String get stockOut => 'Out of stock';

  @override
  String stockLowWarning(String name, String count) {
    return '$name: only $count left';
  }

  @override
  String stockOutWarning(String name) {
    return '$name: out of stock';
  }

  @override
  String get cardStockEmpty =>
      'No product is sold from code stock yet. Open a card / service product and turn on \"Sold from code stock\".';

  @override
  String get cardStockLookup => 'Find a card by its code';

  @override
  String get expiredCodesTitle => 'Expired codes';

  @override
  String expiredCodesNotice(String count) {
    return '$count expired codes are not being sold. Decide what to do with them.';
  }

  @override
  String get expiredEmpty => 'No expired codes';

  @override
  String get batchesTitle => 'Batches';

  @override
  String get batchAdd => 'Load codes';

  @override
  String get batchEmpty => 'No codes loaded yet';

  @override
  String batchCostEach(String amount) {
    return 'Cost $amount each';
  }

  @override
  String batchExpires(String date) {
    return 'Valid until $date';
  }

  @override
  String get batchDelete => 'Delete batch';

  @override
  String get batchDeleteTitle => 'Delete this batch?';

  @override
  String batchDeleteMessage(String count) {
    return 'Its $count unsold codes will be deleted for good.';
  }

  @override
  String get batchDeleteBlocked =>
      'This batch has sold codes and cannot be deleted.';

  @override
  String batchDeleted(String count) {
    return '$count codes deleted';
  }

  @override
  String get batchShowCodes => 'Show the codes';

  @override
  String get batchChangeExpiry => 'Change expiry date';

  @override
  String get expiryChanged => 'Expiry date changed';

  @override
  String get exportCodes => 'Export unsold codes';

  @override
  String get exportWarning =>
      'The file holds the codes in the clear. Anyone who gets it can use the cards.';

  @override
  String get exportShare => 'Share the file';

  @override
  String get exportSave => 'Save to phone';

  @override
  String exportDone(String count) {
    return '$count codes exported';
  }

  @override
  String get exportNothing => 'No unsold codes to export';

  @override
  String get addBatchTitle => 'Load codes';

  @override
  String get loadMethodPaste => 'Paste';

  @override
  String get loadMethodFile => 'File';

  @override
  String get loadMethodScan => 'Scan';

  @override
  String get pasteLabel => 'Codes';

  @override
  String get pasteHint => 'One card per line';

  @override
  String get pickFile => 'Choose a .txt or .csv file';

  @override
  String get fileReadFailed => 'The file could not be read';

  @override
  String get columnsLabel => 'Each line holds';

  @override
  String get columnsCodeOnly => 'Code';

  @override
  String get columnsSerialCode => 'Serial, code';

  @override
  String get columnsCodeSerial => 'Code, serial';

  @override
  String importToAdd(String count) {
    return '$count to add';
  }

  @override
  String importAdded(String count) {
    return '$count added';
  }

  @override
  String importDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count duplicates skipped',
      one: '1 duplicate skipped',
    );
    return '$_temp0';
  }

  @override
  String importEmpty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count empty lines',
      one: '1 empty line',
    );
    return '$_temp0';
  }

  @override
  String importInvalid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines without a code',
      one: '1 line without a code',
    );
    return '$_temp0';
  }

  @override
  String get importHeaderSkipped => 'heading line left out';

  @override
  String get batchExpiryLabel => 'Expiry date (optional)';

  @override
  String get noExpiry => 'No expiry';

  @override
  String batchCostLabel(String currency) {
    return 'Cost per card, $currency (optional)';
  }

  @override
  String get saveBatch => 'Save the batch';

  @override
  String get nothingToAdd => 'Nothing new to add';

  @override
  String get scanStart => 'Scan cards with the camera';

  @override
  String get scanTitle => 'Scan cards';

  @override
  String scanCount(String count) {
    return '$count scanned';
  }

  @override
  String get scanDuplicate => 'Already scanned';

  @override
  String get scanHint =>
      'Point the camera at the QR code or barcode on the card';

  @override
  String get scanCameraError =>
      'The camera could not be opened. Allow camera access for Souqi in the phone settings.';

  @override
  String scannedCards(String count) {
    return 'Scanned cards: $count';
  }

  @override
  String get clearScanned => 'Clear';

  @override
  String get codesTitle => 'Card codes';

  @override
  String get codesMaskedNote =>
      'Codes are hidden on screen. They are printed and shared in full.';

  @override
  String get codeStatusAvailable => 'In stock';

  @override
  String get codeStatusSold => 'Sold';

  @override
  String get codeStatusVoid => 'Void';

  @override
  String get codeStatusExpired => 'Expired';

  @override
  String get codeReveal => 'Show the code';

  @override
  String get codeVoid => 'Void';

  @override
  String get codeReturn => 'Return to stock';

  @override
  String get codeRevealedTitle => 'Card code';

  @override
  String get codeUnreadable => 'This code cannot be read on this device.';

  @override
  String get voidCodeTitle => 'Void this code?';

  @override
  String get voidCodeMessage =>
      'The card will count as neither sold nor in stock. This is written to the audit log.';

  @override
  String get returnCodeTitle => 'Return this code to stock?';

  @override
  String get returnCodeMessage =>
      'The card becomes available for sale again. This is written to the audit log.';

  @override
  String get reasonLabel => 'Reason';

  @override
  String get codeVoided => 'Code voided';

  @override
  String get codeReturned => 'Code returned to stock';

  @override
  String get voidExpiredAction => 'Void them';

  @override
  String get voidExpiredTitle => 'Void the expired codes?';

  @override
  String voidExpiredMessage(String count, String name) {
    return '$count expired codes of \"$name\" will be voided.';
  }

  @override
  String expiredVoided(String count) {
    return '$count codes voided';
  }

  @override
  String get batchCodesTitle => 'Codes of the batch';

  @override
  String get lookupTitle => 'Find a card';

  @override
  String get lookupHint => 'Type or paste the full code';

  @override
  String get lookupAction => 'Search';

  @override
  String get lookupNotFound => 'No card with this code';

  @override
  String lookupSoldOn(String date) {
    return 'Sold on $date';
  }

  @override
  String lookupCustomer(String name) {
    return 'Customer: $name';
  }

  @override
  String lookupAccount(String number) {
    return 'Account: $number';
  }

  @override
  String get lookupOpenInvoice => 'Open the invoice';

  @override
  String get lookupInvoiceDeleted =>
      'The invoice itself was deleted from the archive';

  @override
  String codeStockOnly(String count) {
    return 'Only $count in stock';
  }

  @override
  String codeStockShort(String name, String wanted, String available) {
    return '\"$name\": $wanted wanted, $available in stock';
  }

  @override
  String get codeStockUnreadable =>
      'The card codes cannot be read on this device, so nothing was sold.';

  @override
  String codeStockWholeCards(String name) {
    return '\"$name\" is sold in whole cards';
  }

  @override
  String get soldFromCodeStock => 'Sold from code stock';

  @override
  String get soldFromCodeStockHint =>
      'Each sale takes a card code from the loaded stock and prints it on the invoice';

  @override
  String get lowStockThresholdLabel => 'Warn when stock falls to';

  @override
  String get lowStockThresholdHint => 'Empty = no warning';

  @override
  String get manageStock => 'Card stock of this product';

  @override
  String get sectionCardCodes => 'Card codes';

  @override
  String get printCodeQrLabel => 'Print a QR code of each card code';

  @override
  String get codesSeparateSlipsLabel => 'Print each card on a separate slip';

  @override
  String get codesSeparateSlipsHint =>
      'The printer feeds (and cuts) between slips. A shared image or PDF always holds everything.';

  @override
  String get invoiceSerialLabel => 'S/N';

  @override
  String invoiceExpiryLabel(String date) {
    return 'Valid until $date';
  }

  @override
  String get invoiceCodeUnreadable => 'Code unavailable on this device';

  @override
  String get statsCardsSold => 'Cards sold';

  @override
  String statsCardsProfit(String amount) {
    return 'Profit $amount';
  }

  @override
  String statsCardsProfitPartial(String amount, String count) {
    return 'Profit $amount (on the $count with a known cost)';
  }

  @override
  String get debugSeedCards => 'Create test card codes';

  @override
  String get debugSeedCardsHint =>
      'Two card products with made-up codes, one batch near expiry, for testing card sales';

  @override
  String debugSeedCardsDone(String count) {
    return '$count test codes created';
  }

  @override
  String get batchSaveFailed =>
      'The batch could not be saved. Nothing was added.';

  @override
  String get importPreviewTitle => 'Preview (first 5)';

  @override
  String get recoveryCodeTitle => 'Recovery code';

  @override
  String get recoveryCodeIntro =>
      'If the PIN is ever forgotten, this code is the only way to choose a new one. It is shown once, now. Print it or save it, and keep it away from this phone.';

  @override
  String get recoveryCodeSaved => 'I saved it';

  @override
  String get recoveryPrint => 'Print';

  @override
  String get recoveryShare => 'Share';

  @override
  String get recoverySlipTitle => 'PIN recovery code';

  @override
  String get recoverySlipHint =>
      'Keep this safe. With this code the PIN can be reset.';

  @override
  String get pinForgot => 'Forgot PIN?';

  @override
  String get recoveryEnterTitle => 'Reset the PIN';

  @override
  String get recoveryEnterIntro =>
      'Enter the recovery code you were given when the PIN was chosen.';

  @override
  String get recoveryEnterIntroSigned =>
      'Enter the recovery code you were given when the PIN was chosen, or a reset code from the developer.';

  @override
  String get recoveryInvalid => 'A recovery code has 12 letters and digits';

  @override
  String recoveryWrong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attempts left',
      one: '1 attempt left',
      zero: 'No attempts left',
    );
    return 'Wrong recovery code. $_temp0';
  }

  @override
  String get recoveryRefused => 'This code is not valid';

  @override
  String get auditPinRecover => 'PIN reset with the recovery code';

  @override
  String get auditPinResetSigned => 'PIN reset with a developer code';

  @override
  String get recoveryMissingTitle => 'This PIN has no recovery code';

  @override
  String get recoveryMissingMessage =>
      'If the PIN is forgotten there will be no way back in.';

  @override
  String get recoveryCreateNow => 'Create a recovery code now';

  @override
  String get recoveryCreateArmed =>
      'Enter the PIN. The recovery code is shown next.';

  @override
  String get auditRecoveryCodeCreate => 'Recovery code created';
}
