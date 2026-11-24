// ignore_for_file: deprecated_member_use

// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'سوقي';

  @override
  String get navSale => 'البيع';

  @override
  String get navProducts => 'المنتجات';

  @override
  String get navArchive => 'الأرشيف';

  @override
  String get navStats => 'الإحصائيات';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get comingSoon => 'قريباً';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get delete => 'حذف';

  @override
  String get edit => 'تعديل';

  @override
  String get add => 'إضافة';

  @override
  String get fieldRequired => 'هذا الحقل مطلوب';

  @override
  String get activeLabel => 'فعّال';

  @override
  String get setupWelcome => 'أهلاً بك في سوقي';

  @override
  String get setupIntro =>
      'اختر لغة التطبيق ونوع المحل. يمكنك تغييرهما لاحقاً من الإعدادات.';

  @override
  String get setupLanguage => 'لغة التطبيق';

  @override
  String get languageArabic => 'العربية';

  @override
  String get languageEnglish => 'English';

  @override
  String get setupShopType => 'نوع المحل';

  @override
  String get shopTypeGrocery => 'بقالة ومواد غذائية';

  @override
  String get shopTypeCards => 'كروت واشتراكات';

  @override
  String get shopTypeBoth => 'الاثنان معاً';

  @override
  String get setupStart => 'ابدأ';

  @override
  String get searchProductsHint => 'ابحث بالاسم أو الرمز';

  @override
  String get filterAll => 'الكل';

  @override
  String get filterGoods => 'بضائع';

  @override
  String get filterServices => 'كروت وخدمات';

  @override
  String get addProduct => 'إضافة منتج';

  @override
  String get editProduct => 'تعديل منتج';

  @override
  String get productName => 'الاسم';

  @override
  String get productCode => 'الرمز (اختياري)';

  @override
  String get productCodeTaken => 'هذا الرمز مستخدم من قبل';

  @override
  String get productKind => 'النوع';

  @override
  String get kindGoods => 'بضاعة';

  @override
  String get kindService => 'كرت / خدمة';

  @override
  String get productUnit => 'الوحدة';

  @override
  String get productPrice => 'السعر';

  @override
  String get invalidPrice => 'سعر غير صالح';

  @override
  String get productCurrency => 'عملة السعر';

  @override
  String get favoriteLabel => 'مفضّل';

  @override
  String get requiresAccount => 'يتطلب حساب زبون';

  @override
  String get requiresAccountHint =>
      'بيع هذا الصنف يجب أن يرتبط برقم كرت أو حساب الزبون';

  @override
  String get showInactive => 'إظهار غير الفعّالة';

  @override
  String get inactiveBadge => 'غير فعّال';

  @override
  String get deleteProductTitle => 'حذف المنتج؟';

  @override
  String deleteProductMessage(String name) {
    return 'حذف «$name»؟';
  }

  @override
  String get productDeactivatedMessage =>
      'هذا المنتج مستخدم في فواتير، لذلك أُلغي تفعيله بدل حذفه.';

  @override
  String get noProducts => 'لا توجد منتجات بعد';

  @override
  String get unitsTitle => 'الوحدات';

  @override
  String get addUnit => 'إضافة وحدة';

  @override
  String get editUnit => 'تعديل وحدة';

  @override
  String get unitName => 'اسم الوحدة';

  @override
  String get presetBadge => 'أساسية';

  @override
  String get deleteUnitTitle => 'حذف الوحدة؟';

  @override
  String deleteUnitMessage(String name) {
    return 'حذف «$name»؟';
  }

  @override
  String unitInUse(int count) {
    return 'لا يمكن الحذف: $count منتج يستخدم هذه الوحدة';
  }

  @override
  String get settingsCurrencies => 'العملات وأسعار الصرف';

  @override
  String get showPoweredBy => 'إظهار «مدعوم من سوقي» في أسفل الفاتورة';

  @override
  String get poweredByFooter => 'مدعوم من سوقي';

  @override
  String get aboutTitle => 'حول سوقي';

  @override
  String get aboutTagline => 'Souqi — نظام المبيعات والفواتير';

  @override
  String versionLabel(String version) {
    return 'الإصدار $version';
  }

  @override
  String get currenciesTitle => 'العملات';

  @override
  String get addCurrency => 'إضافة عملة';

  @override
  String get editCurrency => 'تعديل عملة';

  @override
  String get currencyCode => 'الرمز (مثل USD)';

  @override
  String get currencyCodeExists => 'هذا الرمز موجود';

  @override
  String get currencyNameAr => 'الاسم بالعربية';

  @override
  String get currencyNameEn => 'الاسم بالإنكليزية';

  @override
  String get currencySymbol => 'رمز العملة';

  @override
  String get currencyDecimals => 'عدد الخانات العشرية';

  @override
  String get exchangeRate => 'سعر الصرف';

  @override
  String rateHint(String code, String base) {
    return '1 $code = ؟ $base';
  }

  @override
  String rateDisplay(String code, String value, String base) {
    return '1 $code = $value $base';
  }

  @override
  String get invalidRate => 'سعر صرف غير صالح';

  @override
  String rateUpdatedAt(String date) {
    return 'آخر تحديث للسعر: $date';
  }

  @override
  String get rateNeverUpdated => 'لم يُحدَّد سعر الصرف بعد';

  @override
  String get updateRate => 'تحديث السعر';

  @override
  String get baseBadge => 'الأساسية';

  @override
  String get setAsBase => 'تعيين كعملة أساسية';

  @override
  String get baseChangeTitle => 'تغيير العملة الأساسية؟';

  @override
  String baseChangeWarning(String code) {
    return 'تُحسب المجاميع والإحصائيات بالعملة الأساسية. يجب إعادة إدخال أسعار صرف بقية العملات مقابل $code.';
  }

  @override
  String get baseChangeLocked =>
      'العملة الأساسية مقفلة لوجود فواتير أو ديون مسجّلة.';

  @override
  String get cannotDisableBase => 'لا يمكن تعطيل العملة الأساسية.';

  @override
  String get saleFavorites => 'المفضّلة';

  @override
  String get saleFavoritesHint =>
      'تظهر هنا المنتجات ذات النجمة والأكثر مبيعاً كأزرار سريعة';

  @override
  String get saleSearchHint => 'اكتب اسم الصنف أو رمزه';

  @override
  String get cartEmpty => 'السلة فارغة';

  @override
  String get cartEmptyHint => 'اكتب اسم الصنف لبيعه، أو اضغط على منتج مفضّل';

  @override
  String get noMatchingProducts => 'لا توجد منتجات مطابقة';

  @override
  String codeNotFound(String code) {
    return 'لا يوجد صنف بالرمز $code';
  }

  @override
  String get invoiceCurrency => 'عملة الفاتورة';

  @override
  String get subtotalLabel => 'المجموع قبل الحسم';

  @override
  String get discountLabel => 'الحسم';

  @override
  String get totalLabel => 'الإجمالي';

  @override
  String itemsCount(int count) {
    return 'الأصناف: $count';
  }

  @override
  String get quantityLabel => 'الكمية';

  @override
  String get unitPriceLabel => 'سعر الوحدة';

  @override
  String get unitPriceThisSaleOnly =>
      'لهذه الفاتورة فقط — سعر المنتج المحفوظ لا يتغيّر';

  @override
  String get lineTotalLabel => 'إجمالي السطر';

  @override
  String get addToCart => 'إضافة';

  @override
  String get updateLine => 'تحديث';

  @override
  String get clearCartTitle => 'تفريغ السلة؟';

  @override
  String get clearCartMessage => 'ستُحذف كل أصناف هذه الفاتورة.';

  @override
  String get clearCart => 'تفريغ السلة';

  @override
  String get removeLine => 'حذف';

  @override
  String get invalidQuantity => 'كمية غير صالحة';

  @override
  String get quantityMustBePositive => 'يجب أن تكون الكمية أكبر من صفر';

  @override
  String get discountTitle => 'حسم على الفاتورة';

  @override
  String get discountTypeAmount => 'مبلغ';

  @override
  String get discountTypePercent => 'نسبة %';

  @override
  String get discountNone => 'بلا حسم';

  @override
  String get invalidDiscount => 'حسم غير صالح';

  @override
  String get discountCappedNote => 'لا يمكن أن يتجاوز الحسم المجموع.';

  @override
  String get quickItemTitle => 'صنف سريع';

  @override
  String get quickItemHint => 'يُباع مرة واحدة بدون حفظه كمنتج';

  @override
  String get quickItemName => 'اسم الصنف';

  @override
  String get saveAsProduct => 'حفظه كمنتج أيضاً';

  @override
  String get unitOptional => 'الوحدة (اختياري)';

  @override
  String get unitNone => 'بلا وحدة';

  @override
  String get ratesTitle => 'أسعار الصرف';

  @override
  String rateNeeded(String code) {
    return 'حدّد سعر صرف $code قبل حفظ هذه الفاتورة';
  }

  @override
  String get secondaryTotalTitle => 'مجموع بعملة ثانية';

  @override
  String get secondaryTotalNone => 'بلا';

  @override
  String get done => 'تم';

  @override
  String addNewItem(String name) {
    return 'إضافة «$name»';
  }

  @override
  String get newItemDontSave => 'لا تحفظه كمنتج';

  @override
  String get newItemMore => 'المزيد';

  @override
  String get newItemLess => 'أقل';

  @override
  String get unitPriceUpdatesProduct =>
      'السعر المعدَّل يُحفظ للمنتج أيضاً عند حفظ الفاتورة';

  @override
  String get cartNewProduct => 'منتج جديد';

  @override
  String get cartPriceWillUpdate => 'سيُحفظ السعر الجديد';

  @override
  String get sectionSelling => 'البيع';

  @override
  String get settingSaveNewItems => 'حفظ الأصناف الجديدة كمنتجات';

  @override
  String get settingSaveNewItemsHint =>
      'الصنف المكتوب أثناء البيع يُحفظ عند حفظ فاتورته';

  @override
  String get settingUpdatePrices => 'تحديث سعر المنتج من المبيعات';

  @override
  String get settingUpdatePricesHint =>
      'السعر المعدَّل أثناء البيع يصبح سعر المنتج المحفوظ';

  @override
  String get settingAutoFavorites => 'المفضّلة التلقائية';

  @override
  String get settingAutoFavoritesHint =>
      'بعد المنتجات ذات النجمة، يعرض شريط المفضّلة الأكثر مبيعاً في آخر 30 يوماً';

  @override
  String get invoiceSavedTitle => 'تم حفظ الفاتورة';

  @override
  String invoiceNoLabel(String no) {
    return 'فاتورة رقم $no';
  }

  @override
  String get printInvoice => 'طباعة';

  @override
  String get sharePdf => 'مشاركة كملف PDF';

  @override
  String get newSale => 'فاتورة جديدة';

  @override
  String get backToHome => 'العودة للرئيسية';

  @override
  String get setupPrinterQuestion => 'هل لديك طابعة فواتير؟';

  @override
  String get setupPrinterYes => 'نعم، أطبع الفواتير';

  @override
  String get setupPrinterNo => 'لا، أشاركها (صورة / واتساب)';

  @override
  String get invoiceSettingsTitle => 'الفاتورة والطباعة';

  @override
  String get previewTitle => 'معاينة';

  @override
  String get sectionOutput => 'بعد حفظ الفاتورة';

  @override
  String get outputModePrint => 'طباعة';

  @override
  String get outputModeShare => 'مشاركة';

  @override
  String get outputModeBoth => 'طباعة + مشاركة';

  @override
  String get outputModeHint =>
      'يحدّد الزر الرئيسي بعد حفظ الفاتورة. بقية الخيارات تبقى في القائمة.';

  @override
  String get sectionPrinter => 'طابعة البلوتوث';

  @override
  String get printerNone => 'لم تُحدَّد طابعة';

  @override
  String get choosePrinter => 'اختيار الطابعة';

  @override
  String get forgetPrinter => 'نسيان هذه الطابعة';

  @override
  String get pairedDevicesTitle => 'الأجهزة المقترنة';

  @override
  String get noPairedDevices =>
      'لا توجد أجهزة مقترنة. اقرن الطابعة أولاً من إعدادات البلوتوث في الهاتف (الرمز غالباً 0000 أو 1234) ثم عُد إلى هنا.';

  @override
  String get openBluetoothSettings => 'إعدادات البلوتوث';

  @override
  String get openAppSettings => 'إعدادات التطبيق';

  @override
  String get refresh => 'تحديث';

  @override
  String get testPrint => 'طباعة تجريبية';

  @override
  String get feedLinesLabel => 'أسطر فارغة بعد الطباعة';

  @override
  String get cutPaperLabel => 'قصّ الورق بعد الطباعة';

  @override
  String get cutPaperHint => 'للطابعات المزوّدة بقاطع فقط';

  @override
  String get sectionPaper => 'الورق';

  @override
  String get paperWidthLabel => 'عرض الورق';

  @override
  String paperWidthPreset(String mm) {
    return '$mm مم';
  }

  @override
  String get paperCustom => 'مخصّص';

  @override
  String get paperWidthMmLabel => 'عرض الورق (مم)';

  @override
  String get printerDpiLabel => 'دقة الطابعة (DPI)';

  @override
  String get sideMarginLabel => 'الهامش الجانبي (مم)';

  @override
  String printableWidthInfo(String dots, String mm) {
    return 'عرض الطباعة: $dots نقطة ($mm مم)';
  }

  @override
  String get advancedSection => 'إعدادات متقدمة';

  @override
  String get printableDotsOverrideLabel => 'عرض الطباعة (بالنقاط)';

  @override
  String get printableDotsOverrideHint =>
      'اتركه فارغاً ليُحسب من عرض الورق والهامش والدقة';

  @override
  String get invalidNumber => 'رقم غير صالح';

  @override
  String get sectionShop => 'بيانات المحل';

  @override
  String get shopNameLabel => 'اسم المحل';

  @override
  String get logoLabel => 'الشعار';

  @override
  String get logoHint => 'الشعار البسيط الداكن على خلفية بيضاء يُطبع أفضل';

  @override
  String get pickLogo => 'اختيار صورة';

  @override
  String get removeLogo => 'إزالة';

  @override
  String get logoError => 'تعذّرت قراءة هذه الصورة';

  @override
  String get headerTextLabel => 'نص الترويسة';

  @override
  String get footerTextLabel => 'نص التذييل';

  @override
  String get sectionContent => 'محتوى الفاتورة';

  @override
  String get invoiceLanguageLabel => 'لغة الفاتورة';

  @override
  String get baseFontSizeLabel => 'حجم الخط';

  @override
  String get showItemCodeLabel => 'رمز الصنف';

  @override
  String get showUnitLabel => 'الوحدة';

  @override
  String get showUnitPriceLabel => 'سعر الوحدة';

  @override
  String get showDateTimeLabel => 'التاريخ والوقت';

  @override
  String get showInvoiceNumberLabel => 'رقم الفاتورة';

  @override
  String get showCustomerNameLabel => 'اسم الزبون';

  @override
  String get showCustomerPhoneLabel => 'هاتف الزبون';

  @override
  String get showAccountNumberLabel => 'رقم الحساب / الكرت';

  @override
  String get maskAccountLabel => 'إخفاء الرقم ما عدا آخر 4 خانات';

  @override
  String get sectionCurrency => 'العملات في الفاتورة';

  @override
  String get currencyDisplayLabel => 'كتابة العملة';

  @override
  String get currencyDisplaySymbol => 'الرمز';

  @override
  String get currencyDisplayCode => 'الكود';

  @override
  String get extraCurrenciesLabel => 'إظهار الإجمالي أيضاً بـ';

  @override
  String get extraCurrenciesHint =>
      'عملتان كحدّ أقصى. يُطبع سعر الصرف المستخدم تحت الإجمالي.';

  @override
  String get extraCurrenciesNone =>
      'حدّد سعر صرف عملة أخرى لاستخدام هذا الخيار.';

  @override
  String get sectionSharing => 'المشاركة';

  @override
  String get shareWidthLabel => 'عرض الصورة عند المشاركة';

  @override
  String get shareWidthSameAsPaper => 'مثل عرض الورق';

  @override
  String get shareWidthMmLabel => 'عرض المشاركة (مم)';

  @override
  String get defaultCountryCodeLabel => 'رمز الدولة الافتراضي';

  @override
  String defaultCountryCodeHint(String code) {
    return 'للإرسال عبر واتساب: الرقم المكتوب 09… يُرسل إلى ‎+$code 9…';
  }

  @override
  String get invoiceCustomerLabel => 'الزبون';

  @override
  String get invoicePhoneLabel => 'الهاتف';

  @override
  String get invoiceAccountLabel => 'رقم الحساب';

  @override
  String get sampleItemSugar => 'سكر';

  @override
  String get sampleItemTea => 'شاي';

  @override
  String get sampleItemPackage => 'باقة إنترنت 100 غيغا';

  @override
  String get sampleUnitKg => 'كغ';

  @override
  String get sampleUnitBox => 'علبة';

  @override
  String get sampleCustomerName => 'أحمد';

  @override
  String get shareInvoice => 'مشاركة';

  @override
  String get shareAsImage => 'مشاركة كصورة';

  @override
  String get sendOnWhatsApp => 'إرسال عبر واتساب';

  @override
  String get saveImageToPhone => 'حفظ الصورة في الهاتف';

  @override
  String get savePdfToPhone => 'حفظ ملف PDF في الهاتف';

  @override
  String get moreActions => 'المزيد';

  @override
  String get printSent => 'أُرسلت إلى الطابعة';

  @override
  String savedToPhone(String path) {
    return 'حُفظت في $path';
  }

  @override
  String get whatsAppNotInstalled =>
      'واتساب غير مثبّت — سيتم فتح قائمة المشاركة';

  @override
  String get whatsAppUnsupported =>
      'تعذّر فتح المحادثة مباشرة — سيتم فتح قائمة المشاركة';

  @override
  String get whatsAppChooseTitle => 'الإرسال عبر';

  @override
  String get whatsAppRegular => 'واتساب';

  @override
  String get whatsAppBusiness => 'واتساب للأعمال';

  @override
  String get whatsAppPhoneTitle => 'رقم واتساب';

  @override
  String get whatsAppPhoneHint => 'مثال: 0944 123 456';

  @override
  String get invalidPhone => 'رقم هاتف غير صالح';

  @override
  String get send => 'إرسال';

  @override
  String get errorNoPrinter =>
      'لم تُحدَّد طابعة. اخترها من الإعدادات ← الفاتورة والطباعة.';

  @override
  String get errorBluetoothUnsupported => 'هذا الجهاز لا يدعم البلوتوث.';

  @override
  String get errorBluetoothOff => 'البلوتوث مُطفأ. شغّله ثم حاول مجدداً.';

  @override
  String get errorBluetoothPermission =>
      'لا يملك سوقي إذن استخدام البلوتوث. اسمح بإذن «الأجهزة المجاورة» من إعدادات التطبيق.';

  @override
  String errorPrinterUnreachable(String name) {
    return 'تعذّر الوصول إلى الطابعة $name. تأكد أنها تعمل وقريبة ومقترنة بالهاتف.';
  }

  @override
  String get errorPrinterWrite =>
      'انقطع الاتصال بالطابعة أثناء الطباعة. حاول مجدداً.';

  @override
  String get errorStoragePermission =>
      'لا يملك سوقي إذن حفظ الملفات. اسمح بإذن التخزين من إعدادات التطبيق.';

  @override
  String errorOutputUnknown(String detail) {
    return 'حدث خطأ: $detail';
  }

  @override
  String get storageTitle => 'التخزين';

  @override
  String get storageInvoiceCount => 'الفواتير المحفوظة';

  @override
  String get storageDatabaseSize => 'حجم قاعدة البيانات';

  @override
  String get optimizingStorage => 'جارٍ التحسين…';

  @override
  String sizeInBytes(String size) {
    return '$size بايت';
  }

  @override
  String sizeInKilobytes(String size) {
    return '$size كيلوبايت';
  }

  @override
  String sizeInMegabytes(String size) {
    return '$size ميغابايت';
  }
}
