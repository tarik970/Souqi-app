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

  /// No description provided for @comingSoon.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoon;

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
