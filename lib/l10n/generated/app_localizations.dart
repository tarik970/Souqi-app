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
  /// **'This product is used in invoices or as an account\'s default package, so it was deactivated instead of deleted.'**
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

  /// No description provided for @navCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get navCustomers;

  /// No description provided for @navDue.
  ///
  /// In en, this message translates to:
  /// **'Due for renewal'**
  String get navDue;

  /// No description provided for @customerName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get customerName;

  /// No description provided for @customerPhone.
  ///
  /// In en, this message translates to:
  /// **'Phone (optional)'**
  String get customerPhone;

  /// No description provided for @notesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get notesLabel;

  /// No description provided for @addCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get addCustomer;

  /// No description provided for @editCustomer.
  ///
  /// In en, this message translates to:
  /// **'Edit customer'**
  String get editCustomer;

  /// No description provided for @newCustomer.
  ///
  /// In en, this message translates to:
  /// **'New customer'**
  String get newCustomer;

  /// No description provided for @searchCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'Search by name or phone'**
  String get searchCustomersHint;

  /// No description provided for @noCustomers.
  ///
  /// In en, this message translates to:
  /// **'No customers yet'**
  String get noCustomers;

  /// No description provided for @deactivate.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get deactivate;

  /// No description provided for @reactivate.
  ///
  /// In en, this message translates to:
  /// **'Reactivate'**
  String get reactivate;

  /// No description provided for @deactivateCustomerTitle.
  ///
  /// In en, this message translates to:
  /// **'Deactivate customer?'**
  String get deactivateCustomerTitle;

  /// No description provided for @deactivateCustomerMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" will no longer appear in the search or in the due list. Their invoices and accounts are kept, and you can reactivate them at any time.'**
  String deactivateCustomerMessage(String name);

  /// No description provided for @customerNotFound.
  ///
  /// In en, this message translates to:
  /// **'This customer is no longer there'**
  String get customerNotFound;

  /// No description provided for @callCustomer.
  ///
  /// In en, this message translates to:
  /// **'Call'**
  String get callCustomer;

  /// No description provided for @whatsAppCustomer.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsAppCustomer;

  /// No description provided for @cannotDial.
  ///
  /// In en, this message translates to:
  /// **'Could not open the phone dialer'**
  String get cannotDial;

  /// No description provided for @whatsAppChatNotInstalled.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp is not installed on this phone'**
  String get whatsAppChatNotInstalled;

  /// No description provided for @whatsAppChatFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the WhatsApp chat'**
  String get whatsAppChatFailed;

  /// No description provided for @accountsTitle.
  ///
  /// In en, this message translates to:
  /// **'Cards & accounts'**
  String get accountsTitle;

  /// No description provided for @addAccount.
  ///
  /// In en, this message translates to:
  /// **'Add card / account'**
  String get addAccount;

  /// No description provided for @editAccount.
  ///
  /// In en, this message translates to:
  /// **'Edit card / account'**
  String get editAccount;

  /// No description provided for @noAccounts.
  ///
  /// In en, this message translates to:
  /// **'No cards or accounts yet'**
  String get noAccounts;

  /// No description provided for @accountsCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No cards} =1{1 card / account} other{{count} cards / accounts}}'**
  String accountsCount(int count);

  /// No description provided for @accountNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Card / account number'**
  String get accountNumberLabel;

  /// No description provided for @accountLabelLabel.
  ///
  /// In en, this message translates to:
  /// **'Type (e.g. internet card, ADSL line)'**
  String get accountLabelLabel;

  /// No description provided for @accountProviderLabel.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get accountProviderLabel;

  /// No description provided for @accountPackageLabel.
  ///
  /// In en, this message translates to:
  /// **'Default package'**
  String get accountPackageLabel;

  /// No description provided for @accountNoPackage.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get accountNoPackage;

  /// No description provided for @accountRenewalDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Renewal period (days)'**
  String get accountRenewalDaysLabel;

  /// No description provided for @accountRenewalDaysHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 30. Leave empty for no schedule.'**
  String get accountRenewalDaysHint;

  /// No description provided for @accountLastRenewalLabel.
  ///
  /// In en, this message translates to:
  /// **'Last renewal'**
  String get accountLastRenewalLabel;

  /// No description provided for @accountNextDueLabel.
  ///
  /// In en, this message translates to:
  /// **'Next due date'**
  String get accountNextDueLabel;

  /// No description provided for @accountNextDueHint.
  ///
  /// In en, this message translates to:
  /// **'Last renewal + period. You can also set it by hand.'**
  String get accountNextDueHint;

  /// No description provided for @accountNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get accountNotSet;

  /// No description provided for @clearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearDate;

  /// No description provided for @accountDuplicateTitle.
  ///
  /// In en, this message translates to:
  /// **'Number already registered'**
  String get accountDuplicateTitle;

  /// No description provided for @accountDuplicateMessage.
  ///
  /// In en, this message translates to:
  /// **'{number} is already registered with the same provider for: {customer}. Save it anyway?'**
  String accountDuplicateMessage(String number, String customer);

  /// No description provided for @saveAnyway.
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get saveAnyway;

  /// No description provided for @firstAccountSection.
  ///
  /// In en, this message translates to:
  /// **'First card / account (optional)'**
  String get firstAccountSection;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Purchases & renewals'**
  String get historyTitle;

  /// No description provided for @noHistory.
  ///
  /// In en, this message translates to:
  /// **'No invoices yet'**
  String get noHistory;

  /// No description provided for @showMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get showMore;

  /// No description provided for @customerInvoiceCount.
  ///
  /// In en, this message translates to:
  /// **'Invoices'**
  String get customerInvoiceCount;

  /// No description provided for @customerTotalSpent.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get customerTotalSpent;

  /// No description provided for @customerLastPurchase.
  ///
  /// In en, this message translates to:
  /// **'Last purchase'**
  String get customerLastPurchase;

  /// No description provided for @historyMoreItems.
  ///
  /// In en, this message translates to:
  /// **'+{count} more'**
  String historyMoreItems(String count);

  /// No description provided for @quickSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Customer, phone or card number'**
  String get quickSearchHint;

  /// No description provided for @quickSearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No customer or card matches \"{query}\"'**
  String quickSearchEmpty(String query);

  /// No description provided for @quickSearchPrompt.
  ///
  /// In en, this message translates to:
  /// **'Type a name, a phone number or a card / account number'**
  String get quickSearchPrompt;

  /// No description provided for @renew.
  ///
  /// In en, this message translates to:
  /// **'Renew'**
  String get renew;

  /// No description provided for @packageLabel.
  ///
  /// In en, this message translates to:
  /// **'Package: {name}'**
  String packageLabel(String name);

  /// No description provided for @lastRenewalLabel.
  ///
  /// In en, this message translates to:
  /// **'Last renewal: {date}'**
  String lastRenewalLabel(String date);

  /// No description provided for @dueOverdueBy.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Overdue by 1 day} other{Overdue by {days} days}}'**
  String dueOverdueBy(int days);

  /// No description provided for @dueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today'**
  String get dueToday;

  /// No description provided for @dueInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Due tomorrow} other{Due in {days} days}}'**
  String dueInDays(int days);

  /// No description provided for @dueOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get dueOk;

  /// No description provided for @dueNoDate.
  ///
  /// In en, this message translates to:
  /// **'No due date'**
  String get dueNoDate;

  /// No description provided for @dueSectionOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue ({count})'**
  String dueSectionOverdue(String count);

  /// No description provided for @dueSectionToday.
  ///
  /// In en, this message translates to:
  /// **'Due today ({count})'**
  String dueSectionToday(String count);

  /// No description provided for @dueSectionSoon.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{Due tomorrow ({count})} other{Due in the next {days} days ({count})}}'**
  String dueSectionSoon(int days, String count);

  /// No description provided for @dueEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing is due for renewal'**
  String get dueEmpty;

  /// No description provided for @dueSeeAll.
  ///
  /// In en, this message translates to:
  /// **'See all ({count})'**
  String dueSeeAll(String count);

  /// No description provided for @sendReminder.
  ///
  /// In en, this message translates to:
  /// **'Remind on WhatsApp'**
  String get sendReminder;

  /// No description provided for @sectionCustomers.
  ///
  /// In en, this message translates to:
  /// **'Customers & renewals'**
  String get sectionCustomers;

  /// No description provided for @settingDueSoonDays.
  ///
  /// In en, this message translates to:
  /// **'Due-soon window'**
  String get settingDueSoonDays;

  /// No description provided for @settingDueSoonDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Accounts due within this many days are listed under \"Due for renewal\"'**
  String get settingDueSoonDaysHint;

  /// No description provided for @daysCount.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String daysCount(int days);

  /// No description provided for @settingReminderText.
  ///
  /// In en, this message translates to:
  /// **'Renewal reminder message'**
  String get settingReminderText;

  /// No description provided for @settingReminderTextHint.
  ///
  /// In en, this message translates to:
  /// **'Opened in the customer\'s WhatsApp chat from the due list. You can still edit it there before sending.'**
  String get settingReminderTextHint;

  /// No description provided for @reminderDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminder message'**
  String get reminderDialogTitle;

  /// No description provided for @reminderPlaceholdersHint.
  ///
  /// In en, this message translates to:
  /// **'These are replaced for each customer: {placeholders}'**
  String reminderPlaceholdersHint(String placeholders);

  /// No description provided for @reminderResetDefault.
  ///
  /// In en, this message translates to:
  /// **'Use default'**
  String get reminderResetDefault;

  /// No description provided for @reminderDefaultText.
  ///
  /// In en, this message translates to:
  /// **'Hello {name}, this is a reminder that your subscription ({account}) is due for renewal on {date}.'**
  String reminderDefaultText(String name, String account, String date);

  /// No description provided for @saleCustomerChip.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get saleCustomerChip;

  /// No description provided for @saleCustomerRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove customer'**
  String get saleCustomerRemove;

  /// No description provided for @accountRequiredMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" must be linked to a customer\'s card or account'**
  String accountRequiredMessage(String name);

  /// No description provided for @chooseAccount.
  ///
  /// In en, this message translates to:
  /// **'Choose account'**
  String get chooseAccount;

  /// No description provided for @customerPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose customer'**
  String get customerPickerTitle;

  /// No description provided for @newCustomerNamed.
  ///
  /// In en, this message translates to:
  /// **'New customer \"{text}\"'**
  String newCustomerNamed(String text);

  /// No description provided for @newCustomerWithPhone.
  ///
  /// In en, this message translates to:
  /// **'New customer with phone {text}'**
  String newCustomerWithPhone(String text);

  /// No description provided for @newCustomerWithAccount.
  ///
  /// In en, this message translates to:
  /// **'New customer with card no. {text}'**
  String newCustomerWithAccount(String text);

  /// No description provided for @packageChangedNotice.
  ///
  /// In en, this message translates to:
  /// **'This renewal sold \"{name}\", which is not the account\'s default package.'**
  String packageChangedNotice(String name);

  /// No description provided for @makeDefaultPackage.
  ///
  /// In en, this message translates to:
  /// **'Make this the default package for this account'**
  String get makeDefaultPackage;

  /// No description provided for @defaultPackageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Default package updated'**
  String get defaultPackageUpdated;

  /// No description provided for @renewNewSaleTitle.
  ///
  /// In en, this message translates to:
  /// **'Start a new sale?'**
  String get renewNewSaleTitle;

  /// No description provided for @renewNewSaleMessage.
  ///
  /// In en, this message translates to:
  /// **'There are items in the current sale. Starting the renewal will remove them.'**
  String get renewNewSaleMessage;

  /// No description provided for @renewNoPackage.
  ///
  /// In en, this message translates to:
  /// **'This account has no default package. Add the item to sell.'**
  String get renewNoPackage;

  /// No description provided for @statsRenewals.
  ///
  /// In en, this message translates to:
  /// **'Renewals'**
  String get statsRenewals;

  /// No description provided for @statsTopPackages.
  ///
  /// In en, this message translates to:
  /// **'Top packages'**
  String get statsTopPackages;

  /// No description provided for @statsTopCustomers.
  ///
  /// In en, this message translates to:
  /// **'Sales per customer'**
  String get statsTopCustomers;

  /// No description provided for @statsInvoicesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} invoices'**
  String statsInvoicesCount(String count);

  /// No description provided for @debugSeedCustomers.
  ///
  /// In en, this message translates to:
  /// **'Create test customers'**
  String get debugSeedCustomers;

  /// No description provided for @debugSeedCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'Each with 2 cards / accounts, for testing the quick search and the due list'**
  String get debugSeedCustomersHint;

  /// No description provided for @debugSeedCustomersDone.
  ///
  /// In en, this message translates to:
  /// **'{count} test customers created'**
  String debugSeedCustomersDone(String count);

  /// No description provided for @debugSeedingCustomersTitle.
  ///
  /// In en, this message translates to:
  /// **'Creating test customers'**
  String get debugSeedingCustomersTitle;

  /// No description provided for @sectionSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get sectionSecurity;

  /// No description provided for @pinLockTitle.
  ///
  /// In en, this message translates to:
  /// **'PIN lock'**
  String get pinLockTitle;

  /// No description provided for @pinNotSet.
  ///
  /// In en, this message translates to:
  /// **'No PIN set'**
  String get pinNotSet;

  /// No description provided for @pinIsSet.
  ///
  /// In en, this message translates to:
  /// **'A PIN is set'**
  String get pinIsSet;

  /// No description provided for @pinSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a PIN'**
  String get pinSetTitle;

  /// No description provided for @pinChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'New PIN'**
  String get pinChangeTitle;

  /// No description provided for @pinSetIntro.
  ///
  /// In en, this message translates to:
  /// **'The PIN protects card codes and other sensitive actions. Use 4 to 6 digits.'**
  String get pinSetIntro;

  /// No description provided for @pinNeededIntro.
  ///
  /// In en, this message translates to:
  /// **'A PIN is needed here and none is set yet. Choose one now: 4 to 6 digits.'**
  String get pinNeededIntro;

  /// No description provided for @pinNewLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinNewLabel;

  /// No description provided for @pinConfirmLabel.
  ///
  /// In en, this message translates to:
  /// **'Repeat the PIN'**
  String get pinConfirmLabel;

  /// No description provided for @pinInvalid.
  ///
  /// In en, this message translates to:
  /// **'The PIN must be 4 to 6 digits'**
  String get pinInvalid;

  /// No description provided for @pinMismatch.
  ///
  /// In en, this message translates to:
  /// **'The two PINs are not the same'**
  String get pinMismatch;

  /// No description provided for @pinEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN'**
  String get pinEnterTitle;

  /// No description provided for @pinLabel.
  ///
  /// In en, this message translates to:
  /// **'PIN'**
  String get pinLabel;

  /// No description provided for @pinWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong PIN. {count, plural, =0{No attempts left} =1{1 attempt left} other{{count} attempts left}}'**
  String pinWrong(int count);

  /// No description provided for @pinLocked.
  ///
  /// In en, this message translates to:
  /// **'Too many wrong attempts. Try again in {time}.'**
  String pinLocked(String time);

  /// No description provided for @pinConfirmAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get pinConfirmAction;

  /// No description provided for @pinForgetWarning.
  ///
  /// In en, this message translates to:
  /// **'Next you will get a recovery code: the only way back in if the PIN is forgotten.'**
  String get pinForgetWarning;

  /// No description provided for @pinChangeAction.
  ///
  /// In en, this message translates to:
  /// **'Change PIN'**
  String get pinChangeAction;

  /// No description provided for @pinRemoveAction.
  ///
  /// In en, this message translates to:
  /// **'Remove PIN'**
  String get pinRemoveAction;

  /// No description provided for @pinRemoveTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove the PIN?'**
  String get pinRemoveTitle;

  /// No description provided for @pinRemoveMessage.
  ///
  /// In en, this message translates to:
  /// **'Without a PIN, whoever holds this phone can choose a new one and then reveal or reprint card codes.'**
  String get pinRemoveMessage;

  /// No description provided for @pinSaved.
  ///
  /// In en, this message translates to:
  /// **'PIN saved'**
  String get pinSaved;

  /// No description provided for @pinRemoved.
  ///
  /// In en, this message translates to:
  /// **'PIN removed'**
  String get pinRemoved;

  /// No description provided for @pinReasonReprint.
  ///
  /// In en, this message translates to:
  /// **'This invoice carries card codes. Printing or sharing it again needs the PIN and is marked as a copy.'**
  String get pinReasonReprint;

  /// No description provided for @pinReasonCodes.
  ///
  /// In en, this message translates to:
  /// **'Card codes are protected by the PIN.'**
  String get pinReasonCodes;

  /// No description provided for @auditLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Audit log'**
  String get auditLogTitle;

  /// No description provided for @auditLogHint.
  ///
  /// In en, this message translates to:
  /// **'Codes revealed, reprinted, voided, loaded or exported'**
  String get auditLogHint;

  /// No description provided for @auditEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sensitive actions in this period'**
  String get auditEmpty;

  /// No description provided for @loadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get loadMore;

  /// No description provided for @auditCodeImport.
  ///
  /// In en, this message translates to:
  /// **'Codes loaded'**
  String get auditCodeImport;

  /// No description provided for @auditCodeReveal.
  ///
  /// In en, this message translates to:
  /// **'Code shown on screen'**
  String get auditCodeReveal;

  /// No description provided for @auditCodeLookup.
  ///
  /// In en, this message translates to:
  /// **'Search by code'**
  String get auditCodeLookup;

  /// No description provided for @auditCodeVoid.
  ///
  /// In en, this message translates to:
  /// **'Code voided'**
  String get auditCodeVoid;

  /// No description provided for @auditCodeRestore.
  ///
  /// In en, this message translates to:
  /// **'Code returned to stock'**
  String get auditCodeRestore;

  /// No description provided for @auditCodeExport.
  ///
  /// In en, this message translates to:
  /// **'Codes exported'**
  String get auditCodeExport;

  /// No description provided for @auditCodeExpiryChange.
  ///
  /// In en, this message translates to:
  /// **'Expiry date changed'**
  String get auditCodeExpiryChange;

  /// No description provided for @auditBatchDelete.
  ///
  /// In en, this message translates to:
  /// **'Batch deleted'**
  String get auditBatchDelete;

  /// No description provided for @auditInvoiceReprint.
  ///
  /// In en, this message translates to:
  /// **'Invoice with codes printed again'**
  String get auditInvoiceReprint;

  /// No description provided for @auditPinSet.
  ///
  /// In en, this message translates to:
  /// **'PIN set'**
  String get auditPinSet;

  /// No description provided for @auditPinChange.
  ///
  /// In en, this message translates to:
  /// **'PIN changed'**
  String get auditPinChange;

  /// No description provided for @auditPinRemove.
  ///
  /// In en, this message translates to:
  /// **'PIN removed'**
  String get auditPinRemove;

  /// No description provided for @auditDetailFound.
  ///
  /// In en, this message translates to:
  /// **'{count} found'**
  String auditDetailFound(String count);

  /// No description provided for @auditDetailReason.
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String auditDetailReason(String reason);

  /// No description provided for @cardsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cards'**
  String cardsCount(String count);

  /// No description provided for @serialLabel.
  ///
  /// In en, this message translates to:
  /// **'S/N {serial}'**
  String serialLabel(String serial);

  /// No description provided for @navCardStock.
  ///
  /// In en, this message translates to:
  /// **'Card stock'**
  String get navCardStock;

  /// No description provided for @stockAvailable.
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get stockAvailable;

  /// No description provided for @stockSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get stockSold;

  /// No description provided for @stockVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get stockVoid;

  /// No description provided for @stockExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get stockExpired;

  /// No description provided for @stockCount.
  ///
  /// In en, this message translates to:
  /// **'In stock: {count}'**
  String stockCount(String count);

  /// No description provided for @stockOut.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get stockOut;

  /// No description provided for @stockLowWarning.
  ///
  /// In en, this message translates to:
  /// **'{name}: only {count} left'**
  String stockLowWarning(String name, String count);

  /// No description provided for @stockOutWarning.
  ///
  /// In en, this message translates to:
  /// **'{name}: out of stock'**
  String stockOutWarning(String name);

  /// No description provided for @cardStockEmpty.
  ///
  /// In en, this message translates to:
  /// **'No product is sold from code stock yet. Open a card / service product and turn on \"Sold from code stock\".'**
  String get cardStockEmpty;

  /// No description provided for @cardStockLookup.
  ///
  /// In en, this message translates to:
  /// **'Find a card by its code'**
  String get cardStockLookup;

  /// No description provided for @expiredCodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Expired codes'**
  String get expiredCodesTitle;

  /// No description provided for @expiredCodesNotice.
  ///
  /// In en, this message translates to:
  /// **'{count} expired codes are not being sold. Decide what to do with them.'**
  String expiredCodesNotice(String count);

  /// No description provided for @expiredEmpty.
  ///
  /// In en, this message translates to:
  /// **'No expired codes'**
  String get expiredEmpty;

  /// No description provided for @batchesTitle.
  ///
  /// In en, this message translates to:
  /// **'Batches'**
  String get batchesTitle;

  /// No description provided for @batchAdd.
  ///
  /// In en, this message translates to:
  /// **'Load codes'**
  String get batchAdd;

  /// No description provided for @batchEmpty.
  ///
  /// In en, this message translates to:
  /// **'No codes loaded yet'**
  String get batchEmpty;

  /// No description provided for @batchCostEach.
  ///
  /// In en, this message translates to:
  /// **'Cost {amount} each'**
  String batchCostEach(String amount);

  /// No description provided for @batchExpires.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String batchExpires(String date);

  /// No description provided for @batchDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete batch'**
  String get batchDelete;

  /// No description provided for @batchDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this batch?'**
  String get batchDeleteTitle;

  /// No description provided for @batchDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Its {count} unsold codes will be deleted for good.'**
  String batchDeleteMessage(String count);

  /// No description provided for @batchDeleteBlocked.
  ///
  /// In en, this message translates to:
  /// **'This batch has sold codes and cannot be deleted.'**
  String get batchDeleteBlocked;

  /// No description provided for @batchDeleted.
  ///
  /// In en, this message translates to:
  /// **'{count} codes deleted'**
  String batchDeleted(String count);

  /// No description provided for @batchShowCodes.
  ///
  /// In en, this message translates to:
  /// **'Show the codes'**
  String get batchShowCodes;

  /// No description provided for @batchChangeExpiry.
  ///
  /// In en, this message translates to:
  /// **'Change expiry date'**
  String get batchChangeExpiry;

  /// No description provided for @expiryChanged.
  ///
  /// In en, this message translates to:
  /// **'Expiry date changed'**
  String get expiryChanged;

  /// No description provided for @exportCodes.
  ///
  /// In en, this message translates to:
  /// **'Export unsold codes'**
  String get exportCodes;

  /// No description provided for @exportWarning.
  ///
  /// In en, this message translates to:
  /// **'The file holds the codes in the clear. Anyone who gets it can use the cards.'**
  String get exportWarning;

  /// No description provided for @exportShare.
  ///
  /// In en, this message translates to:
  /// **'Share the file'**
  String get exportShare;

  /// No description provided for @exportSave.
  ///
  /// In en, this message translates to:
  /// **'Save to phone'**
  String get exportSave;

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'{count} codes exported'**
  String exportDone(String count);

  /// No description provided for @exportNothing.
  ///
  /// In en, this message translates to:
  /// **'No unsold codes to export'**
  String get exportNothing;

  /// No description provided for @addBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Load codes'**
  String get addBatchTitle;

  /// No description provided for @loadMethodPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get loadMethodPaste;

  /// No description provided for @loadMethodFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get loadMethodFile;

  /// No description provided for @loadMethodScan.
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get loadMethodScan;

  /// No description provided for @pasteLabel.
  ///
  /// In en, this message translates to:
  /// **'Codes'**
  String get pasteLabel;

  /// No description provided for @pasteHint.
  ///
  /// In en, this message translates to:
  /// **'One card per line'**
  String get pasteHint;

  /// No description provided for @pickFile.
  ///
  /// In en, this message translates to:
  /// **'Choose a .txt or .csv file'**
  String get pickFile;

  /// No description provided for @fileReadFailed.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read'**
  String get fileReadFailed;

  /// No description provided for @columnsLabel.
  ///
  /// In en, this message translates to:
  /// **'Each line holds'**
  String get columnsLabel;

  /// No description provided for @columnsCodeOnly.
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get columnsCodeOnly;

  /// No description provided for @columnsSerialCode.
  ///
  /// In en, this message translates to:
  /// **'Serial, code'**
  String get columnsSerialCode;

  /// No description provided for @columnsCodeSerial.
  ///
  /// In en, this message translates to:
  /// **'Code, serial'**
  String get columnsCodeSerial;

  /// No description provided for @importToAdd.
  ///
  /// In en, this message translates to:
  /// **'{count} to add'**
  String importToAdd(String count);

  /// No description provided for @importAdded.
  ///
  /// In en, this message translates to:
  /// **'{count} added'**
  String importAdded(String count);

  /// No description provided for @importDuplicates.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 duplicate skipped} other{{count} duplicates skipped}}'**
  String importDuplicates(int count);

  /// No description provided for @importEmpty.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 empty line} other{{count} empty lines}}'**
  String importEmpty(int count);

  /// No description provided for @importInvalid.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 line without a code} other{{count} lines without a code}}'**
  String importInvalid(int count);

  /// No description provided for @importHeaderSkipped.
  ///
  /// In en, this message translates to:
  /// **'heading line left out'**
  String get importHeaderSkipped;

  /// No description provided for @batchExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Expiry date (optional)'**
  String get batchExpiryLabel;

  /// No description provided for @noExpiry.
  ///
  /// In en, this message translates to:
  /// **'No expiry'**
  String get noExpiry;

  /// No description provided for @batchCostLabel.
  ///
  /// In en, this message translates to:
  /// **'Cost per card, {currency} (optional)'**
  String batchCostLabel(String currency);

  /// No description provided for @saveBatch.
  ///
  /// In en, this message translates to:
  /// **'Save the batch'**
  String get saveBatch;

  /// No description provided for @nothingToAdd.
  ///
  /// In en, this message translates to:
  /// **'Nothing new to add'**
  String get nothingToAdd;

  /// No description provided for @scanStart.
  ///
  /// In en, this message translates to:
  /// **'Scan cards with the camera'**
  String get scanStart;

  /// No description provided for @scanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan cards'**
  String get scanTitle;

  /// No description provided for @scanCount.
  ///
  /// In en, this message translates to:
  /// **'{count} scanned'**
  String scanCount(String count);

  /// No description provided for @scanDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Already scanned'**
  String get scanDuplicate;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at the QR code or barcode on the card'**
  String get scanHint;

  /// No description provided for @scanCameraError.
  ///
  /// In en, this message translates to:
  /// **'The camera could not be opened. Allow camera access for Souqi in the phone settings.'**
  String get scanCameraError;

  /// No description provided for @scannedCards.
  ///
  /// In en, this message translates to:
  /// **'Scanned cards: {count}'**
  String scannedCards(String count);

  /// No description provided for @clearScanned.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearScanned;

  /// No description provided for @codesTitle.
  ///
  /// In en, this message translates to:
  /// **'Card codes'**
  String get codesTitle;

  /// No description provided for @codesMaskedNote.
  ///
  /// In en, this message translates to:
  /// **'Codes are hidden on screen. They are printed and shared in full.'**
  String get codesMaskedNote;

  /// No description provided for @codeStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get codeStatusAvailable;

  /// No description provided for @codeStatusSold.
  ///
  /// In en, this message translates to:
  /// **'Sold'**
  String get codeStatusSold;

  /// No description provided for @codeStatusVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get codeStatusVoid;

  /// No description provided for @codeStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get codeStatusExpired;

  /// No description provided for @codeReveal.
  ///
  /// In en, this message translates to:
  /// **'Show the code'**
  String get codeReveal;

  /// No description provided for @codeVoid.
  ///
  /// In en, this message translates to:
  /// **'Void'**
  String get codeVoid;

  /// No description provided for @codeReturn.
  ///
  /// In en, this message translates to:
  /// **'Return to stock'**
  String get codeReturn;

  /// No description provided for @codeRevealedTitle.
  ///
  /// In en, this message translates to:
  /// **'Card code'**
  String get codeRevealedTitle;

  /// No description provided for @codeUnreadable.
  ///
  /// In en, this message translates to:
  /// **'This code cannot be read on this device.'**
  String get codeUnreadable;

  /// No description provided for @voidCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Void this code?'**
  String get voidCodeTitle;

  /// No description provided for @voidCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'The card will count as neither sold nor in stock. This is written to the audit log.'**
  String get voidCodeMessage;

  /// No description provided for @returnCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Return this code to stock?'**
  String get returnCodeTitle;

  /// No description provided for @returnCodeMessage.
  ///
  /// In en, this message translates to:
  /// **'The card becomes available for sale again. This is written to the audit log.'**
  String get returnCodeMessage;

  /// No description provided for @reasonLabel.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reasonLabel;

  /// No description provided for @codeVoided.
  ///
  /// In en, this message translates to:
  /// **'Code voided'**
  String get codeVoided;

  /// No description provided for @codeReturned.
  ///
  /// In en, this message translates to:
  /// **'Code returned to stock'**
  String get codeReturned;

  /// No description provided for @voidExpiredAction.
  ///
  /// In en, this message translates to:
  /// **'Void them'**
  String get voidExpiredAction;

  /// No description provided for @voidExpiredTitle.
  ///
  /// In en, this message translates to:
  /// **'Void the expired codes?'**
  String get voidExpiredTitle;

  /// No description provided for @voidExpiredMessage.
  ///
  /// In en, this message translates to:
  /// **'{count} expired codes of \"{name}\" will be voided.'**
  String voidExpiredMessage(String count, String name);

  /// No description provided for @expiredVoided.
  ///
  /// In en, this message translates to:
  /// **'{count} codes voided'**
  String expiredVoided(String count);

  /// No description provided for @batchCodesTitle.
  ///
  /// In en, this message translates to:
  /// **'Codes of the batch'**
  String get batchCodesTitle;

  /// No description provided for @lookupTitle.
  ///
  /// In en, this message translates to:
  /// **'Find a card'**
  String get lookupTitle;

  /// No description provided for @lookupHint.
  ///
  /// In en, this message translates to:
  /// **'Type or paste the full code'**
  String get lookupHint;

  /// No description provided for @lookupAction.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get lookupAction;

  /// No description provided for @lookupNotFound.
  ///
  /// In en, this message translates to:
  /// **'No card with this code'**
  String get lookupNotFound;

  /// No description provided for @lookupSoldOn.
  ///
  /// In en, this message translates to:
  /// **'Sold on {date}'**
  String lookupSoldOn(String date);

  /// No description provided for @lookupCustomer.
  ///
  /// In en, this message translates to:
  /// **'Customer: {name}'**
  String lookupCustomer(String name);

  /// No description provided for @lookupAccount.
  ///
  /// In en, this message translates to:
  /// **'Account: {number}'**
  String lookupAccount(String number);

  /// No description provided for @lookupOpenInvoice.
  ///
  /// In en, this message translates to:
  /// **'Open the invoice'**
  String get lookupOpenInvoice;

  /// No description provided for @lookupInvoiceDeleted.
  ///
  /// In en, this message translates to:
  /// **'The invoice itself was deleted from the archive'**
  String get lookupInvoiceDeleted;

  /// No description provided for @codeStockOnly.
  ///
  /// In en, this message translates to:
  /// **'Only {count} in stock'**
  String codeStockOnly(String count);

  /// No description provided for @codeStockShort.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\": {wanted} wanted, {available} in stock'**
  String codeStockShort(String name, String wanted, String available);

  /// No description provided for @codeStockUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The card codes cannot be read on this device, so nothing was sold.'**
  String get codeStockUnreadable;

  /// No description provided for @codeStockWholeCards.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" is sold in whole cards'**
  String codeStockWholeCards(String name);

  /// No description provided for @soldFromCodeStock.
  ///
  /// In en, this message translates to:
  /// **'Sold from code stock'**
  String get soldFromCodeStock;

  /// No description provided for @soldFromCodeStockHint.
  ///
  /// In en, this message translates to:
  /// **'Each sale takes a card code from the loaded stock and prints it on the invoice'**
  String get soldFromCodeStockHint;

  /// No description provided for @lowStockThresholdLabel.
  ///
  /// In en, this message translates to:
  /// **'Warn when stock falls to'**
  String get lowStockThresholdLabel;

  /// No description provided for @lowStockThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'Empty = no warning'**
  String get lowStockThresholdHint;

  /// No description provided for @manageStock.
  ///
  /// In en, this message translates to:
  /// **'Card stock of this product'**
  String get manageStock;

  /// No description provided for @sectionCardCodes.
  ///
  /// In en, this message translates to:
  /// **'Card codes'**
  String get sectionCardCodes;

  /// No description provided for @printCodeQrLabel.
  ///
  /// In en, this message translates to:
  /// **'Print a QR code of each card code'**
  String get printCodeQrLabel;

  /// No description provided for @codesSeparateSlipsLabel.
  ///
  /// In en, this message translates to:
  /// **'Print each card on a separate slip'**
  String get codesSeparateSlipsLabel;

  /// No description provided for @codesSeparateSlipsHint.
  ///
  /// In en, this message translates to:
  /// **'The printer feeds (and cuts) between slips. A shared image or PDF always holds everything.'**
  String get codesSeparateSlipsHint;

  /// No description provided for @invoiceSerialLabel.
  ///
  /// In en, this message translates to:
  /// **'S/N'**
  String get invoiceSerialLabel;

  /// No description provided for @invoiceExpiryLabel.
  ///
  /// In en, this message translates to:
  /// **'Valid until {date}'**
  String invoiceExpiryLabel(String date);

  /// No description provided for @invoiceCodeUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Code unavailable on this device'**
  String get invoiceCodeUnreadable;

  /// No description provided for @statsCardsSold.
  ///
  /// In en, this message translates to:
  /// **'Cards sold'**
  String get statsCardsSold;

  /// No description provided for @statsCardsProfit.
  ///
  /// In en, this message translates to:
  /// **'Profit {amount}'**
  String statsCardsProfit(String amount);

  /// No description provided for @statsCardsProfitPartial.
  ///
  /// In en, this message translates to:
  /// **'Profit {amount} (on the {count} with a known cost)'**
  String statsCardsProfitPartial(String amount, String count);

  /// No description provided for @debugSeedCards.
  ///
  /// In en, this message translates to:
  /// **'Create test card codes'**
  String get debugSeedCards;

  /// No description provided for @debugSeedCardsHint.
  ///
  /// In en, this message translates to:
  /// **'Two card products with made-up codes, one batch near expiry, for testing card sales'**
  String get debugSeedCardsHint;

  /// No description provided for @debugSeedCardsDone.
  ///
  /// In en, this message translates to:
  /// **'{count} test codes created'**
  String debugSeedCardsDone(String count);

  /// No description provided for @batchSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'The batch could not be saved. Nothing was added.'**
  String get batchSaveFailed;

  /// No description provided for @importPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview (first 5)'**
  String get importPreviewTitle;

  /// No description provided for @recoveryCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Recovery code'**
  String get recoveryCodeTitle;

  /// No description provided for @recoveryCodeIntro.
  ///
  /// In en, this message translates to:
  /// **'If the PIN is ever forgotten, this code is the only way to choose a new one. It is shown once, now. Print it or save it, and keep it away from this phone.'**
  String get recoveryCodeIntro;

  /// No description provided for @recoveryCodeSaved.
  ///
  /// In en, this message translates to:
  /// **'I saved it'**
  String get recoveryCodeSaved;

  /// No description provided for @recoveryPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get recoveryPrint;

  /// No description provided for @recoveryShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get recoveryShare;

  /// No description provided for @recoverySlipTitle.
  ///
  /// In en, this message translates to:
  /// **'PIN recovery code'**
  String get recoverySlipTitle;

  /// No description provided for @recoverySlipHint.
  ///
  /// In en, this message translates to:
  /// **'Keep this safe. With this code the PIN can be reset.'**
  String get recoverySlipHint;

  /// No description provided for @pinForgot.
  ///
  /// In en, this message translates to:
  /// **'Forgot PIN?'**
  String get pinForgot;

  /// No description provided for @recoveryEnterTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset the PIN'**
  String get recoveryEnterTitle;

  /// No description provided for @recoveryEnterIntro.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code you were given when the PIN was chosen.'**
  String get recoveryEnterIntro;

  /// No description provided for @recoveryEnterIntroSigned.
  ///
  /// In en, this message translates to:
  /// **'Enter the recovery code you were given when the PIN was chosen, or a reset code from the developer.'**
  String get recoveryEnterIntroSigned;

  /// No description provided for @recoveryInvalid.
  ///
  /// In en, this message translates to:
  /// **'A recovery code has 12 letters and digits'**
  String get recoveryInvalid;

  /// No description provided for @recoveryWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong recovery code. {count, plural, =0{No attempts left} =1{1 attempt left} other{{count} attempts left}}'**
  String recoveryWrong(int count);

  /// No description provided for @recoveryRefused.
  ///
  /// In en, this message translates to:
  /// **'This code is not valid'**
  String get recoveryRefused;

  /// No description provided for @auditPinRecover.
  ///
  /// In en, this message translates to:
  /// **'PIN reset with the recovery code'**
  String get auditPinRecover;

  /// No description provided for @auditPinResetSigned.
  ///
  /// In en, this message translates to:
  /// **'PIN reset with a developer code'**
  String get auditPinResetSigned;

  /// No description provided for @recoveryMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'This PIN has no recovery code'**
  String get recoveryMissingTitle;

  /// No description provided for @recoveryMissingMessage.
  ///
  /// In en, this message translates to:
  /// **'If the PIN is forgotten there will be no way back in.'**
  String get recoveryMissingMessage;

  /// No description provided for @recoveryCreateNow.
  ///
  /// In en, this message translates to:
  /// **'Create a recovery code now'**
  String get recoveryCreateNow;

  /// No description provided for @recoveryCreateArmed.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN. The recovery code is shown next.'**
  String get recoveryCreateArmed;

  /// No description provided for @auditRecoveryCodeCreate.
  ///
  /// In en, this message translates to:
  /// **'Recovery code created'**
  String get auditRecoveryCodeCreate;

  /// No description provided for @debtsTitle.
  ///
  /// In en, this message translates to:
  /// **'Debts'**
  String get debtsTitle;

  /// No description provided for @debtorsTitle.
  ///
  /// In en, this message translates to:
  /// **'Debtors'**
  String get debtorsTitle;

  /// No description provided for @accountTab.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get accountTab;

  /// No description provided for @customerDetailsTab.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get customerDetailsTab;

  /// No description provided for @balanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balanceLabel;

  /// No description provided for @balanceOwes.
  ///
  /// In en, this message translates to:
  /// **'Owes {amount}'**
  String balanceOwes(String amount);

  /// No description provided for @balanceCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit {amount}'**
  String balanceCredit(String amount);

  /// No description provided for @balanceSettled.
  ///
  /// In en, this message translates to:
  /// **'No balance'**
  String get balanceSettled;

  /// No description provided for @creditLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit limit'**
  String get creditLimitLabel;

  /// No description provided for @lastPaymentLabel.
  ///
  /// In en, this message translates to:
  /// **'Last payment'**
  String get lastPaymentLabel;

  /// No description provided for @neverPaid.
  ///
  /// In en, this message translates to:
  /// **'No payment yet'**
  String get neverPaid;

  /// No description provided for @overdueBadge.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get overdueBadge;

  /// No description provided for @overdueAmount.
  ///
  /// In en, this message translates to:
  /// **'Overdue: {amount}'**
  String overdueAmount(String amount);

  /// No description provided for @oldestDebtAge.
  ///
  /// In en, this message translates to:
  /// **'Oldest debt: {days} days'**
  String oldestDebtAge(String days);

  /// No description provided for @oldestDebtToday.
  ///
  /// In en, this message translates to:
  /// **'Oldest debt: today'**
  String get oldestDebtToday;

  /// No description provided for @overLimitBadge.
  ///
  /// In en, this message translates to:
  /// **'Over limit'**
  String get overLimitBadge;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recordPayment;

  /// No description provided for @addDebt.
  ///
  /// In en, this message translates to:
  /// **'Add debt'**
  String get addDebt;

  /// No description provided for @openingBalance.
  ///
  /// In en, this message translates to:
  /// **'Opening balance'**
  String get openingBalance;

  /// No description provided for @adjustment.
  ///
  /// In en, this message translates to:
  /// **'Adjustment'**
  String get adjustment;

  /// No description provided for @accountStatement.
  ///
  /// In en, this message translates to:
  /// **'Account statement'**
  String get accountStatement;

  /// No description provided for @sendDebtReminder.
  ///
  /// In en, this message translates to:
  /// **'Remind on WhatsApp'**
  String get sendDebtReminder;

  /// No description provided for @debtReminderNoPhone.
  ///
  /// In en, this message translates to:
  /// **'This customer has no phone number'**
  String get debtReminderNoPhone;

  /// No description provided for @entryInvoice.
  ///
  /// In en, this message translates to:
  /// **'Invoice {no}'**
  String entryInvoice(String no);

  /// No description provided for @entryReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt {no}'**
  String entryReceipt(String no);

  /// No description provided for @entryPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get entryPayment;

  /// No description provided for @entryManualDebt.
  ///
  /// In en, this message translates to:
  /// **'Debt'**
  String get entryManualDebt;

  /// No description provided for @entryReversalOf.
  ///
  /// In en, this message translates to:
  /// **'Reversal: {what}'**
  String entryReversalOf(String what);

  /// No description provided for @entryReversed.
  ///
  /// In en, this message translates to:
  /// **'Reversed'**
  String get entryReversed;

  /// No description provided for @ledgerEmpty.
  ///
  /// In en, this message translates to:
  /// **'No entries yet'**
  String get ledgerEmpty;

  /// No description provided for @ledgerNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No entries match the filter'**
  String get ledgerNoMatch;

  /// No description provided for @ledgerDebit.
  ///
  /// In en, this message translates to:
  /// **'Debit'**
  String get ledgerDebit;

  /// No description provided for @ledgerCredit.
  ///
  /// In en, this message translates to:
  /// **'Credit'**
  String get ledgerCredit;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get dateLabel;

  /// No description provided for @descriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get descriptionLabel;

  /// No description provided for @typeFilterDebts.
  ///
  /// In en, this message translates to:
  /// **'Debts'**
  String get typeFilterDebts;

  /// No description provided for @typeFilterPayments.
  ///
  /// In en, this message translates to:
  /// **'Payments'**
  String get typeFilterPayments;

  /// No description provided for @typeFilterOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get typeFilterOther;

  /// No description provided for @invoiceDeletedNote.
  ///
  /// In en, this message translates to:
  /// **'Invoice {no} was deleted from the archive. The debt stays in the account.'**
  String invoiceDeletedNote(String no);

  /// No description provided for @openInvoice.
  ///
  /// In en, this message translates to:
  /// **'Open invoice'**
  String get openInvoice;

  /// No description provided for @viewReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get viewReceipt;

  /// No description provided for @reverseEntry.
  ///
  /// In en, this message translates to:
  /// **'Reverse entry'**
  String get reverseEntry;

  /// No description provided for @reverseTitle.
  ///
  /// In en, this message translates to:
  /// **'Reverse this entry?'**
  String get reverseTitle;

  /// No description provided for @reverseMessage.
  ///
  /// In en, this message translates to:
  /// **'The entry stays in the ledger, struck through, and a reversal entry cancels it. This cannot be undone.'**
  String get reverseMessage;

  /// No description provided for @reasonRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the reason'**
  String get reasonRequired;

  /// No description provided for @pinReasonReverse.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN to reverse a ledger entry.'**
  String get pinReasonReverse;

  /// No description provided for @pinReasonAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN to adjust a balance.'**
  String get pinReasonAdjustment;

  /// No description provided for @pinReasonCreditLimit.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN to sell over the credit limit.'**
  String get pinReasonCreditLimit;

  /// No description provided for @pinReasonDebtAccess.
  ///
  /// In en, this message translates to:
  /// **'Enter the PIN to open the debts.'**
  String get pinReasonDebtAccess;

  /// No description provided for @entryReversedSnack.
  ///
  /// In en, this message translates to:
  /// **'Entry reversed'**
  String get entryReversedSnack;

  /// No description provided for @dueOnLabel.
  ///
  /// In en, this message translates to:
  /// **'Due {date}'**
  String dueOnLabel(String date);

  /// No description provided for @paymentMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get paymentMethodLabel;

  /// No description provided for @methodCash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get methodCash;

  /// No description provided for @methodTransfer.
  ///
  /// In en, this message translates to:
  /// **'Transfer'**
  String get methodTransfer;

  /// No description provided for @methodOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get methodOther;

  /// No description provided for @amountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amountLabel;

  /// No description provided for @amountInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount greater than zero'**
  String get amountInvalid;

  /// No description provided for @payFullBalance.
  ///
  /// In en, this message translates to:
  /// **'Pay full balance'**
  String get payFullBalance;

  /// No description provided for @paymentCurrencyLabel.
  ///
  /// In en, this message translates to:
  /// **'Currency'**
  String get paymentCurrencyLabel;

  /// No description provided for @paymentRateLabel.
  ///
  /// In en, this message translates to:
  /// **'Rate: {base} per 1 {code}'**
  String paymentRateLabel(String base, String code);

  /// No description provided for @paymentCountsAs.
  ///
  /// In en, this message translates to:
  /// **'Counts as {amount}'**
  String paymentCountsAs(String amount);

  /// No description provided for @paymentOverBalance.
  ///
  /// In en, this message translates to:
  /// **'More than the balance: the customer will have a credit of {amount}.'**
  String paymentOverBalance(String amount);

  /// No description provided for @noteOptional.
  ///
  /// In en, this message translates to:
  /// **'Note (optional)'**
  String get noteOptional;

  /// No description provided for @receiptTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment receipt'**
  String get receiptTitle;

  /// No description provided for @receiptNoLabel.
  ///
  /// In en, this message translates to:
  /// **'Receipt no. {no}'**
  String receiptNoLabel(String no);

  /// No description provided for @receiptReceivedFrom.
  ///
  /// In en, this message translates to:
  /// **'Received from'**
  String get receiptReceivedFrom;

  /// No description provided for @receiptAmountLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get receiptAmountLabel;

  /// No description provided for @receiptPaidAs.
  ///
  /// In en, this message translates to:
  /// **'Received as'**
  String get receiptPaidAs;

  /// No description provided for @receiptMethodLabel.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get receiptMethodLabel;

  /// No description provided for @receiptNoteLabel.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get receiptNoteLabel;

  /// No description provided for @receiptReversedMark.
  ///
  /// In en, this message translates to:
  /// **'CANCELLED'**
  String get receiptReversedMark;

  /// No description provided for @previousBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'Previous balance'**
  String get previousBalanceLabel;

  /// No description provided for @newBalanceLabel.
  ///
  /// In en, this message translates to:
  /// **'New balance'**
  String get newBalanceLabel;

  /// No description provided for @paperOwes.
  ///
  /// In en, this message translates to:
  /// **'owes'**
  String get paperOwes;

  /// No description provided for @paperCredit.
  ///
  /// In en, this message translates to:
  /// **'credit'**
  String get paperCredit;

  /// No description provided for @statementOpening.
  ///
  /// In en, this message translates to:
  /// **'Balance brought forward'**
  String get statementOpening;

  /// No description provided for @statementClosing.
  ///
  /// In en, this message translates to:
  /// **'Closing balance'**
  String get statementClosing;

  /// No description provided for @statementTotalDebits.
  ///
  /// In en, this message translates to:
  /// **'Total debits'**
  String get statementTotalDebits;

  /// No description provided for @statementTotalCredits.
  ///
  /// In en, this message translates to:
  /// **'Total credits'**
  String get statementTotalCredits;

  /// No description provided for @statementNoEntries.
  ///
  /// In en, this message translates to:
  /// **'No entries in this period'**
  String get statementNoEntries;

  /// No description provided for @statementWholeAccount.
  ///
  /// In en, this message translates to:
  /// **'Whole account'**
  String get statementWholeAccount;

  /// No description provided for @statementLast30.
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get statementLast30;

  /// No description provided for @statementUntil.
  ///
  /// In en, this message translates to:
  /// **'Until {date}'**
  String statementUntil(String date);

  /// No description provided for @debtorsTotalOutstanding.
  ///
  /// In en, this message translates to:
  /// **'Total outstanding'**
  String get debtorsTotalOutstanding;

  /// No description provided for @debtorsOwingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} customers owe'**
  String debtorsOwingCount(String count);

  /// No description provided for @debtorsCreditTotal.
  ///
  /// In en, this message translates to:
  /// **'We owe customers: {amount}'**
  String debtorsCreditTotal(String amount);

  /// No description provided for @agingTitle.
  ///
  /// In en, this message translates to:
  /// **'Debts by age'**
  String get agingTitle;

  /// No description provided for @aging0to30.
  ///
  /// In en, this message translates to:
  /// **'0–30 days'**
  String get aging0to30;

  /// No description provided for @aging31to60.
  ///
  /// In en, this message translates to:
  /// **'31–60 days'**
  String get aging31to60;

  /// No description provided for @aging61to90.
  ///
  /// In en, this message translates to:
  /// **'61–90 days'**
  String get aging61to90;

  /// No description provided for @agingOver90.
  ///
  /// In en, this message translates to:
  /// **'Over 90 days'**
  String get agingOver90;

  /// No description provided for @sortLabel.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get sortLabel;

  /// No description provided for @sortByAmount.
  ///
  /// In en, this message translates to:
  /// **'Largest amount'**
  String get sortByAmount;

  /// No description provided for @sortByOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest debt'**
  String get sortByOldest;

  /// No description provided for @sortByLastPayment.
  ///
  /// In en, this message translates to:
  /// **'Longest since a payment'**
  String get sortByLastPayment;

  /// No description provided for @filterOverdue.
  ///
  /// In en, this message translates to:
  /// **'Overdue'**
  String get filterOverdue;

  /// No description provided for @filterOverLimit.
  ///
  /// In en, this message translates to:
  /// **'Over limit'**
  String get filterOverLimit;

  /// No description provided for @filterCreditBalances.
  ///
  /// In en, this message translates to:
  /// **'Credit balances'**
  String get filterCreditBalances;

  /// No description provided for @debtorsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nobody owes anything'**
  String get debtorsEmpty;

  /// No description provided for @debtorsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No matching customers'**
  String get debtorsNoMatch;

  /// No description provided for @lastPaymentOn.
  ///
  /// In en, this message translates to:
  /// **'Last payment {date}'**
  String lastPaymentOn(String date);

  /// No description provided for @paymentSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get paymentSheetTitle;

  /// No description provided for @payFull.
  ///
  /// In en, this message translates to:
  /// **'Paid in full'**
  String get payFull;

  /// No description provided for @payPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get payPartial;

  /// No description provided for @payCredit.
  ///
  /// In en, this message translates to:
  /// **'On credit'**
  String get payCredit;

  /// No description provided for @amountPaidLabel.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get amountPaidLabel;

  /// No description provided for @remainingAsDebt.
  ///
  /// In en, this message translates to:
  /// **'Goes on the account: {amount}'**
  String remainingAsDebt(String amount);

  /// No description provided for @cashReceivedLabel.
  ///
  /// In en, this message translates to:
  /// **'Cash received (optional)'**
  String get cashReceivedLabel;

  /// No description provided for @changeDue.
  ///
  /// In en, this message translates to:
  /// **'Change to give back: {amount}'**
  String changeDue(String amount);

  /// No description provided for @cashShort.
  ///
  /// In en, this message translates to:
  /// **'Less than the amount to pay'**
  String get cashShort;

  /// No description provided for @customerRequiredForDebt.
  ///
  /// In en, this message translates to:
  /// **'Choose a customer to sell on credit'**
  String get customerRequiredForDebt;

  /// No description provided for @chooseCustomer.
  ///
  /// In en, this message translates to:
  /// **'Choose customer'**
  String get chooseCustomer;

  /// No description provided for @changeCustomer.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get changeCustomer;

  /// No description provided for @useCreditBalance.
  ///
  /// In en, this message translates to:
  /// **'Use credit balance ({amount})'**
  String useCreditBalance(String amount);

  /// No description provided for @toPayNow.
  ///
  /// In en, this message translates to:
  /// **'To pay now: {amount}'**
  String toPayNow(String amount);

  /// No description provided for @dueDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get dueDateLabel;

  /// No description provided for @creditLimitWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Over the credit limit'**
  String get creditLimitWarningTitle;

  /// No description provided for @creditLimitWarning.
  ///
  /// In en, this message translates to:
  /// **'Balance {balance} + this sale {sale} = {newBalance}. The limit is {limit}.'**
  String creditLimitWarning(
    String balance,
    String sale,
    String newBalance,
    String limit,
  );

  /// No description provided for @overrideAndSave.
  ///
  /// In en, this message translates to:
  /// **'Override and save'**
  String get overrideAndSave;

  /// No description provided for @creditLimitConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Sell over the limit?'**
  String get creditLimitConfirmTitle;

  /// No description provided for @creditLimitBlocked.
  ///
  /// In en, this message translates to:
  /// **'This sale would take the customer over their credit limit.'**
  String get creditLimitBlocked;

  /// No description provided for @partialInvalid.
  ///
  /// In en, this message translates to:
  /// **'Enter an amount smaller than the amount to pay'**
  String get partialInvalid;

  /// No description provided for @salePaidLine.
  ///
  /// In en, this message translates to:
  /// **'Paid {paid} · on account {remaining}'**
  String salePaidLine(String paid, String remaining);

  /// No description provided for @invoicePaidLabel.
  ///
  /// In en, this message translates to:
  /// **'Paid'**
  String get invoicePaidLabel;

  /// No description provided for @invoiceFromCreditLabel.
  ///
  /// In en, this message translates to:
  /// **'From credit balance'**
  String get invoiceFromCreditLabel;

  /// No description provided for @invoiceRemainingLabel.
  ///
  /// In en, this message translates to:
  /// **'Remaining (debt)'**
  String get invoiceRemainingLabel;

  /// No description provided for @debtLinesSection.
  ///
  /// In en, this message translates to:
  /// **'Debt lines'**
  String get debtLinesSection;

  /// No description provided for @debtLinesHint.
  ///
  /// In en, this message translates to:
  /// **'Paid and remaining are printed only on a sale that was not paid in full; the balances only when the invoice has a customer.'**
  String get debtLinesHint;

  /// No description provided for @showPaidAmount.
  ///
  /// In en, this message translates to:
  /// **'Amount paid'**
  String get showPaidAmount;

  /// No description provided for @showRemainingAmount.
  ///
  /// In en, this message translates to:
  /// **'Remaining (debt) amount'**
  String get showRemainingAmount;

  /// No description provided for @showPreviousBalance.
  ///
  /// In en, this message translates to:
  /// **'Customer\'s previous balance'**
  String get showPreviousBalance;

  /// No description provided for @showNewBalance.
  ///
  /// In en, this message translates to:
  /// **'Customer\'s new balance'**
  String get showNewBalance;

  /// No description provided for @debtSettingsSection.
  ///
  /// In en, this message translates to:
  /// **'Debts'**
  String get debtSettingsSection;

  /// No description provided for @defaultDueDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Days to pay'**
  String get defaultDueDaysLabel;

  /// No description provided for @defaultDueDaysHint.
  ///
  /// In en, this message translates to:
  /// **'A new debt counts as overdue after this many days, unless the customer has their own.'**
  String get defaultDueDaysHint;

  /// No description provided for @debtRequirePinTitle.
  ///
  /// In en, this message translates to:
  /// **'PIN to open debts'**
  String get debtRequirePinTitle;

  /// No description provided for @debtRequirePinSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask for the PIN before the debtors list and a customer\'s account. Selling on credit never asks.'**
  String get debtRequirePinSubtitle;

  /// No description provided for @debtReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Debt reminder message'**
  String get debtReminderTitle;

  /// No description provided for @debtReminderHint.
  ///
  /// In en, this message translates to:
  /// **'The text WhatsApp opens with when you remind a customer of their balance'**
  String get debtReminderHint;

  /// No description provided for @debtReminderDefaultText.
  ///
  /// In en, this message translates to:
  /// **'Hello {name}, a reminder from {shop}: your balance is {balance}. Last payment: {lastPayment}. Thank you.'**
  String debtReminderDefaultText(
    String name,
    String shop,
    String balance,
    String lastPayment,
  );

  /// No description provided for @customerCreditLimitLabel.
  ///
  /// In en, this message translates to:
  /// **'Credit limit (optional)'**
  String get customerCreditLimitLabel;

  /// No description provided for @customerDueDaysLabel.
  ///
  /// In en, this message translates to:
  /// **'Days to pay (optional)'**
  String get customerDueDaysLabel;

  /// No description provided for @customerDueDaysHint.
  ///
  /// In en, this message translates to:
  /// **'Empty = the shop\'s default ({days})'**
  String customerDueDaysHint(String days);

  /// No description provided for @deactivateWithBalanceMessage.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" has an open balance: {balance}. Deactivating hides them from the search; the balance stays in the debtors list.'**
  String deactivateWithBalanceMessage(String name, String balance);

  /// No description provided for @deleteCarriesDebt.
  ///
  /// In en, this message translates to:
  /// **'{count} of these invoices carry debts. The debts are not deleted: they stay in the customers\' accounts.'**
  String deleteCarriesDebt(String count);

  /// No description provided for @deleteInvoiceCarriesDebt.
  ///
  /// In en, this message translates to:
  /// **'This invoice carries a debt. The debt is not deleted: it stays in the customer\'s account.'**
  String get deleteInvoiceCarriesDebt;

  /// No description provided for @statsOutstandingNow.
  ///
  /// In en, this message translates to:
  /// **'Outstanding now'**
  String get statsOutstandingNow;

  /// No description provided for @statsNewDebt.
  ///
  /// In en, this message translates to:
  /// **'New debt'**
  String get statsNewDebt;

  /// No description provided for @statsCollected.
  ///
  /// In en, this message translates to:
  /// **'Collected'**
  String get statsCollected;

  /// No description provided for @statsCollectionRate.
  ///
  /// In en, this message translates to:
  /// **'Collection rate'**
  String get statsCollectionRate;

  /// No description provided for @statsTopDebtors.
  ///
  /// In en, this message translates to:
  /// **'Top debtors'**
  String get statsTopDebtors;

  /// No description provided for @homeDebtsOverdue.
  ///
  /// In en, this message translates to:
  /// **'{count} overdue'**
  String homeDebtsOverdue(String count);

  /// No description provided for @homeDebtsNoOverdue.
  ///
  /// In en, this message translates to:
  /// **'Nobody overdue'**
  String get homeDebtsNoOverdue;

  /// No description provided for @debtLockedMessage.
  ///
  /// In en, this message translates to:
  /// **'Debts are protected by the PIN.'**
  String get debtLockedMessage;

  /// No description provided for @unlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get unlock;

  /// No description provided for @openingBalancesTitle.
  ///
  /// In en, this message translates to:
  /// **'Opening balances'**
  String get openingBalancesTitle;

  /// No description provided for @openingBalancesIntro.
  ///
  /// In en, this message translates to:
  /// **'Moving from a paper notebook: enter what each customer owes, one after another.'**
  String get openingBalancesIntro;

  /// No description provided for @openingExistingBalance.
  ///
  /// In en, this message translates to:
  /// **'Existing customer · {balance}'**
  String openingExistingBalance(String balance);

  /// No description provided for @openingOwesToggle.
  ///
  /// In en, this message translates to:
  /// **'Owes the shop'**
  String get openingOwesToggle;

  /// No description provided for @openingCreditToggle.
  ///
  /// In en, this message translates to:
  /// **'Shop owes them'**
  String get openingCreditToggle;

  /// No description provided for @openingDateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date (optional)'**
  String get openingDateLabel;

  /// No description provided for @openingAddedNew.
  ///
  /// In en, this message translates to:
  /// **'New customer'**
  String get openingAddedNew;

  /// No description provided for @openingAddedExisting.
  ///
  /// In en, this message translates to:
  /// **'Existing customer'**
  String get openingAddedExisting;

  /// No description provided for @openingSessionTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} entered'**
  String openingSessionTotal(String count);

  /// No description provided for @openingNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter the customer\'s name'**
  String get openingNameRequired;

  /// No description provided for @openingPickedCustomer.
  ///
  /// In en, this message translates to:
  /// **'Adding to {name}'**
  String openingPickedCustomer(String name);

  /// No description provided for @manualDebtNoteHint.
  ///
  /// In en, this message translates to:
  /// **'What is it for? (optional)'**
  String get manualDebtNoteHint;

  /// No description provided for @adjustmentIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase the debt'**
  String get adjustmentIncrease;

  /// No description provided for @adjustmentDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease the debt'**
  String get adjustmentDecrease;

  /// No description provided for @entrySaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get entrySaved;

  /// No description provided for @auditDebtReversal.
  ///
  /// In en, this message translates to:
  /// **'Ledger entry reversed'**
  String get auditDebtReversal;

  /// No description provided for @auditDebtAdjustment.
  ///
  /// In en, this message translates to:
  /// **'Balance adjusted'**
  String get auditDebtAdjustment;

  /// No description provided for @auditCreditLimitOverride.
  ///
  /// In en, this message translates to:
  /// **'Credit limit overridden'**
  String get auditCreditLimitOverride;

  /// No description provided for @seedDebtsTitle.
  ///
  /// In en, this message translates to:
  /// **'Seed debt ledger (debug)'**
  String get seedDebtsTitle;

  /// No description provided for @seedDebtsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'5,000 customers and 200,000 ledger entries, to try the debtors list at full size'**
  String get seedDebtsSubtitle;

  /// No description provided for @seedingDebts.
  ///
  /// In en, this message translates to:
  /// **'Writing ledger entries: {done} / {total}'**
  String seedingDebts(String done, String total);

  /// No description provided for @pinAutoLockTitle.
  ///
  /// In en, this message translates to:
  /// **'Lock again after'**
  String get pinAutoLockTitle;

  /// No description provided for @pinAutoLockHint.
  ///
  /// In en, this message translates to:
  /// **'What the PIN opens — the debts, the audit log, card codes — locks again after this long without a touch, and at once when you leave the app.'**
  String get pinAutoLockHint;

  /// No description provided for @minutesCount.
  ///
  /// In en, this message translates to:
  /// **'{minutes, plural, =1{1 minute} other{{minutes} minutes}}'**
  String minutesCount(int minutes);

  /// No description provided for @saleCreditButton.
  ///
  /// In en, this message translates to:
  /// **'Credit / Partial'**
  String get saleCreditButton;

  /// No description provided for @settingCashReceived.
  ///
  /// In en, this message translates to:
  /// **'Cash received field'**
  String get settingCashReceived;

  /// No description provided for @settingCashReceivedHint.
  ///
  /// In en, this message translates to:
  /// **'Show a small \"cash received\" field under the total that works out the change to give back'**
  String get settingCashReceivedHint;

  /// No description provided for @cashReceivedTitle.
  ///
  /// In en, this message translates to:
  /// **'Cash received'**
  String get cashReceivedTitle;

  /// No description provided for @cashReceivedValue.
  ///
  /// In en, this message translates to:
  /// **'Received {amount}'**
  String cashReceivedValue(String amount);

  /// No description provided for @changeShort.
  ///
  /// In en, this message translates to:
  /// **'Change {amount}'**
  String changeShort(String amount);

  /// No description provided for @cashReceivedClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get cashReceivedClear;

  /// No description provided for @printerLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Printer language'**
  String get printerLanguageLabel;

  /// No description provided for @printerLanguageReceipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt (ESC/POS)'**
  String get printerLanguageReceipt;

  /// No description provided for @printerLanguageReceiptHint.
  ///
  /// In en, this message translates to:
  /// **'Receipt printers — most printers'**
  String get printerLanguageReceiptHint;

  /// No description provided for @printerLanguageTspl.
  ///
  /// In en, this message translates to:
  /// **'Label (TSPL)'**
  String get printerLanguageTspl;

  /// No description provided for @printerLanguageTsplHint.
  ///
  /// In en, this message translates to:
  /// **'Label printers, or a dual printer left in label mode'**
  String get printerLanguageTsplHint;

  /// No description provided for @printerLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'Not sure? Keep Receipt. If nothing prints, try both in Printer diagnostics.'**
  String get printerLanguageHint;

  /// No description provided for @cutPaperTsplHint.
  ///
  /// In en, this message translates to:
  /// **'Not sent in label mode (TSPL)'**
  String get cutPaperTsplHint;

  /// No description provided for @printerDiagnosticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Printer diagnostics'**
  String get printerDiagnosticsTitle;

  /// No description provided for @printerDiagnosticsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing prints, or it prints garbage? Find the settings that work.'**
  String get printerDiagnosticsSubtitle;

  /// No description provided for @diagLanguageSection.
  ///
  /// In en, this message translates to:
  /// **'Which language does the printer understand?'**
  String get diagLanguageSection;

  /// No description provided for @diagLanguageIntro.
  ///
  /// In en, this message translates to:
  /// **'Print both tests. The one that comes out readable is the printer\'s language.'**
  String get diagLanguageIntro;

  /// No description provided for @testReceiptMode.
  ///
  /// In en, this message translates to:
  /// **'Test receipt mode (ESC/POS)'**
  String get testReceiptMode;

  /// No description provided for @testLabelMode.
  ///
  /// In en, this message translates to:
  /// **'Test label mode (TSPL)'**
  String get testLabelMode;

  /// No description provided for @diagLanguageHint.
  ///
  /// In en, this message translates to:
  /// **'If only the label test prints, choose Label (TSPL), or switch the printer to receipt mode (see its manual).'**
  String get diagLanguageHint;

  /// No description provided for @diagDidItPrint.
  ///
  /// In en, this message translates to:
  /// **'Did this test print?'**
  String get diagDidItPrint;

  /// No description provided for @diagPrintedUseThis.
  ///
  /// In en, this message translates to:
  /// **'Printed — use this'**
  String get diagPrintedUseThis;

  /// No description provided for @diagDidNotPrint.
  ///
  /// In en, this message translates to:
  /// **'Did not print'**
  String get diagDidNotPrint;

  /// No description provided for @diagWorks.
  ///
  /// In en, this message translates to:
  /// **'This one printed'**
  String get diagWorks;

  /// No description provided for @diagWorksInUse.
  ///
  /// In en, this message translates to:
  /// **'This one printed — in use'**
  String get diagWorksInUse;

  /// No description provided for @diagNotPrinted.
  ///
  /// In en, this message translates to:
  /// **'This one did not print'**
  String get diagNotPrinted;

  /// No description provided for @diagImageModeSection.
  ///
  /// In en, this message translates to:
  /// **'Image mode (ESC/POS)'**
  String get diagImageModeSection;

  /// No description provided for @diagImageModeHint.
  ///
  /// In en, this message translates to:
  /// **'For a receipt printer that connects but prints nothing or garbage: test each mode and keep the one that prints.'**
  String get diagImageModeHint;

  /// No description provided for @imageModeDefault.
  ///
  /// In en, this message translates to:
  /// **'{mode} (default)'**
  String imageModeDefault(String mode);

  /// No description provided for @imageModeEscStar.
  ///
  /// In en, this message translates to:
  /// **'{mode} (24-dot, line by line)'**
  String imageModeEscStar(String mode);

  /// No description provided for @testImageMode.
  ///
  /// In en, this message translates to:
  /// **'Test {mode}'**
  String testImageMode(String mode);

  /// No description provided for @diagCompatSection.
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get diagCompatSection;

  /// No description provided for @diagChunkSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Chunk size (bytes)'**
  String get diagChunkSizeLabel;

  /// No description provided for @diagChunkDelayLabel.
  ///
  /// In en, this message translates to:
  /// **'Delay between chunks (ms)'**
  String get diagChunkDelayLabel;

  /// No description provided for @diagCompatHint.
  ///
  /// In en, this message translates to:
  /// **'If long receipts stop halfway or lose lines, try smaller chunks and a longer delay.'**
  String get diagCompatHint;

  /// No description provided for @tsplOneIsBlackLabel.
  ///
  /// In en, this message translates to:
  /// **'Swap black and white (label mode)'**
  String get tsplOneIsBlackLabel;

  /// No description provided for @tsplOneIsBlackHint.
  ///
  /// In en, this message translates to:
  /// **'Turn on if the label test prints white text on a black background.'**
  String get tsplOneIsBlackHint;

  /// No description provided for @widthTooWideWarning.
  ///
  /// In en, this message translates to:
  /// **'The image is {dots} dots wide, but the print head for {paper} mm paper is usually {head} dots. A wider image is cut off or prints garbage.'**
  String widthTooWideWarning(String dots, String paper, String head);

  /// No description provided for @widthUseHead.
  ///
  /// In en, this message translates to:
  /// **'Use {head} dots'**
  String widthUseHead(String head);

  /// No description provided for @printerTestSlipTitle.
  ///
  /// In en, this message translates to:
  /// **'Print test'**
  String get printerTestSlipTitle;

  /// No description provided for @diagCalibrationSection.
  ///
  /// In en, this message translates to:
  /// **'Position on the paper'**
  String get diagCalibrationSection;

  /// No description provided for @diagCalibrationHint.
  ///
  /// In en, this message translates to:
  /// **'Print the calibration test: a frame with a ruler along the top, LEFT at one end and RIGHT at the other. Both ends of the frame must be on the paper. If one side is cut off, move the print away from it with the arrows. If it is still cut off, make it narrower with −. Each tap prints the test again.'**
  String get diagCalibrationHint;

  /// No description provided for @calibrationTest.
  ///
  /// In en, this message translates to:
  /// **'Calibration test'**
  String get calibrationTest;

  /// No description provided for @horizontalOffsetValue.
  ///
  /// In en, this message translates to:
  /// **'Horizontal offset: {offset} dots'**
  String horizontalOffsetValue(String offset);

  /// No description provided for @printableWidthValue.
  ///
  /// In en, this message translates to:
  /// **'Printable width: {dots} dots'**
  String printableWidthValue(String dots);

  /// No description provided for @calibrationShiftLeft.
  ///
  /// In en, this message translates to:
  /// **'Move the print left'**
  String get calibrationShiftLeft;

  /// No description provided for @calibrationShiftRight.
  ///
  /// In en, this message translates to:
  /// **'Move the print right'**
  String get calibrationShiftRight;

  /// No description provided for @calibrationNarrower.
  ///
  /// In en, this message translates to:
  /// **'Narrower'**
  String get calibrationNarrower;

  /// No description provided for @calibrationWider.
  ///
  /// In en, this message translates to:
  /// **'Wider'**
  String get calibrationWider;

  /// No description provided for @calibrationReceiptNote.
  ///
  /// In en, this message translates to:
  /// **'In receipt mode (ESC/POS) the print can only be moved to the right: an offset below 0 changes nothing.'**
  String get calibrationReceiptNote;

  /// No description provided for @printerCalibrationInfo.
  ///
  /// In en, this message translates to:
  /// **'Width {dots} dots · offset {offset}'**
  String printerCalibrationInfo(String dots, String offset);
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
