// ignore_for_file: deprecated_member_use
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// Application name, shown in the app bar and task switcher
  ///
  /// In en, this message translates to:
  /// **'Souqi'**
  String get appTitle;

  /// No description provided for @navSale.
  ///
  /// In en, this message translates to:
  /// **'Sale'**
  String get navSale;

  /// No description provided for @navProducts.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get navProducts;

  /// No description provided for @navArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get navArchive;

  /// No description provided for @navStats.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get navStats;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @fieldRequired.
  ///
  /// In en, this message translates to:
  /// **'This field is required'**
  String get fieldRequired;

  /// No description provided for @activeLabel.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get activeLabel;

  /// No description provided for @setupWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Souqi'**
  String get setupWelcome;

  /// No description provided for @setupIntro.
  ///
  /// In en, this message translates to:
  /// **'Choose the app language and your shop type. You can change both later in Settings.'**
  String get setupIntro;

  /// No description provided for @setupLanguage.
  ///
  /// In en, this message translates to:
  /// **'App language'**
  String get setupLanguage;

  /// No description provided for @languageArabic.
  ///
  /// In en, this message translates to:
  /// **'العربية'**
  String get languageArabic;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @setupShopType.
  ///
  /// In en, this message translates to:
  /// **'Shop type'**
  String get setupShopType;

  /// No description provided for @shopTypeGrocery.
  ///
  /// In en, this message translates to:
  /// **'Grocery'**
  String get shopTypeGrocery;

  /// No description provided for @shopTypeCards.
  ///
  /// In en, this message translates to:
  /// **'Cards & subscriptions'**
  String get shopTypeCards;

  /// No description provided for @shopTypeBoth.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get shopTypeBoth;

  /// No description provided for @setupStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get setupStart;

  /// No description provided for @searchProductsHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or code'**
  String get searchProductsHint;

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @filterGoods.
  ///
  /// In en, this message translates to:
  /// **'Goods'**
  String get filterGoods;

  /// No description provided for @filterServices.
  ///
  /// In en, this message translates to:
  /// **'Cards & services'**
  String get filterServices;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get addProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit product'**
  String get editProduct;

  /// No description provided for @productName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get productName;

  /// No description provided for @productCode.
  ///
  /// In en, this message translates to:
  /// **'Code (optional)'**
  String get productCode;

  /// No description provided for @productCodeTaken.
  ///
  /// In en, this message translates to:
  /// **'This code is already used'**
  String get productCodeTaken;

  /// No description provided for @productKind.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get productKind;

  /// No description provided for @kindGoods.
  ///
  /// In en, this message translates to:
  /// **'Goods'**
  String get kindGoods;

  /// No description provided for @kindService.
  ///
  /// In en, this message translates to:
  /// **'Card / service'**
  String get kindService;

  /// No description provided for @productUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get productUnit;

  /// No description provided for @productPrice.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get productPrice;

  /// No description provided for @invalidPrice.
  ///
  /// In en, this message translates to:
  /// **'Invalid price'**
  String get invalidPrice;

  /// No description provided for @productCurrency.
  ///
  /// In en, this message translates to:
  /// **'Price currency'**
  String get productCurrency;

  /// No description provided for @favoriteLabel.
  ///
  /// In en, this message translates to:
  /// **'Favorite'**
  String get favoriteLabel;

  /// No description provided for @requiresAccount.
  ///
  /// In en, this message translates to:
  /// **'Requires customer account'**
  String get requiresAccount;

  /// No description provided for @requiresAccountHint.
  ///
  /// In en, this message translates to:
  /// **'A sale of this item must be linked to a customer\'s card or account number'**
  String get requiresAccountHint;

  /// No description provided for @showInactive.
  ///
  /// In en, this message translates to:
  /// **'Show inactive'**
  String get showInactive;

  /// No description provided for @inactiveBadge.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactiveBadge;

  /// No description provided for @deleteProductTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete product?'**
  String get deleteProductTitle;

  /// No description provided for @deleteProductMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteProductMessage(String name);

  /// No description provided for @productDeactivatedMessage.
  ///
  /// In en, this message translates to:
  /// **'This product is used in invoices, so it was deactivated instead of deleted.'**
  String get productDeactivatedMessage;

  /// No description provided for @noProducts.
  ///
  /// In en, this message translates to:
  /// **'No products yet'**
  String get noProducts;

  /// No description provided for @unitsTitle.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get unitsTitle;

  /// No description provided for @addUnit.
  ///
  /// In en, this message translates to:
  /// **'Add unit'**
  String get addUnit;

  /// No description provided for @editUnit.
  ///
  /// In en, this message translates to:
  /// **'Edit unit'**
  String get editUnit;

  /// No description provided for @unitName.
  ///
  /// In en, this message translates to:
  /// **'Unit name'**
  String get unitName;

  /// No description provided for @presetBadge.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get presetBadge;

  /// No description provided for @deleteUnitTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete unit?'**
  String get deleteUnitTitle;

  /// No description provided for @deleteUnitMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteUnitMessage(String name);

  /// No description provided for @unitInUse.
  ///
  /// In en, this message translates to:
  /// **'Cannot delete: {count} product(s) use this unit'**
  String unitInUse(int count);

  /// No description provided for @settingsCurrencies.
  ///
  /// In en, this message translates to:
  /// **'Currencies & exchange rates'**
  String get settingsCurrencies;

  /// No description provided for @showPoweredBy.
  ///
  /// In en, this message translates to:
  /// **'Show \"Powered by Souqi\" on invoices'**
  String get showPoweredBy;

  /// No description provided for @poweredByFooter.
  ///
  /// In en, this message translates to:
  /// **'Powered by Souqi'**
  String get poweredByFooter;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Souqi'**
  String get aboutTitle;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Souqi — Sales & invoicing system'**
  String get aboutTagline;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String versionLabel(String version);

  /// No description provided for @currenciesTitle.
  ///
  /// In en, this message translates to:
  /// **'Currencies'**
  String get currenciesTitle;

  /// No description provided for @addCurrency.
  ///
  /// In en, this message translates to:
  /// **'Add currency'**
  String get addCurrency;

  /// No description provided for @editCurrency.
  ///
  /// In en, this message translates to:
  /// **'Edit currency'**
  String get editCurrency;

  /// No description provided for @currencyCode.
  ///
  /// In en, this message translates to:
  /// **'Code (e.g. USD)'**
  String get currencyCode;

  /// No description provided for @currencyCodeExists.
  ///
  /// In en, this message translates to:
  /// **'This code already exists'**
  String get currencyCodeExists;

  /// No description provided for @currencyNameAr.
  ///
  /// In en, this message translates to:
  /// **'Arabic name'**
  String get currencyNameAr;

  /// No description provided for @currencyNameEn.
  ///
  /// In en, this message translates to:
  /// **'English name'**
  String get currencyNameEn;

  /// No description provided for @currencySymbol.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get currencySymbol;

  /// No description provided for @currencyDecimals.
  ///
  /// In en, this message translates to:
  /// **'Decimal places'**
  String get currencyDecimals;

  /// No description provided for @exchangeRate.
  ///
  /// In en, this message translates to:
  /// **'Exchange rate'**
  String get exchangeRate;

  /// No description provided for @rateHint.
  ///
  /// In en, this message translates to:
  /// **'1 {code} = ? {base}'**
  String rateHint(String code, String base);

  /// No description provided for @rateDisplay.
  ///
  /// In en, this message translates to:
  /// **'1 {code} = {value} {base}'**
  String rateDisplay(String code, String value, String base);

  /// No description provided for @invalidRate.
  ///
  /// In en, this message translates to:
  /// **'Invalid exchange rate'**
  String get invalidRate;

  /// No description provided for @rateUpdatedAt.
  ///
  /// In en, this message translates to:
  /// **'Rate updated: {date}'**
  String rateUpdatedAt(String date);

  /// No description provided for @rateNeverUpdated.
  ///
  /// In en, this message translates to:
  /// **'Rate not set yet'**
  String get rateNeverUpdated;

  /// No description provided for @updateRate.
  ///
  /// In en, this message translates to:
  /// **'Update rate'**
  String get updateRate;

  /// No description provided for @baseBadge.
  ///
  /// In en, this message translates to:
  /// **'Base'**
  String get baseBadge;

  /// No description provided for @setAsBase.
  ///
  /// In en, this message translates to:
  /// **'Set as base currency'**
  String get setAsBase;

  /// No description provided for @baseChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change base currency?'**
  String get baseChangeTitle;

  /// No description provided for @baseChangeWarning.
  ///
  /// In en, this message translates to:
  /// **'All totals and statistics use the base currency. Exchange rates of the other currencies must be entered again against {code}.'**
  String baseChangeWarning(String code);

  /// No description provided for @baseChangeLocked.
  ///
  /// In en, this message translates to:
  /// **'The base currency is locked because invoices or debts already exist.'**
  String get baseChangeLocked;

  /// No description provided for @cannotDisableBase.
  ///
  /// In en, this message translates to:
  /// **'The base currency cannot be disabled.'**
  String get cannotDisableBase;

  /// No description provided for @saleFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get saleFavorites;

  /// No description provided for @saleFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'Starred products and your best sellers appear here as one-tap buttons'**
  String get saleFavoritesHint;

  /// No description provided for @saleSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Type an item name or code'**
  String get saleSearchHint;

  /// No description provided for @cartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get cartEmpty;

  /// No description provided for @cartEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Type an item name to sell it, or tap a favorite'**
  String get cartEmptyHint;

  /// No description provided for @noMatchingProducts.
  ///
  /// In en, this message translates to:
  /// **'No matching products'**
  String get noMatchingProducts;

  /// No description provided for @codeNotFound.
  ///
  /// In en, this message translates to:
  /// **'No item with code {code}'**
  String codeNotFound(String code);

  /// No description provided for @invoiceCurrency.
  ///
  /// In en, this message translates to:
  /// **'Invoice currency'**
  String get invoiceCurrency;

  /// No description provided for @subtotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotalLabel;

  /// No description provided for @discountLabel.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discountLabel;

  /// No description provided for @totalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalLabel;

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'Items: {count}'**
  String itemsCount(int count);

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity'**
  String get quantityLabel;

  /// No description provided for @unitPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get unitPriceLabel;

  /// No description provided for @unitPriceThisSaleOnly.
  ///
  /// In en, this message translates to:
  /// **'This sale only — the saved product price does not change'**
  String get unitPriceThisSaleOnly;

  /// No description provided for @lineTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Line total'**
  String get lineTotalLabel;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get addToCart;

  /// No description provided for @updateLine.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get updateLine;

  /// No description provided for @clearCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cart?'**
  String get clearCartTitle;

  /// No description provided for @clearCartMessage.
  ///
  /// In en, this message translates to:
  /// **'All items in this sale will be removed.'**
  String get clearCartMessage;

  /// No description provided for @clearCart.
  ///
  /// In en, this message translates to:
  /// **'Clear cart'**
  String get clearCart;

  /// No description provided for @removeLine.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLine;

  /// No description provided for @invalidQuantity.
  ///
  /// In en, this message translates to:
  /// **'Invalid quantity'**
  String get invalidQuantity;

  /// No description provided for @quantityMustBePositive.
  ///
  /// In en, this message translates to:
  /// **'Quantity must be greater than zero'**
  String get quantityMustBePositive;

  /// No description provided for @discountTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice discount'**
  String get discountTitle;

  /// No description provided for @discountTypeAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get discountTypeAmount;

  /// No description provided for @discountTypePercent.
  ///
  /// In en, this message translates to:
  /// **'Percent'**
  String get discountTypePercent;

  /// No description provided for @discountNone.
  ///
  /// In en, this message translates to:
  /// **'No discount'**
  String get discountNone;

  /// No description provided for @invalidDiscount.
  ///
  /// In en, this message translates to:
  /// **'Invalid discount'**
  String get invalidDiscount;

  /// No description provided for @discountCappedNote.
  ///
  /// In en, this message translates to:
  /// **'The discount cannot exceed the subtotal.'**
  String get discountCappedNote;

  /// No description provided for @quickItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick item'**
  String get quickItemTitle;

  /// No description provided for @quickItemHint.
  ///
  /// In en, this message translates to:
  /// **'Sold once, without saving a product'**
  String get quickItemHint;

  /// No description provided for @quickItemName.
  ///
  /// In en, this message translates to:
  /// **'Item name'**
  String get quickItemName;

  /// No description provided for @saveAsProduct.
  ///
  /// In en, this message translates to:
  /// **'Save as a product too'**
  String get saveAsProduct;

  /// No description provided for @unitOptional.
  ///
  /// In en, this message translates to:
  /// **'Unit (optional)'**
  String get unitOptional;

  /// No description provided for @unitNone.
  ///
  /// In en, this message translates to:
  /// **'No unit'**
  String get unitNone;

  /// No description provided for @ratesTitle.
  ///
  /// In en, this message translates to:
  /// **'Exchange rates'**
  String get ratesTitle;

  /// No description provided for @rateNeeded.
  ///
  /// In en, this message translates to:
  /// **'Set the exchange rate for {code} before saving this sale'**
  String rateNeeded(String code);

  /// No description provided for @secondaryTotalTitle.
  ///
  /// In en, this message translates to:
  /// **'Secondary total'**
  String get secondaryTotalTitle;

  /// No description provided for @secondaryTotalNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get secondaryTotalNone;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// Top row of the sale search: sells the typed text as a new item
  ///
  /// In en, this message translates to:
  /// **'Add «{name}»'**
  String addNewItem(String name);

  /// No description provided for @newItemDontSave.
  ///
  /// In en, this message translates to:
  /// **'Don\'t save as a product'**
  String get newItemDontSave;

  /// No description provided for @newItemMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get newItemMore;

  /// No description provided for @newItemLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get newItemLess;

  /// No description provided for @unitPriceUpdatesProduct.
  ///
  /// In en, this message translates to:
  /// **'A changed price is also saved to the product when the invoice is saved'**
  String get unitPriceUpdatesProduct;

  /// No description provided for @cartNewProduct.
  ///
  /// In en, this message translates to:
  /// **'New product'**
  String get cartNewProduct;

  /// No description provided for @cartPriceWillUpdate.
  ///
  /// In en, this message translates to:
  /// **'New price will be saved'**
  String get cartPriceWillUpdate;

  /// No description provided for @sectionSelling.
  ///
  /// In en, this message translates to:
  /// **'Selling'**
  String get sectionSelling;

  /// No description provided for @settingSaveNewItems.
  ///
  /// In en, this message translates to:
  /// **'Save new items as products'**
  String get settingSaveNewItems;

  /// No description provided for @settingSaveNewItemsHint.
  ///
  /// In en, this message translates to:
  /// **'An item typed during a sale is saved when its invoice is saved'**
  String get settingSaveNewItemsHint;

  /// No description provided for @settingUpdatePrices.
  ///
  /// In en, this message translates to:
  /// **'Update product price from sales'**
  String get settingUpdatePrices;

  /// No description provided for @settingUpdatePricesHint.
  ///
  /// In en, this message translates to:
  /// **'A price changed during a sale becomes the product\'s saved price'**
  String get settingUpdatePricesHint;

  /// No description provided for @settingAutoFavorites.
  ///
  /// In en, this message translates to:
  /// **'Automatic favorites'**
  String get settingAutoFavorites;

  /// No description provided for @settingAutoFavoritesHint.
  ///
  /// In en, this message translates to:
  /// **'After your starred products, the favorites bar shows the best sellers of the last 30 days'**
  String get settingAutoFavoritesHint;

  /// No description provided for @invoiceSavedTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice saved'**
  String get invoiceSavedTitle;

  /// No description provided for @invoiceNoLabel.
  ///
  /// In en, this message translates to:
  /// **'Invoice no. {no}'**
  String invoiceNoLabel(String no);

  /// No description provided for @printInvoice.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get printInvoice;

  /// No description provided for @sharePdf.
  ///
  /// In en, this message translates to:
  /// **'Share as PDF'**
  String get sharePdf;

  /// No description provided for @newSale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get newSale;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get backToHome;

  /// No description provided for @setupPrinterQuestion.
  ///
  /// In en, this message translates to:
  /// **'Do you have a receipt printer?'**
  String get setupPrinterQuestion;

  /// No description provided for @setupPrinterYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, I print invoices'**
  String get setupPrinterYes;

  /// No description provided for @setupPrinterNo.
  ///
  /// In en, this message translates to:
  /// **'No, I share them (image / WhatsApp)'**
  String get setupPrinterNo;

  /// No description provided for @invoiceSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Invoice & printing'**
  String get invoiceSettingsTitle;

  /// No description provided for @previewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get previewTitle;

  /// No description provided for @sectionOutput.
  ///
  /// In en, this message translates to:
  /// **'After saving a sale'**
  String get sectionOutput;

  /// No description provided for @outputModePrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get outputModePrint;

  /// No description provided for @outputModeShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get outputModeShare;

  /// No description provided for @outputModeBoth.
  ///
  /// In en, this message translates to:
  /// **'Print + Share'**
  String get outputModeBoth;

  /// No description provided for @outputModeHint.
  ///
  /// In en, this message translates to:
  /// **'Sets the main button after a sale is saved. The other actions stay in the menu.'**
  String get outputModeHint;

  /// No description provided for @sectionPrinter.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth printer'**
  String get sectionPrinter;

  /// No description provided for @printerNone.
  ///
  /// In en, this message translates to:
  /// **'No printer selected'**
  String get printerNone;

  /// No description provided for @choosePrinter.
  ///
  /// In en, this message translates to:
  /// **'Choose printer'**
  String get choosePrinter;

  /// No description provided for @forgetPrinter.
  ///
  /// In en, this message translates to:
  /// **'Forget this printer'**
  String get forgetPrinter;

  /// No description provided for @pairedDevicesTitle.
  ///
  /// In en, this message translates to:
  /// **'Paired devices'**
  String get pairedDevicesTitle;

  /// No description provided for @noPairedDevices.
  ///
  /// In en, this message translates to:
  /// **'No paired devices. Pair the printer in the phone\'s Bluetooth settings first (the PIN is usually 0000 or 1234), then come back.'**
  String get noPairedDevices;

  /// No description provided for @openBluetoothSettings.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth settings'**
  String get openBluetoothSettings;

  /// No description provided for @openAppSettings.
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get openAppSettings;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @testPrint.
  ///
  /// In en, this message translates to:
  /// **'Test print'**
  String get testPrint;

  /// No description provided for @feedLinesLabel.
  ///
  /// In en, this message translates to:
  /// **'Blank lines after printing'**
  String get feedLinesLabel;

  /// No description provided for @cutPaperLabel.
  ///
  /// In en, this message translates to:
  /// **'Cut the paper after printing'**
  String get cutPaperLabel;

  /// No description provided for @cutPaperHint.
  ///
  /// In en, this message translates to:
  /// **'Only for printers with a cutter'**
  String get cutPaperHint;

  /// No description provided for @sectionPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get sectionPaper;

  /// No description provided for @paperWidthLabel.
  ///
  /// In en, this message translates to:
  /// **'Paper width'**
  String get paperWidthLabel;

  /// No description provided for @paperWidthPreset.
  ///
  /// In en, this message translates to:
  /// **'{mm} mm'**
  String paperWidthPreset(String mm);

  /// No description provided for @paperCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get paperCustom;

  /// No description provided for @paperWidthMmLabel.
  ///
  /// In en, this message translates to:
  /// **'Paper width (mm)'**
  String get paperWidthMmLabel;

  /// No description provided for @printerDpiLabel.
  ///
  /// In en, this message translates to:
  /// **'Printer resolution (DPI)'**
  String get printerDpiLabel;

  /// No description provided for @sideMarginLabel.
  ///
  /// In en, this message translates to:
  /// **'Side margin (mm)'**
  String get sideMarginLabel;

  /// No description provided for @printableWidthInfo.
  ///
  /// In en, this message translates to:
  /// **'Printable width: {dots} dots ({mm} mm)'**
  String printableWidthInfo(String dots, String mm);

  /// No description provided for @advancedSection.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get advancedSection;

  /// No description provided for @printableDotsOverrideLabel.
  ///
  /// In en, this message translates to:
  /// **'Printable width (dots)'**
  String get printableDotsOverrideLabel;

  /// No description provided for @printableDotsOverrideHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to compute it from the paper width, margin and DPI'**
  String get printableDotsOverrideHint;

  /// No description provided for @invalidNumber.
  ///
  /// In en, this message translates to:
  /// **'Invalid number'**
  String get invalidNumber;

  /// No description provided for @sectionShop.
  ///
  /// In en, this message translates to:
  /// **'Shop details'**
  String get sectionShop;

  /// No description provided for @shopNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get shopNameLabel;

  /// No description provided for @logoLabel.
  ///
  /// In en, this message translates to:
  /// **'Logo'**
  String get logoLabel;

  /// No description provided for @logoHint.
  ///
  /// In en, this message translates to:
  /// **'A simple dark logo on a white background prints best'**
  String get logoHint;

  /// No description provided for @pickLogo.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get pickLogo;

  /// No description provided for @removeLogo.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLogo;

  /// No description provided for @logoError.
  ///
  /// In en, this message translates to:
  /// **'This image could not be read'**
  String get logoError;

  /// No description provided for @headerTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Header text'**
  String get headerTextLabel;

  /// No description provided for @footerTextLabel.
  ///
  /// In en, this message translates to:
  /// **'Footer text'**
  String get footerTextLabel;

  /// No description provided for @sectionContent.
  ///
  /// In en, this message translates to:
  /// **'Invoice content'**
  String get sectionContent;

  /// No description provided for @invoiceLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Invoice language'**
  String get invoiceLanguageLabel;

  /// No description provided for @baseFontSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get baseFontSizeLabel;

  /// No description provided for @showItemCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Item code'**
  String get showItemCodeLabel;

  /// No description provided for @showUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get showUnitLabel;

  /// No description provided for @showUnitPriceLabel.
  ///
  /// In en, this message translates to:
  /// **'Unit price'**
  String get showUnitPriceLabel;

  /// No description provided for @showDateTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Date and time'**
  String get showDateTimeLabel;

  /// No description provided for @showInvoiceNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Invoice number'**
  String get showInvoiceNumberLabel;

  /// No description provided for @showCustomerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get showCustomerNameLabel;

  /// No description provided for @showCustomerPhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer phone'**
  String get showCustomerPhoneLabel;

  /// No description provided for @showAccountNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Account / card number'**
  String get showAccountNumberLabel;

  /// No description provided for @maskAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Hide all but the last 4 digits'**
  String get maskAccountLabel;

  /// No description provided for @sectionCurrency.
  ///
  /// In en, this message translates to:
  /// **'Currencies on the invoice'**
  String get sectionCurrency;

  /// No description provided for @currencyDisplayLabel.
  ///
  /// In en, this message translates to:
  /// **'Write the currency as'**
  String get currencyDisplayLabel;

  /// No description provided for @currencyDisplaySymbol.
  ///
  /// In en, this message translates to:
  /// **'Symbol'**
  String get currencyDisplaySymbol;

  /// No description provided for @currencyDisplayCode.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get currencyDisplayCode;

  /// No description provided for @extraCurrenciesLabel.
  ///
  /// In en, this message translates to:
  /// **'Also show the total in'**
  String get extraCurrenciesLabel;

  /// No description provided for @extraCurrenciesHint.
  ///
  /// In en, this message translates to:
  /// **'Up to 2 currencies. The exchange rate used is printed under the total.'**
  String get extraCurrenciesHint;

  /// No description provided for @extraCurrenciesNone.
  ///
  /// In en, this message translates to:
  /// **'Set the exchange rate of another currency to use this.'**
  String get extraCurrenciesNone;

  /// No description provided for @sectionSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing'**
  String get sectionSharing;

  /// No description provided for @shareWidthLabel.
  ///
  /// In en, this message translates to:
  /// **'Width of the shared image'**
  String get shareWidthLabel;

  /// No description provided for @shareWidthSameAsPaper.
  ///
  /// In en, this message translates to:
  /// **'Same as the paper'**
  String get shareWidthSameAsPaper;

  /// No description provided for @shareWidthMmLabel.
  ///
  /// In en, this message translates to:
  /// **'Share width (mm)'**
  String get shareWidthMmLabel;

  /// No description provided for @defaultCountryCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Default country code'**
  String get defaultCountryCodeLabel;

  /// No description provided for @defaultCountryCodeHint.
  ///
  /// In en, this message translates to:
  /// **'For sending on WhatsApp: a number typed as 09… is sent to +{code} 9…'**
  String defaultCountryCodeHint(String code);

  /// No description provided for @invoiceCustomerLabel.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get invoiceCustomerLabel;

  /// No description provided for @invoicePhoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get invoicePhoneLabel;

  /// No description provided for @invoiceAccountLabel.
  ///
  /// In en, this message translates to:
  /// **'Account no.'**
  String get invoiceAccountLabel;

  /// No description provided for @sampleItemSugar.
  ///
  /// In en, this message translates to:
  /// **'Sugar'**
  String get sampleItemSugar;

  /// No description provided for @sampleItemTea.
  ///
  /// In en, this message translates to:
  /// **'Tea'**
  String get sampleItemTea;

  /// No description provided for @sampleItemPackage.
  ///
  /// In en, this message translates to:
  /// **'Internet package 100 GB'**
  String get sampleItemPackage;

  /// No description provided for @sampleUnitKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get sampleUnitKg;

  /// No description provided for @sampleUnitBox.
  ///
  /// In en, this message translates to:
  /// **'box'**
  String get sampleUnitBox;

  /// No description provided for @sampleCustomerName.
  ///
  /// In en, this message translates to:
  /// **'Ahmad'**
  String get sampleCustomerName;

  /// No description provided for @shareInvoice.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareInvoice;

  /// No description provided for @shareAsImage.
  ///
  /// In en, this message translates to:
  /// **'Share as image'**
  String get shareAsImage;

  /// No description provided for @sendOnWhatsApp.
  ///
  /// In en, this message translates to:
  /// **'Send on WhatsApp'**
  String get sendOnWhatsApp;

  /// No description provided for @saveImageToPhone.
  ///
  /// In en, this message translates to:
  /// **'Save image to phone'**
  String get saveImageToPhone;

  /// No description provided for @savePdfToPhone.
  ///
  /// In en, this message translates to:
  /// **'Save PDF to phone'**
  String get savePdfToPhone;

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;

  /// No description provided for @printSent.
  ///
  /// In en, this message translates to:
  /// **'Sent to the printer'**
  String get printSent;

  /// No description provided for @savedToPhone.
  ///
  /// In en, this message translates to:
  /// **'Saved to {path}'**
  String savedToPhone(String path);

  /// No description provided for @whatsAppNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp is not installed — opening the share menu instead'**
  String get whatsAppNotInstalled;

  /// No description provided for @whatsAppUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Could not open the chat directly — opening the share menu instead'**
  String get whatsAppUnsupported;

  /// No description provided for @whatsAppChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Send with'**
  String get whatsAppChooseTitle;

  /// No description provided for @whatsAppRegular.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsAppRegular;

  /// No description provided for @whatsAppBusiness.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp Business'**
  String get whatsAppBusiness;

  /// No description provided for @whatsAppPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp number'**
  String get whatsAppPhoneTitle;

  /// No description provided for @whatsAppPhoneHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 0944 123 456'**
  String get whatsAppPhoneHint;

  /// No description provided for @invalidPhone.
  ///
  /// In en, this message translates to:
  /// **'Invalid phone number'**
  String get invalidPhone;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @errorNoPrinter.
  ///
  /// In en, this message translates to:
  /// **'No printer selected. Choose one in Settings → Invoice & printing.'**
  String get errorNoPrinter;

  /// No description provided for @errorBluetoothUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This device has no Bluetooth.'**
  String get errorBluetoothUnsupported;

  /// No description provided for @errorBluetoothOff.
  ///
  /// In en, this message translates to:
  /// **'Bluetooth is off. Turn it on and try again.'**
  String get errorBluetoothOff;

  /// No description provided for @errorBluetoothPermission.
  ///
  /// In en, this message translates to:
  /// **'Souqi is not allowed to use Bluetooth. Allow \"Nearby devices\" in the app settings.'**
  String get errorBluetoothPermission;

  /// No description provided for @errorPrinterUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Cannot reach the printer {name}. Check that it is switched on, close by and paired.'**
  String errorPrinterUnreachable(String name);

  /// No description provided for @errorPrinterWrite.
  ///
  /// In en, this message translates to:
  /// **'The connection to the printer dropped while printing. Try again.'**
  String get errorPrinterWrite;

  /// No description provided for @errorStoragePermission.
  ///
  /// In en, this message translates to:
  /// **'Souqi is not allowed to save files. Allow storage access in the app settings.'**
  String get errorStoragePermission;

  /// No description provided for @errorOutputUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {detail}'**
  String errorOutputUnknown(String detail);

  /// No description provided for @storageTitle.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get storageTitle;

  /// No description provided for @storageInvoiceCount.
  ///
  /// In en, this message translates to:
  /// **'Invoices stored'**
  String get storageInvoiceCount;

  /// No description provided for @storageDatabaseSize.
  ///
  /// In en, this message translates to:
  /// **'Database size'**
  String get storageDatabaseSize;

  /// No description provided for @optimizingStorage.
  ///
  /// In en, this message translates to:
  /// **'Optimizing…'**
  String get optimizingStorage;

  /// No description provided for @sizeInBytes.
  ///
  /// In en, this message translates to:
  /// **'{size} B'**
  String sizeInBytes(String size);

  /// No description provided for @sizeInKilobytes.
  ///
  /// In en, this message translates to:
  /// **'{size} KB'**
  String sizeInKilobytes(String size);

  /// No description provided for @sizeInMegabytes.
  ///
  /// In en, this message translates to:
  /// **'{size} MB'**
  String sizeInMegabytes(String size);

  /// No description provided for @archiveSearchProductHint.
  ///
  /// In en, this message translates to:
  /// **'Product sold'**
  String get archiveSearchProductHint;

  /// No description provided for @archiveSearchCustomerHint.
  ///
  /// In en, this message translates to:
  /// **'Customer, phone or card number'**
  String get archiveSearchCustomerHint;

  /// No description provided for @archiveInvoiceNoHint.
  ///
  /// In en, this message translates to:
  /// **'Invoice no.'**
  String get archiveInvoiceNoHint;

  /// No description provided for @archiveFilters.
  ///
  /// In en, this message translates to:
  /// **'Filters'**
  String get archiveFilters;

  /// No description provided for @archiveClearFilters.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get archiveClearFilters;

  /// No description provided for @periodAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get periodAll;

  /// No description provided for @periodToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get periodToday;

  /// No description provided for @periodYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get periodYesterday;

  /// No description provided for @periodThisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get periodThisWeek;

  /// No description provided for @periodThisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get periodThisMonth;

  /// No description provided for @periodCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get periodCustom;

  /// No description provided for @periodRangeLabel.
  ///
  /// In en, this message translates to:
  /// **'{from} — {to}'**
  String periodRangeLabel(String from, String to);

  /// No description provided for @archiveNoInvoices.
  ///
  /// In en, this message translates to:
  /// **'No invoices yet'**
  String get archiveNoInvoices;

  /// No description provided for @archiveNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No invoice matches these filters'**
  String get archiveNoMatches;

  /// No description provided for @archiveItemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Items: {count}'**
  String archiveItemsLabel(String count);

  /// No description provided for @archiveMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices · {total}'**
  String archiveMatchCount(String count, String total);

  /// No description provided for @archiveDeleteRange.
  ///
  /// In en, this message translates to:
  /// **'Delete these invoices'**
  String get archiveDeleteRange;

  /// No description provided for @archiveDeleteRangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete invoices?'**
  String get archiveDeleteRangeTitle;

  /// No description provided for @archiveDeleteRangeMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices totalling {total} will be deleted. Products, invoice numbering and sold card codes are kept.'**
  String archiveDeleteRangeMessage(String count, String total);

  /// No description provided for @archiveDeleteWholeArchive.
  ///
  /// In en, this message translates to:
  /// **'No date range is set, so this deletes EVERY invoice in the archive.'**
  String get archiveDeleteWholeArchive;

  /// No description provided for @archiveDeleteRangeEmpty.
  ///
  /// In en, this message translates to:
  /// **'There are no invoices in this range.'**
  String get archiveDeleteRangeEmpty;

  /// No description provided for @archiveDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices deleted'**
  String archiveDeletedMessage(String count);

  /// No description provided for @deleteInvoiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete invoice?'**
  String get deleteInvoiceTitle;

  /// No description provided for @deleteInvoiceMessage.
  ///
  /// In en, this message translates to:
  /// **'Invoice {number} will be deleted. Products and sold card codes are kept, and the number is never reused.'**
  String deleteInvoiceMessage(String number);

  /// No description provided for @invoiceDeletedMessage.
  ///
  /// In en, this message translates to:
  /// **'Invoice {number} deleted'**
  String invoiceDeletedMessage(String number);

  /// No description provided for @invoiceNotFound.
  ///
  /// In en, this message translates to:
  /// **'This invoice is no longer in the archive.'**
  String get invoiceNotFound;

  /// No description provided for @invoiceCopyMark.
  ///
  /// In en, this message translates to:
  /// **'COPY'**
  String get invoiceCopyMark;

  /// No description provided for @invoiceCopyNotice.
  ///
  /// In en, this message translates to:
  /// **'Anything printed or shared from here is marked as a copy.'**
  String get invoiceCopyNotice;

  /// No description provided for @sectionArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get sectionArchive;

  /// No description provided for @settingAutoDelete.
  ///
  /// In en, this message translates to:
  /// **'Auto-delete old invoices'**
  String get settingAutoDelete;

  /// No description provided for @settingAutoDeleteHint.
  ///
  /// In en, this message translates to:
  /// **'Invoices older than this are deleted on the first launch of each day. Products, invoice numbering and sold card codes are kept.'**
  String get settingAutoDeleteHint;

  /// No description provided for @retentionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get retentionOff;

  /// No description provided for @retentionDays.
  ///
  /// In en, this message translates to:
  /// **'After {days} days'**
  String retentionDays(String days);

  /// No description provided for @retentionCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom…'**
  String get retentionCustom;

  /// No description provided for @retentionCustomTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete invoices older than'**
  String get retentionCustomTitle;

  /// No description provided for @retentionCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get retentionCustomHint;

  /// No description provided for @retentionNotice.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices older than {days} days were deleted'**
  String retentionNotice(String count, String days);

  /// No description provided for @statsBaseCurrencyNote.
  ///
  /// In en, this message translates to:
  /// **'All amounts in {code}, at the exchange rate stored with each invoice.'**
  String statsBaseCurrencyNote(String code);

  /// No description provided for @statsTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Total sales'**
  String get statsTotalSales;

  /// No description provided for @statsInvoiceCount.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get statsInvoiceCount;

  /// No description provided for @statsAverageInvoice.
  ///
  /// In en, this message translates to:
  /// **'Average invoice'**
  String get statsAverageInvoice;

  /// No description provided for @statsTotalDiscounts.
  ///
  /// In en, this message translates to:
  /// **'Discounts'**
  String get statsTotalDiscounts;

  /// No description provided for @statsPreviousValue.
  ///
  /// In en, this message translates to:
  /// **'Previous period: {value}'**
  String statsPreviousValue(String value);

  /// No description provided for @statsTrendUp.
  ///
  /// In en, this message translates to:
  /// **'Up {percent}%'**
  String statsTrendUp(String percent);

  /// No description provided for @statsTrendDown.
  ///
  /// In en, this message translates to:
  /// **'Down {percent}%'**
  String statsTrendDown(String percent);

  /// No description provided for @statsTrendFlat.
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get statsTrendFlat;

  /// No description provided for @statsTrendNew.
  ///
  /// In en, this message translates to:
  /// **'New — there was none in the previous period'**
  String get statsTrendNew;

  /// No description provided for @statsTrendGone.
  ///
  /// In en, this message translates to:
  /// **'None in this period'**
  String get statsTrendGone;

  /// No description provided for @statsTopBySales.
  ///
  /// In en, this message translates to:
  /// **'Top 10 by number of sales'**
  String get statsTopBySales;

  /// No description provided for @statsTopByAmount.
  ///
  /// In en, this message translates to:
  /// **'Top 10 by amount'**
  String get statsTopByAmount;

  /// No description provided for @statsSalesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sales'**
  String statsSalesCount(String count);

  /// No description provided for @statsUnsavedItemBadge.
  ///
  /// In en, this message translates to:
  /// **'not a product'**
  String get statsUnsavedItemBadge;

  /// No description provided for @statsNoData.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period'**
  String get statsNoData;

  /// No description provided for @statsByCurrency.
  ///
  /// In en, this message translates to:
  /// **'Sales by invoice currency'**
  String get statsByCurrency;

  /// No description provided for @statsShowByCurrency.
  ///
  /// In en, this message translates to:
  /// **'Break down by invoice currency'**
  String get statsShowByCurrency;

  /// No description provided for @debugTools.
  ///
  /// In en, this message translates to:
  /// **'Developer tools (debug build)'**
  String get debugTools;

  /// No description provided for @debugSeedInvoices.
  ///
  /// In en, this message translates to:
  /// **'Create test invoices'**
  String get debugSeedInvoices;

  /// No description provided for @debugSeedTitle.
  ///
  /// In en, this message translates to:
  /// **'How many invoices?'**
  String get debugSeedTitle;

  /// No description provided for @debugSeedHint.
  ///
  /// In en, this message translates to:
  /// **'Spread over the last 365 days, for performance testing'**
  String get debugSeedHint;

  /// No description provided for @debugSeedDone.
  ///
  /// In en, this message translates to:
  /// **'{count} test invoices created'**
  String debugSeedDone(String count);

  /// No description provided for @archiveCounting.
  ///
  /// In en, this message translates to:
  /// **'Counting…'**
  String get archiveCounting;

  /// No description provided for @archiveDeletingTitle.
  ///
  /// In en, this message translates to:
  /// **'Deleting invoices'**
  String get archiveDeletingTitle;

  /// No description provided for @archiveDeletingHint.
  ///
  /// In en, this message translates to:
  /// **'Keep the app open until this finishes.'**
  String get archiveDeletingHint;

  /// No description provided for @progressCount.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String progressCount(String done, String total);

  /// No description provided for @archiveDeletePartial.
  ///
  /// In en, this message translates to:
  /// **'{deleted} invoices deleted, {remaining} still there. Try again.'**
  String archiveDeletePartial(String deleted, String remaining);

  /// No description provided for @archiveDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'The cleanup stopped: {detail}'**
  String archiveDeleteFailed(String detail);

  /// No description provided for @housekeepingBusy.
  ///
  /// In en, this message translates to:
  /// **'Another cleanup is still running.'**
  String get housekeepingBusy;

  /// No description provided for @debugSeedingTitle.
  ///
  /// In en, this message translates to:
  /// **'Creating test invoices'**
  String get debugSeedingTitle;

  /// No description provided for @archiveDeleteNeedsNoSearch.
  ///
  /// In en, this message translates to:
  /// **'Clear the search to delete a period'**
  String get archiveDeleteNeedsNoSearch;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
