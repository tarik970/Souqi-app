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
  String get saleFavoritesHint => 'Star products to get one-tap buttons here';

  @override
  String get saleSearchHint => 'Name or code — press enter for an exact code';

  @override
  String get cartEmpty => 'Cart is empty';

  @override
  String get cartEmptyHint => 'Tap a favorite or search for an item';

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
  String get invoiceSavedTitle => 'Invoice saved';

  @override
  String invoiceNoLabel(String no) {
    return 'Invoice no. $no';
  }

  @override
  String get printInvoice => 'Print';

  @override
  String get sharePdf => 'Share PDF';

  @override
  String get newSale => 'New sale';

  @override
  String get backToHome => 'Back to home';
}
