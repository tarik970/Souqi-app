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
  String get comingSoon => 'Coming soon';

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
      'This product is used in invoices, so it was deactivated instead of deleted.';

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
}
