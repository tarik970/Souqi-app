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
      'هذا المنتج مستخدم في فواتير أو كباقة افتراضية لحساب، لذلك أُلغي تفعيله بدل حذفه.';

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

  @override
  String get archiveSearchProductHint => 'المادة المبيعة';

  @override
  String get archiveSearchCustomerHint => 'الاسم أو الهاتف أو رقم البطاقة';

  @override
  String get archiveInvoiceNoHint => 'رقم الفاتورة';

  @override
  String get archiveFilters => 'تصفية';

  @override
  String get archiveClearFilters => 'إلغاء التصفية';

  @override
  String get periodAll => 'الكل';

  @override
  String get periodToday => 'اليوم';

  @override
  String get periodYesterday => 'أمس';

  @override
  String get periodThisWeek => 'هذا الأسبوع';

  @override
  String get periodThisMonth => 'هذا الشهر';

  @override
  String get periodCustom => 'مدة مخصصة';

  @override
  String periodRangeLabel(String from, String to) {
    return '$from — $to';
  }

  @override
  String get archiveNoInvoices => 'لا توجد فواتير بعد';

  @override
  String get archiveNoMatches => 'لا فاتورة تطابق هذه التصفية';

  @override
  String archiveItemsLabel(String count) {
    return 'المواد: $count';
  }

  @override
  String archiveMatchCount(String count, String total) {
    return '$count فاتورة · $total';
  }

  @override
  String get archiveDeleteRange => 'حذف هذه الفواتير';

  @override
  String get archiveDeleteRangeTitle => 'حذف الفواتير؟';

  @override
  String archiveDeleteRangeMessage(String count, String total) {
    return 'سيتم حذف $count فاتورة بمجموع $total. تبقى المواد وترقيم الفواتير وأكواد البطاقات المبيعة كما هي.';
  }

  @override
  String get archiveDeleteWholeArchive =>
      'لم تُحدَّد مدة، لذلك سيُحذف كل ما في السجل من فواتير.';

  @override
  String get archiveDeleteRangeEmpty => 'لا فواتير في هذه المدة.';

  @override
  String archiveDeletedMessage(String count) {
    return 'تم حذف $count فاتورة';
  }

  @override
  String get deleteInvoiceTitle => 'حذف الفاتورة؟';

  @override
  String deleteInvoiceMessage(String number) {
    return 'سيتم حذف الفاتورة $number. تبقى المواد وأكواد البطاقات المبيعة، ولا يُعاد استخدام رقم الفاتورة.';
  }

  @override
  String invoiceDeletedMessage(String number) {
    return 'تم حذف الفاتورة $number';
  }

  @override
  String get invoiceNotFound => 'هذه الفاتورة لم تبقَ في السجل.';

  @override
  String get invoiceCopyMark => 'نسخة';

  @override
  String get invoiceCopyNotice =>
      'كل ما يُطبع أو يُشارك من هنا يحمل علامة «نسخة».';

  @override
  String get sectionArchive => 'السجل';

  @override
  String get settingAutoDelete => 'حذف الفواتير القديمة تلقائياً';

  @override
  String get settingAutoDeleteHint =>
      'تُحذف الفواتير الأقدم من ذلك عند أول تشغيل في اليوم. تبقى المواد وترقيم الفواتير وأكواد البطاقات المبيعة.';

  @override
  String get retentionOff => 'معطّل';

  @override
  String retentionDays(String days) {
    return 'بعد $days يوم';
  }

  @override
  String get retentionCustom => 'عدد آخر…';

  @override
  String get retentionCustomTitle => 'حذف الفواتير الأقدم من';

  @override
  String get retentionCustomHint => 'عدد الأيام';

  @override
  String retentionNotice(String count, String days) {
    return 'تم حذف $count فاتورة أقدم من $days يوم';
  }

  @override
  String statsBaseCurrencyNote(String code) {
    return 'كل المبالغ بـ $code، بسعر الصرف المحفوظ مع كل فاتورة.';
  }

  @override
  String get statsTotalSales => 'إجمالي المبيعات';

  @override
  String get statsInvoiceCount => 'عدد الفواتير';

  @override
  String get statsAverageInvoice => 'متوسط الفاتورة';

  @override
  String get statsTotalDiscounts => 'الحسومات';

  @override
  String statsPreviousValue(String value) {
    return 'المدة السابقة: $value';
  }

  @override
  String statsTrendUp(String percent) {
    return 'ارتفاع $percent%';
  }

  @override
  String statsTrendDown(String percent) {
    return 'انخفاض $percent%';
  }

  @override
  String get statsTrendFlat => 'بلا تغيير';

  @override
  String get statsTrendNew => 'جديد — لا شيء في المدة السابقة';

  @override
  String get statsTrendGone => 'لا شيء في هذه المدة';

  @override
  String get statsTopBySales => 'أكثر 10 مواد بعدد المبيعات';

  @override
  String get statsTopByAmount => 'أكثر 10 مواد بالمبلغ';

  @override
  String statsSalesCount(String count) {
    return '$count عملية بيع';
  }

  @override
  String get statsUnsavedItemBadge => 'غير محفوظة كمادة';

  @override
  String get statsNoData => 'لا مبيعات في هذه المدة';

  @override
  String get statsByCurrency => 'المبيعات بحسب عملة الفاتورة';

  @override
  String get statsShowByCurrency => 'تفصيل بحسب عملة الفاتورة';

  @override
  String get debugTools => 'أدوات المطوّر (نسخة تطوير)';

  @override
  String get debugSeedInvoices => 'إنشاء فواتير للتجربة';

  @override
  String get debugSeedTitle => 'كم فاتورة؟';

  @override
  String get debugSeedHint => 'موزّعة على آخر 365 يوماً، لاختبار الأداء';

  @override
  String debugSeedDone(String count) {
    return 'تم إنشاء $count فاتورة تجربة';
  }

  @override
  String get archiveCounting => 'جارٍ العدّ…';

  @override
  String get archiveDeletingTitle => 'جارٍ حذف الفواتير';

  @override
  String get archiveDeletingHint => 'اترك التطبيق مفتوحاً حتى ينتهي.';

  @override
  String progressCount(String done, String total) {
    return '$done من $total';
  }

  @override
  String archiveDeletePartial(String deleted, String remaining) {
    return 'تم حذف $deleted فاتورة، وبقيت $remaining. أعد المحاولة.';
  }

  @override
  String archiveDeleteFailed(String detail) {
    return 'توقّف التنظيف: $detail';
  }

  @override
  String get housekeepingBusy => 'هناك عملية تنظيف أخرى قيد التشغيل.';

  @override
  String get debugSeedingTitle => 'جارٍ إنشاء فواتير التجربة';

  @override
  String get archiveDeleteNeedsNoSearch => 'امسح البحث لحذف مدة';

  @override
  String get navCustomers => 'الزبائن';

  @override
  String get navDue => 'مستحقة التجديد';

  @override
  String get customerName => 'الاسم';

  @override
  String get customerPhone => 'الهاتف (اختياري)';

  @override
  String get notesLabel => 'ملاحظات';

  @override
  String get addCustomer => 'إضافة زبون';

  @override
  String get editCustomer => 'تعديل الزبون';

  @override
  String get newCustomer => 'زبون جديد';

  @override
  String get searchCustomersHint => 'ابحث بالاسم أو الهاتف';

  @override
  String get noCustomers => 'لا يوجد زبائن بعد';

  @override
  String get deactivate => 'إلغاء التفعيل';

  @override
  String get reactivate => 'إعادة التفعيل';

  @override
  String get deactivateCustomerTitle => 'إلغاء تفعيل الزبون؟';

  @override
  String deactivateCustomerMessage(String name) {
    return 'لن يظهر «$name» في البحث ولا في قائمة المستحقات. تبقى فواتيره وحساباته محفوظة، ويمكنك إعادة تفعيله في أي وقت.';
  }

  @override
  String get customerNotFound => 'هذا الزبون لم يعد موجوداً';

  @override
  String get callCustomer => 'اتصال';

  @override
  String get whatsAppCustomer => 'واتساب';

  @override
  String get cannotDial => 'تعذّر فتح تطبيق الاتصال';

  @override
  String get whatsAppChatNotInstalled => 'واتساب غير مثبّت على هذا الهاتف';

  @override
  String get whatsAppChatFailed => 'تعذّر فتح محادثة واتساب';

  @override
  String get accountsTitle => 'البطاقات والحسابات';

  @override
  String get addAccount => 'إضافة بطاقة / حساب';

  @override
  String get editAccount => 'تعديل البطاقة / الحساب';

  @override
  String get noAccounts => 'لا توجد بطاقات أو حسابات بعد';

  @override
  String accountsCount(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString بطاقة / حساب',
      few: '$countString بطاقات / حسابات',
      two: 'بطاقتان / حسابان',
      one: 'بطاقة / حساب واحد',
      zero: 'لا توجد بطاقات',
    );
    return '$_temp0';
  }

  @override
  String get accountNumberLabel => 'رقم البطاقة / الحساب';

  @override
  String get accountLabelLabel => 'النوع (مثل: بطاقة إنترنت، خط ADSL)';

  @override
  String get accountProviderLabel => 'المزوّد';

  @override
  String get accountPackageLabel => 'الباقة الافتراضية';

  @override
  String get accountNoPackage => 'بدون';

  @override
  String get accountRenewalDaysLabel => 'مدة التجديد (بالأيام)';

  @override
  String get accountRenewalDaysHint =>
      'مثلاً 30. اتركها فارغة إن لم يكن هناك موعد دوري.';

  @override
  String get accountLastRenewalLabel => 'آخر تجديد';

  @override
  String get accountNextDueLabel => 'موعد الاستحقاق القادم';

  @override
  String get accountNextDueHint => 'آخر تجديد + المدة. ويمكنك تحديده يدوياً.';

  @override
  String get accountNotSet => 'غير محدد';

  @override
  String get clearDate => 'مسح';

  @override
  String get accountDuplicateTitle => 'الرقم مسجّل من قبل';

  @override
  String accountDuplicateMessage(String number, String customer) {
    return 'الرقم $number مسجّل لدى المزوّد نفسه باسم: $customer. هل تريد الحفظ على أي حال؟';
  }

  @override
  String get saveAnyway => 'حفظ على أي حال';

  @override
  String get firstAccountSection => 'أول بطاقة / حساب (اختياري)';

  @override
  String get historyTitle => 'المشتريات والتجديدات';

  @override
  String get noHistory => 'لا توجد فواتير بعد';

  @override
  String get showMore => 'عرض المزيد';

  @override
  String get customerInvoiceCount => 'الفواتير';

  @override
  String get customerTotalSpent => 'الإجمالي';

  @override
  String get customerLastPurchase => 'آخر شراء';

  @override
  String historyMoreItems(String count) {
    return '+$count أخرى';
  }

  @override
  String get quickSearchHint => 'الاسم أو الهاتف أو رقم البطاقة';

  @override
  String quickSearchEmpty(String query) {
    return 'لا يوجد زبون أو بطاقة تطابق «$query»';
  }

  @override
  String get quickSearchPrompt => 'اكتب اسماً أو رقم هاتف أو رقم بطاقة / حساب';

  @override
  String get renew => 'تجديد';

  @override
  String packageLabel(String name) {
    return 'الباقة: $name';
  }

  @override
  String lastRenewalLabel(String date) {
    return 'آخر تجديد: $date';
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
      other: 'متأخر $daysString يوماً',
      few: 'متأخر $daysString أيام',
      two: 'متأخر يومين',
      one: 'متأخر يوماً واحداً',
    );
    return '$_temp0';
  }

  @override
  String get dueToday => 'يستحق اليوم';

  @override
  String dueInDays(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'يستحق بعد $daysString يوماً',
      few: 'يستحق بعد $daysString أيام',
      two: 'يستحق بعد يومين',
      one: 'يستحق غداً',
    );
    return '$_temp0';
  }

  @override
  String get dueOk => 'سارٍ';

  @override
  String get dueNoDate => 'بلا موعد استحقاق';

  @override
  String dueSectionOverdue(String count) {
    return 'متأخرة ($count)';
  }

  @override
  String dueSectionToday(String count) {
    return 'تستحق اليوم ($count)';
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
      other: 'تستحق خلال $daysString يوماً ($count)',
      few: 'تستحق خلال $daysString أيام ($count)',
      two: 'تستحق خلال يومين ($count)',
      one: 'تستحق غداً ($count)',
    );
    return '$_temp0';
  }

  @override
  String get dueEmpty => 'لا توجد تجديدات مستحقة';

  @override
  String dueSeeAll(String count) {
    return 'عرض الكل ($count)';
  }

  @override
  String get sendReminder => 'تذكير عبر واتساب';

  @override
  String get sectionCustomers => 'الزبائن والتجديدات';

  @override
  String get settingDueSoonDays => 'مدة التنبيه قبل الاستحقاق';

  @override
  String get settingDueSoonDaysHint =>
      'الحسابات التي تستحق خلال هذه المدة تظهر في قائمة «مستحقة التجديد»';

  @override
  String daysCount(int days) {
    final intl.NumberFormat daysNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String daysString = daysNumberFormat.format(days);

    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$daysString يوماً',
      few: '$daysString أيام',
      two: 'يومان',
      one: 'يوم واحد',
    );
    return '$_temp0';
  }

  @override
  String get settingReminderText => 'رسالة تذكير التجديد';

  @override
  String get settingReminderTextHint =>
      'تُفتح في محادثة واتساب الزبون من قائمة المستحقات، ويمكنك تعديلها هناك قبل الإرسال.';

  @override
  String get reminderDialogTitle => 'رسالة التذكير';

  @override
  String reminderPlaceholdersHint(String placeholders) {
    return 'تُستبدل هذه الرموز لكل زبون: $placeholders';
  }

  @override
  String get reminderResetDefault => 'استخدام النص الافتراضي';

  @override
  String reminderDefaultText(String name, String account, String date) {
    return 'مرحباً $name، نذكّركم بأن موعد تجديد اشتراككم ($account) هو $date.';
  }

  @override
  String get saleCustomerChip => 'الزبون';

  @override
  String get saleCustomerRemove => 'إزالة الزبون';

  @override
  String accountRequiredMessage(String name) {
    return 'يجب ربط «$name» ببطاقة أو حساب زبون';
  }

  @override
  String get chooseAccount => 'اختيار الحساب';

  @override
  String get customerPickerTitle => 'اختيار الزبون';

  @override
  String newCustomerNamed(String text) {
    return 'زبون جديد «$text»';
  }

  @override
  String newCustomerWithPhone(String text) {
    return 'زبون جديد برقم الهاتف $text';
  }

  @override
  String newCustomerWithAccount(String text) {
    return 'زبون جديد برقم البطاقة $text';
  }

  @override
  String packageChangedNotice(String name) {
    return 'بيعت في هذا التجديد «$name»، وهي ليست الباقة الافتراضية لهذا الحساب.';
  }

  @override
  String get makeDefaultPackage => 'اجعلها الباقة الافتراضية لهذا الحساب';

  @override
  String get defaultPackageUpdated => 'تم تحديث الباقة الافتراضية';

  @override
  String get renewNewSaleTitle => 'بدء فاتورة جديدة؟';

  @override
  String get renewNewSaleMessage =>
      'هناك أصناف في الفاتورة الحالية، وبدء التجديد سيحذفها.';

  @override
  String get renewNoPackage =>
      'لا توجد باقة افتراضية لهذا الحساب. أضف الصنف المراد بيعه.';

  @override
  String get statsRenewals => 'التجديدات';

  @override
  String get statsTopPackages => 'أكثر الباقات مبيعاً';

  @override
  String get statsTopCustomers => 'المبيعات حسب الزبون';

  @override
  String statsInvoicesCount(String count) {
    return '$count فاتورة';
  }

  @override
  String get debugSeedCustomers => 'إنشاء زبائن للتجربة';

  @override
  String get debugSeedCustomersHint =>
      'لكل زبون بطاقتان / حسابان، لتجربة البحث السريع وقائمة المستحقات';

  @override
  String debugSeedCustomersDone(String count) {
    return 'تم إنشاء $count زبون للتجربة';
  }

  @override
  String get debugSeedingCustomersTitle => 'جارٍ إنشاء زبائن التجربة';

  @override
  String get sectionSecurity => 'الأمان';

  @override
  String get pinLockTitle => 'رمز القفل';

  @override
  String get pinNotSet => 'لم يُحدَّد رمز';

  @override
  String get pinIsSet => 'تم تحديد رمز';

  @override
  String get pinSetTitle => 'اختر رمز القفل';

  @override
  String get pinChangeTitle => 'رمز القفل الجديد';

  @override
  String get pinSetIntro =>
      'يحمي رمز القفل رموز البطاقات والعمليات الحساسة. من 4 إلى 6 أرقام.';

  @override
  String get pinNeededIntro =>
      'هذه العملية تحتاج رمز قفل ولم يُحدَّد رمز بعد. اختر رمزاً الآن: من 4 إلى 6 أرقام.';

  @override
  String get pinNewLabel => 'رمز القفل';

  @override
  String get pinConfirmLabel => 'أعد كتابة الرمز';

  @override
  String get pinInvalid => 'يجب أن يكون الرمز من 4 إلى 6 أرقام';

  @override
  String get pinMismatch => 'الرمزان غير متطابقين';

  @override
  String get pinEnterTitle => 'أدخل رمز القفل';

  @override
  String get pinLabel => 'رمز القفل';

  @override
  String pinWrong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بقيت $count محاولة',
      few: 'بقيت $count محاولات',
      two: 'بقيت محاولتان',
      one: 'بقيت محاولة واحدة',
      zero: 'لا محاولات متبقية',
    );
    return 'الرمز غير صحيح. $_temp0';
  }

  @override
  String pinLocked(String time) {
    return 'محاولات خاطئة كثيرة. حاول مجدداً بعد $time.';
  }

  @override
  String get pinConfirmAction => 'متابعة';

  @override
  String get pinForgetWarning =>
      'ستحصل بعد ذلك على رمز استرجاع، وهو الطريقة الوحيدة للدخول إذا نُسي رمز القفل.';

  @override
  String get pinChangeAction => 'تغيير الرمز';

  @override
  String get pinRemoveAction => 'إزالة الرمز';

  @override
  String get pinRemoveTitle => 'إزالة رمز القفل؟';

  @override
  String get pinRemoveMessage =>
      'بدون رمز قفل يستطيع أي شخص يحمل هذا الهاتف اختيار رمز جديد ثم إظهار رموز البطاقات أو إعادة طباعتها.';

  @override
  String get pinSaved => 'تم حفظ الرمز';

  @override
  String get pinRemoved => 'تمت إزالة الرمز';

  @override
  String get pinReasonReprint =>
      'هذه الفاتورة تحتوي رموز بطاقات. إعادة طباعتها أو مشاركتها تحتاج رمز القفل وتحمل علامة «نسخة».';

  @override
  String get pinReasonCodes => 'رموز البطاقات محمية برمز القفل.';

  @override
  String get auditLogTitle => 'سجل العمليات الحساسة';

  @override
  String get auditLogHint =>
      'إظهار الرموز وإعادة طباعتها وإلغاؤها وتحميلها وتصديرها';

  @override
  String get auditEmpty => 'لا توجد عمليات حساسة في هذه الفترة';

  @override
  String get loadMore => 'عرض المزيد';

  @override
  String get auditCodeImport => 'تحميل رموز';

  @override
  String get auditCodeReveal => 'إظهار رمز على الشاشة';

  @override
  String get auditCodeLookup => 'بحث برمز بطاقة';

  @override
  String get auditCodeVoid => 'إلغاء رمز';

  @override
  String get auditCodeRestore => 'إعادة رمز إلى المخزون';

  @override
  String get auditCodeExport => 'تصدير رموز';

  @override
  String get auditCodeExpiryChange => 'تغيير تاريخ الانتهاء';

  @override
  String get auditBatchDelete => 'حذف دفعة';

  @override
  String get auditInvoiceReprint => 'إعادة طباعة فاتورة فيها رموز';

  @override
  String get auditPinSet => 'تحديد رمز القفل';

  @override
  String get auditPinChange => 'تغيير رمز القفل';

  @override
  String get auditPinRemove => 'إزالة رمز القفل';

  @override
  String auditDetailFound(String count) {
    return 'النتائج: $count';
  }

  @override
  String auditDetailReason(String reason) {
    return 'السبب: $reason';
  }

  @override
  String cardsCount(String count) {
    return '$count بطاقة';
  }

  @override
  String serialLabel(String serial) {
    return 'تسلسلي $serial';
  }

  @override
  String get navCardStock => 'مخزون البطاقات';

  @override
  String get stockAvailable => 'متوفر';

  @override
  String get stockSold => 'مباع';

  @override
  String get stockVoid => 'ملغى';

  @override
  String get stockExpired => 'منتهي';

  @override
  String stockCount(String count) {
    return 'المخزون: $count';
  }

  @override
  String get stockOut => 'نفد المخزون';

  @override
  String stockLowWarning(String name, String count) {
    return '$name: بقي $count فقط';
  }

  @override
  String stockOutWarning(String name) {
    return '$name: نفد المخزون';
  }

  @override
  String get cardStockEmpty =>
      'لا يوجد منتج يُباع من مخزون الرموز بعد. افتح منتجاً من نوع كرت / خدمة وفعّل «يُباع من مخزون الرموز».';

  @override
  String get cardStockLookup => 'البحث عن بطاقة برمزها';

  @override
  String get expiredCodesTitle => 'الرموز المنتهية';

  @override
  String expiredCodesNotice(String count) {
    return '$count رمز منتهي الصلاحية لا يُباع. قرّر ما تفعل بها.';
  }

  @override
  String get expiredEmpty => 'لا توجد رموز منتهية';

  @override
  String get batchesTitle => 'الدفعات';

  @override
  String get batchAdd => 'تحميل رموز';

  @override
  String get batchEmpty => 'لم تُحمَّل أي رموز بعد';

  @override
  String batchCostEach(String amount) {
    return 'التكلفة $amount للبطاقة';
  }

  @override
  String batchExpires(String date) {
    return 'صالحة حتى $date';
  }

  @override
  String get batchDelete => 'حذف الدفعة';

  @override
  String get batchDeleteTitle => 'حذف هذه الدفعة؟';

  @override
  String batchDeleteMessage(String count) {
    return 'ستُحذف رموزها غير المباعة ($count) نهائياً.';
  }

  @override
  String get batchDeleteBlocked => 'في هذه الدفعة رموز مباعة ولا يمكن حذفها.';

  @override
  String batchDeleted(String count) {
    return 'تم حذف $count رمز';
  }

  @override
  String get batchShowCodes => 'عرض الرموز';

  @override
  String get batchChangeExpiry => 'تغيير تاريخ الانتهاء';

  @override
  String get expiryChanged => 'تم تغيير تاريخ الانتهاء';

  @override
  String get exportCodes => 'تصدير الرموز غير المباعة';

  @override
  String get exportWarning =>
      'الملف يحتوي الرموز مكشوفة، وكل من يحصل عليه يستطيع استخدام البطاقات.';

  @override
  String get exportShare => 'مشاركة الملف';

  @override
  String get exportSave => 'حفظ في الهاتف';

  @override
  String exportDone(String count) {
    return 'تم تصدير $count رمز';
  }

  @override
  String get exportNothing => 'لا توجد رموز غير مباعة للتصدير';

  @override
  String get addBatchTitle => 'تحميل رموز';

  @override
  String get loadMethodPaste => 'لصق';

  @override
  String get loadMethodFile => 'ملف';

  @override
  String get loadMethodScan => 'مسح';

  @override
  String get pasteLabel => 'الرموز';

  @override
  String get pasteHint => 'بطاقة في كل سطر';

  @override
  String get pickFile => 'اختر ملف .txt أو .csv';

  @override
  String get fileReadFailed => 'تعذّرت قراءة الملف';

  @override
  String get columnsLabel => 'كل سطر يحتوي';

  @override
  String get columnsCodeOnly => 'الرمز';

  @override
  String get columnsSerialCode => 'التسلسلي، الرمز';

  @override
  String get columnsCodeSerial => 'الرمز، التسلسلي';

  @override
  String importToAdd(String count) {
    return 'سيُضاف $count';
  }

  @override
  String importAdded(String count) {
    return 'أُضيف $count';
  }

  @override
  String importDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تخطّي $count رمزاً مكرراً',
      few: 'تخطّي $count رموز مكررة',
      two: 'تخطّي رمزين مكررين',
      one: 'تخطّي رمز مكرر واحد',
    );
    return '$_temp0';
  }

  @override
  String importEmpty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سطراً فارغاً',
      few: '$count أسطر فارغة',
      two: 'سطران فارغان',
      one: 'سطر فارغ واحد',
    );
    return '$_temp0';
  }

  @override
  String importInvalid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count سطراً بلا رمز',
      few: '$count أسطر بلا رمز',
      two: 'سطران بلا رمز',
      one: 'سطر واحد بلا رمز',
    );
    return '$_temp0';
  }

  @override
  String get importHeaderSkipped => 'تم تجاهل سطر العناوين';

  @override
  String get batchExpiryLabel => 'تاريخ الانتهاء (اختياري)';

  @override
  String get noExpiry => 'بلا تاريخ انتهاء';

  @override
  String batchCostLabel(String currency) {
    return 'تكلفة البطاقة، $currency (اختياري)';
  }

  @override
  String get saveBatch => 'حفظ الدفعة';

  @override
  String get nothingToAdd => 'لا يوجد جديد للإضافة';

  @override
  String get scanStart => 'مسح البطاقات بالكاميرا';

  @override
  String get scanTitle => 'مسح البطاقات';

  @override
  String scanCount(String count) {
    return 'تم مسح $count';
  }

  @override
  String get scanDuplicate => 'تم مسحها من قبل';

  @override
  String get scanHint => 'وجّه الكاميرا نحو رمز QR أو الباركود على البطاقة';

  @override
  String get scanCameraError =>
      'تعذّر فتح الكاميرا. اسمح لتطبيق سوقي باستخدام الكاميرا من إعدادات الهاتف.';

  @override
  String scannedCards(String count) {
    return 'البطاقات الممسوحة: $count';
  }

  @override
  String get clearScanned => 'مسح القائمة';

  @override
  String get codesTitle => 'رموز البطاقات';

  @override
  String get codesMaskedNote =>
      'الرموز مخفية على الشاشة، وتُطبع وتُشارك كاملة.';

  @override
  String get codeStatusAvailable => 'في المخزون';

  @override
  String get codeStatusSold => 'مباع';

  @override
  String get codeStatusVoid => 'ملغى';

  @override
  String get codeStatusExpired => 'منتهي';

  @override
  String get codeReveal => 'إظهار الرمز';

  @override
  String get codeVoid => 'إلغاء الرمز';

  @override
  String get codeReturn => 'إعادة إلى المخزون';

  @override
  String get codeRevealedTitle => 'رمز البطاقة';

  @override
  String get codeUnreadable => 'لا يمكن قراءة هذا الرمز على هذا الجهاز.';

  @override
  String get voidCodeTitle => 'إلغاء هذا الرمز؟';

  @override
  String get voidCodeMessage =>
      'لن تُحتسب البطاقة مباعة ولا في المخزون. تُسجَّل العملية في سجل العمليات الحساسة.';

  @override
  String get returnCodeTitle => 'إعادة هذا الرمز إلى المخزون؟';

  @override
  String get returnCodeMessage =>
      'تصبح البطاقة متاحة للبيع من جديد. تُسجَّل العملية في سجل العمليات الحساسة.';

  @override
  String get reasonLabel => 'السبب';

  @override
  String get codeVoided => 'تم إلغاء الرمز';

  @override
  String get codeReturned => 'أُعيد الرمز إلى المخزون';

  @override
  String get voidExpiredAction => 'إلغاؤها';

  @override
  String get voidExpiredTitle => 'إلغاء الرموز المنتهية؟';

  @override
  String voidExpiredMessage(String count, String name) {
    return 'سيُلغى $count رمز منتهٍ من «$name».';
  }

  @override
  String expiredVoided(String count) {
    return 'تم إلغاء $count رمز';
  }

  @override
  String get batchCodesTitle => 'رموز الدفعة';

  @override
  String get lookupTitle => 'البحث عن بطاقة';

  @override
  String get lookupHint => 'اكتب أو الصق الرمز كاملاً';

  @override
  String get lookupAction => 'بحث';

  @override
  String get lookupNotFound => 'لا توجد بطاقة بهذا الرمز';

  @override
  String lookupSoldOn(String date) {
    return 'بيعت بتاريخ $date';
  }

  @override
  String lookupCustomer(String name) {
    return 'الزبون: $name';
  }

  @override
  String lookupAccount(String number) {
    return 'الحساب: $number';
  }

  @override
  String get lookupOpenInvoice => 'فتح الفاتورة';

  @override
  String get lookupInvoiceDeleted => 'الفاتورة نفسها حُذفت من السجل';

  @override
  String codeStockOnly(String count) {
    return 'المتوفر $count فقط';
  }

  @override
  String codeStockShort(String name, String wanted, String available) {
    return '«$name»: المطلوب $wanted والمتوفر $available';
  }

  @override
  String get codeStockUnreadable =>
      'لا يمكن قراءة رموز البطاقات على هذا الجهاز، فلم يُبَع شيء.';

  @override
  String codeStockWholeCards(String name) {
    return '«$name» يُباع بطاقات كاملة فقط';
  }

  @override
  String get soldFromCodeStock => 'يُباع من مخزون الرموز';

  @override
  String get soldFromCodeStockHint =>
      'كل عملية بيع تأخذ رمز بطاقة من المخزون وتطبعه على الفاتورة';

  @override
  String get lowStockThresholdLabel => 'التنبيه عند انخفاض المخزون إلى';

  @override
  String get lowStockThresholdHint => 'فارغ = بلا تنبيه';

  @override
  String get manageStock => 'مخزون بطاقات هذا المنتج';

  @override
  String get sectionCardCodes => 'رموز البطاقات';

  @override
  String get printCodeQrLabel => 'طباعة رمز QR لكل رمز بطاقة';

  @override
  String get codesSeparateSlipsLabel => 'طباعة كل بطاقة على قصاصة منفصلة';

  @override
  String get codesSeparateSlipsHint =>
      'تسحب الطابعة الورق (وتقطعه) بين القصاصات. الصورة أو ملف PDF المشارَك يحتوي كل شيء دائماً.';

  @override
  String get invoiceSerialLabel => 'التسلسلي';

  @override
  String invoiceExpiryLabel(String date) {
    return 'صالحة حتى $date';
  }

  @override
  String get invoiceCodeUnreadable => 'الرمز غير متاح على هذا الجهاز';

  @override
  String get statsCardsSold => 'البطاقات المباعة';

  @override
  String statsCardsProfit(String amount) {
    return 'الربح $amount';
  }

  @override
  String statsCardsProfitPartial(String amount, String count) {
    return 'الربح $amount (على $count معروفة التكلفة)';
  }

  @override
  String get debugSeedCards => 'إنشاء رموز بطاقات للتجربة';

  @override
  String get debugSeedCardsHint =>
      'منتجا بطاقات برموز وهمية، وإحدى الدفعات قريبة الانتهاء، لتجربة بيع البطاقات';

  @override
  String debugSeedCardsDone(String count) {
    return 'تم إنشاء $count رمز للتجربة';
  }

  @override
  String get batchSaveFailed => 'تعذّر حفظ الدفعة ولم يُضَف شيء.';

  @override
  String get importPreviewTitle => 'معاينة (أول 5)';

  @override
  String get recoveryCodeTitle => 'رمز الاسترجاع';

  @override
  String get recoveryCodeIntro =>
      'إذا نُسي رمز القفل فهذا الرمز هو الطريقة الوحيدة لاختيار رمز جديد. يظهر مرة واحدة فقط، الآن. اطبعه أو احفظه، وأبقِه بعيداً عن هذا الهاتف.';

  @override
  String get recoveryCodeSaved => 'حفظتُه';

  @override
  String get recoveryPrint => 'طباعة';

  @override
  String get recoveryShare => 'مشاركة';

  @override
  String get recoverySlipTitle => 'رمز استرجاع رمز القفل';

  @override
  String get recoverySlipHint =>
      'احتفظ بهذا الرمز في مكان آمن. به يمكن إعادة تعيين رمز القفل.';

  @override
  String get pinForgot => 'نسيت الرمز؟';

  @override
  String get recoveryEnterTitle => 'إعادة تعيين رمز القفل';

  @override
  String get recoveryEnterIntro =>
      'أدخل رمز الاسترجاع الذي حصلت عليه عند اختيار رمز القفل.';

  @override
  String get recoveryEnterIntroSigned =>
      'أدخل رمز الاسترجاع الذي حصلت عليه عند اختيار رمز القفل، أو رمز إعادة التعيين من المطوّر.';

  @override
  String get recoveryInvalid => 'رمز الاسترجاع مكوّن من 12 حرفاً ورقماً';

  @override
  String recoveryWrong(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'بقيت $count محاولة',
      few: 'بقيت $count محاولات',
      two: 'بقيت محاولتان',
      one: 'بقيت محاولة واحدة',
      zero: 'لا محاولات متبقية',
    );
    return 'رمز الاسترجاع غير صحيح. $_temp0';
  }

  @override
  String get recoveryRefused => 'هذا الرمز غير صالح';

  @override
  String get auditPinRecover => 'إعادة تعيين رمز القفل برمز الاسترجاع';

  @override
  String get auditPinResetSigned => 'إعادة تعيين رمز القفل برمز من المطوّر';

  @override
  String get recoveryMissingTitle => 'رمز القفل هذا بلا رمز استرجاع';

  @override
  String get recoveryMissingMessage =>
      'إذا نُسي رمز القفل فلن تكون هناك طريقة للدخول.';

  @override
  String get recoveryCreateNow => 'إنشاء رمز استرجاع الآن';

  @override
  String get recoveryCreateArmed =>
      'أدخل رمز القفل، وسيظهر رمز الاسترجاع بعده.';

  @override
  String get auditRecoveryCodeCreate => 'إنشاء رمز استرجاع';

  @override
  String get debtsTitle => 'الديون';

  @override
  String get debtorsTitle => 'المدينون';

  @override
  String get accountTab => 'الحساب';

  @override
  String get customerDetailsTab => 'البيانات';

  @override
  String get balanceLabel => 'الرصيد';

  @override
  String balanceOwes(String amount) {
    return 'عليه $amount';
  }

  @override
  String balanceCredit(String amount) {
    return 'له $amount';
  }

  @override
  String get balanceSettled => 'لا يوجد رصيد';

  @override
  String get creditLimitLabel => 'حد الدين';

  @override
  String get lastPaymentLabel => 'آخر دفعة';

  @override
  String get neverPaid => 'لم يدفع بعد';

  @override
  String get overdueBadge => 'متأخر';

  @override
  String overdueAmount(String amount) {
    return 'متأخر: $amount';
  }

  @override
  String oldestDebtAge(String days) {
    return 'أقدم دين: منذ $days يوم';
  }

  @override
  String get oldestDebtToday => 'أقدم دين: اليوم';

  @override
  String get overLimitBadge => 'تجاوز الحد';

  @override
  String get recordPayment => 'تسجيل دفعة';

  @override
  String get addDebt => 'إضافة دين';

  @override
  String get openingBalance => 'رصيد افتتاحي';

  @override
  String get adjustment => 'تسوية';

  @override
  String get accountStatement => 'كشف حساب';

  @override
  String get sendDebtReminder => 'تذكير عبر واتساب';

  @override
  String get debtReminderNoPhone => 'لا يوجد رقم هاتف لهذا الزبون';

  @override
  String entryInvoice(String no) {
    return 'فاتورة $no';
  }

  @override
  String entryReceipt(String no) {
    return 'سند قبض $no';
  }

  @override
  String get entryPayment => 'دفعة';

  @override
  String get entryManualDebt => 'دين';

  @override
  String entryReversalOf(String what) {
    return 'عكس: $what';
  }

  @override
  String get entryReversed => 'معكوسة';

  @override
  String get ledgerEmpty => 'لا توجد حركات بعد';

  @override
  String get ledgerNoMatch => 'لا توجد حركات مطابقة';

  @override
  String get ledgerDebit => 'مدين';

  @override
  String get ledgerCredit => 'دائن';

  @override
  String get dateLabel => 'التاريخ';

  @override
  String get descriptionLabel => 'البيان';

  @override
  String get typeFilterDebts => 'ديون';

  @override
  String get typeFilterPayments => 'دفعات';

  @override
  String get typeFilterOther => 'أخرى';

  @override
  String invoiceDeletedNote(String no) {
    return 'الفاتورة $no حُذفت من الأرشيف. الدين باقٍ في الحساب.';
  }

  @override
  String get openInvoice => 'فتح الفاتورة';

  @override
  String get viewReceipt => 'سند القبض';

  @override
  String get reverseEntry => 'عكس الحركة';

  @override
  String get reverseTitle => 'عكس هذه الحركة؟';

  @override
  String get reverseMessage =>
      'تبقى الحركة في الدفتر مشطوبة، وتُضاف حركة عكسية تلغيها. لا يمكن التراجع عن ذلك.';

  @override
  String get reasonRequired => 'اكتب السبب';

  @override
  String get pinReasonReverse => 'أدخل الرمز لعكس حركة في الدفتر.';

  @override
  String get pinReasonAdjustment => 'أدخل الرمز لتسوية رصيد.';

  @override
  String get pinReasonCreditLimit => 'أدخل الرمز للبيع فوق حد الدين.';

  @override
  String get pinReasonDebtAccess => 'أدخل الرمز لفتح الديون.';

  @override
  String get entryReversedSnack => 'تم عكس الحركة';

  @override
  String dueOnLabel(String date) {
    return 'يستحق $date';
  }

  @override
  String get paymentMethodLabel => 'طريقة الدفع';

  @override
  String get methodCash => 'نقداً';

  @override
  String get methodTransfer => 'حوالة';

  @override
  String get methodOther => 'أخرى';

  @override
  String get amountLabel => 'المبلغ';

  @override
  String get amountInvalid => 'أدخل مبلغاً أكبر من صفر';

  @override
  String get payFullBalance => 'تسديد كامل الرصيد';

  @override
  String get paymentCurrencyLabel => 'العملة';

  @override
  String paymentRateLabel(String base, String code) {
    return 'السعر: كم $base لكل 1 $code';
  }

  @override
  String paymentCountsAs(String amount) {
    return 'يُحتسب $amount';
  }

  @override
  String paymentOverBalance(String amount) {
    return 'أكثر من الرصيد: سيصبح للزبون رصيد دائن $amount.';
  }

  @override
  String get noteOptional => 'ملاحظة (اختياري)';

  @override
  String get receiptTitle => 'سند قبض';

  @override
  String receiptNoLabel(String no) {
    return 'سند قبض رقم $no';
  }

  @override
  String get receiptReceivedFrom => 'استلمنا من';

  @override
  String get receiptAmountLabel => 'المبلغ المدفوع';

  @override
  String get receiptPaidAs => 'استُلم';

  @override
  String get receiptMethodLabel => 'الطريقة';

  @override
  String get receiptNoteLabel => 'ملاحظة';

  @override
  String get receiptReversedMark => 'ملغى';

  @override
  String get previousBalanceLabel => 'الرصيد السابق';

  @override
  String get newBalanceLabel => 'الرصيد الجديد';

  @override
  String get paperOwes => 'عليه';

  @override
  String get paperCredit => 'له';

  @override
  String get statementOpening => 'رصيد سابق';

  @override
  String get statementClosing => 'الرصيد الختامي';

  @override
  String get statementTotalDebits => 'مجموع المدين';

  @override
  String get statementTotalCredits => 'مجموع الدائن';

  @override
  String get statementNoEntries => 'لا توجد حركات في هذه الفترة';

  @override
  String get statementWholeAccount => 'كامل الحساب';

  @override
  String get statementLast30 => 'آخر 30 يوماً';

  @override
  String statementUntil(String date) {
    return 'حتى $date';
  }

  @override
  String get debtorsTotalOutstanding => 'إجمالي الديون';

  @override
  String debtorsOwingCount(String count) {
    return '$count زبون مدين';
  }

  @override
  String debtorsCreditTotal(String amount) {
    return 'أرصدة دائنة للزبائن: $amount';
  }

  @override
  String get agingTitle => 'أعمار الديون';

  @override
  String get aging0to30 => '0–30 يوماً';

  @override
  String get aging31to60 => '31–60 يوماً';

  @override
  String get aging61to90 => '61–90 يوماً';

  @override
  String get agingOver90 => 'أكثر من 90 يوماً';

  @override
  String get sortLabel => 'الترتيب';

  @override
  String get sortByAmount => 'الأكبر مبلغاً';

  @override
  String get sortByOldest => 'أقدم دين';

  @override
  String get sortByLastPayment => 'الأبعد عن آخر دفعة';

  @override
  String get filterOverdue => 'متأخرون';

  @override
  String get filterOverLimit => 'تجاوزوا الحد';

  @override
  String get filterCreditBalances => 'أرصدة دائنة';

  @override
  String get debtorsEmpty => 'لا يوجد مدينون';

  @override
  String get debtorsNoMatch => 'لا يوجد زبائن مطابقون';

  @override
  String lastPaymentOn(String date) {
    return 'آخر دفعة $date';
  }

  @override
  String get paymentSheetTitle => 'الدفع';

  @override
  String get payFull => 'مدفوعة كاملة';

  @override
  String get payPartial => 'دفعة جزئية';

  @override
  String get payCredit => 'آجل (دين)';

  @override
  String get amountPaidLabel => 'المبلغ المدفوع';

  @override
  String remainingAsDebt(String amount) {
    return 'يُسجَّل ديناً: $amount';
  }

  @override
  String get cashReceivedLabel => 'المبلغ المستلم (اختياري)';

  @override
  String changeDue(String amount) {
    return 'الباقي للزبون: $amount';
  }

  @override
  String get cashShort => 'أقل من المبلغ المطلوب';

  @override
  String get customerRequiredForDebt => 'اختر زبوناً للبيع بالدين';

  @override
  String get chooseCustomer => 'اختيار زبون';

  @override
  String get changeCustomer => 'تغيير';

  @override
  String useCreditBalance(String amount) {
    return 'استخدام الرصيد الدائن ($amount)';
  }

  @override
  String toPayNow(String amount) {
    return 'المطلوب الآن: $amount';
  }

  @override
  String get dueDateLabel => 'تاريخ الاستحقاق';

  @override
  String get creditLimitWarningTitle => 'تجاوز حد الدين';

  @override
  String creditLimitWarning(
    String balance,
    String sale,
    String newBalance,
    String limit,
  ) {
    return 'الرصيد $balance + هذه الفاتورة $sale = $newBalance. الحد المسموح $limit.';
  }

  @override
  String get overrideAndSave => 'تجاوز الحد والحفظ';

  @override
  String get creditLimitConfirmTitle => 'البيع فوق حد الدين؟';

  @override
  String get creditLimitBlocked =>
      'هذه الفاتورة تتجاوز حد الدين المسموح للزبون.';

  @override
  String get partialInvalid => 'أدخل مبلغاً أقل من المطلوب';

  @override
  String salePaidLine(String paid, String remaining) {
    return 'المدفوع $paid · على الحساب $remaining';
  }

  @override
  String get invoicePaidLabel => 'المدفوع';

  @override
  String get invoiceFromCreditLabel => 'من الرصيد الدائن';

  @override
  String get invoiceRemainingLabel => 'الباقي (دين)';

  @override
  String get debtLinesSection => 'سطور الدين';

  @override
  String get debtLinesHint =>
      'يُطبع المدفوع والباقي فقط في فاتورة لم تُدفع كاملة، والأرصدة فقط عند وجود زبون على الفاتورة.';

  @override
  String get showPaidAmount => 'المبلغ المدفوع';

  @override
  String get showRemainingAmount => 'المبلغ الباقي (الدين)';

  @override
  String get showPreviousBalance => 'رصيد الزبون السابق';

  @override
  String get showNewBalance => 'رصيد الزبون الجديد';

  @override
  String get debtSettingsSection => 'الديون';

  @override
  String get defaultDueDaysLabel => 'مهلة السداد';

  @override
  String get defaultDueDaysHint =>
      'يُعتبر الدين الجديد متأخراً بعد هذا العدد من الأيام، ما لم تكن للزبون مهلة خاصة.';

  @override
  String get debtRequirePinTitle => 'طلب الرمز لفتح الديون';

  @override
  String get debtRequirePinSubtitle =>
      'يُطلب الرمز قبل قائمة المدينين وحساب الزبون. البيع بالدين لا يطلبه.';

  @override
  String get debtReminderTitle => 'رسالة تذكير الدين';

  @override
  String get debtReminderHint =>
      'النص الذي يُفتح به واتساب عند تذكير الزبون برصيده';

  @override
  String debtReminderDefaultText(
    String name,
    String shop,
    String balance,
    String lastPayment,
  ) {
    return 'مرحباً $name، تذكير من $shop: رصيدكم المستحق $balance. آخر دفعة: $lastPayment. شكراً لكم.';
  }

  @override
  String get customerCreditLimitLabel => 'حد الدين (اختياري)';

  @override
  String get customerDueDaysLabel => 'مهلة السداد بالأيام (اختياري)';

  @override
  String customerDueDaysHint(String days) {
    return 'فارغ = المهلة العامة ($days)';
  }

  @override
  String deactivateWithBalanceMessage(String name, String balance) {
    return 'للزبون \"$name\" رصيد مفتوح: $balance. التعطيل يخفيه من البحث، ويبقى الرصيد في قائمة المدينين.';
  }

  @override
  String deleteCarriesDebt(String count) {
    return '$count من هذه الفواتير عليها ديون. الديون لا تُحذف: تبقى في حسابات الزبائن.';
  }

  @override
  String get deleteInvoiceCarriesDebt =>
      'على هذه الفاتورة دين. الدين لا يُحذف: يبقى في حساب الزبون.';

  @override
  String get statsOutstandingNow => 'الديون القائمة الآن';

  @override
  String get statsNewDebt => 'ديون جديدة';

  @override
  String get statsCollected => 'المحصَّل';

  @override
  String get statsCollectionRate => 'نسبة التحصيل';

  @override
  String get statsTopDebtors => 'أكبر المدينين';

  @override
  String homeDebtsOverdue(String count) {
    return '$count متأخر';
  }

  @override
  String get homeDebtsNoOverdue => 'لا متأخرين';

  @override
  String get debtLockedMessage => 'الديون محمية بالرمز.';

  @override
  String get unlock => 'فتح';

  @override
  String get openingBalancesTitle => 'الأرصدة الافتتاحية';

  @override
  String get openingBalancesIntro =>
      'للانتقال من الدفتر الورقي: أدخل ما على كل زبون، واحداً تلو الآخر.';

  @override
  String openingExistingBalance(String balance) {
    return 'زبون موجود · $balance';
  }

  @override
  String get openingOwesToggle => 'عليه';

  @override
  String get openingCreditToggle => 'له';

  @override
  String get openingDateLabel => 'التاريخ (اختياري)';

  @override
  String get openingAddedNew => 'زبون جديد';

  @override
  String get openingAddedExisting => 'زبون موجود';

  @override
  String openingSessionTotal(String count) {
    return 'أُدخل $count';
  }

  @override
  String get openingNameRequired => 'اكتب اسم الزبون';

  @override
  String openingPickedCustomer(String name) {
    return 'الإضافة إلى $name';
  }

  @override
  String get manualDebtNoteHint => 'مقابل ماذا؟ (اختياري)';

  @override
  String get adjustmentIncrease => 'زيادة الدين';

  @override
  String get adjustmentDecrease => 'إنقاص الدين';

  @override
  String get entrySaved => 'تم الحفظ';

  @override
  String get auditDebtReversal => 'عكس حركة في دفتر الديون';

  @override
  String get auditDebtAdjustment => 'تسوية رصيد';

  @override
  String get auditCreditLimitOverride => 'تجاوز حد الدين';

  @override
  String get seedDebtsTitle => 'توليد دفتر ديون (تجريبي)';

  @override
  String get seedDebtsSubtitle =>
      '5,000 زبون و200,000 حركة، لتجربة قائمة المدينين بالحجم الكامل';

  @override
  String seedingDebts(String done, String total) {
    return 'كتابة الحركات: $done / $total';
  }

  @override
  String get pinAutoLockTitle => 'إعادة القفل بعد';

  @override
  String get pinAutoLockHint =>
      'ما يفتحه الرمز — الديون وسجل العمليات وأكواد البطاقات — يُقفل من جديد بعد هذه المدة دون لمس، وفوراً عند الخروج من التطبيق.';

  @override
  String minutesCount(int minutes) {
    final intl.NumberFormat minutesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String minutesString = minutesNumberFormat.format(minutes);

    String _temp0 = intl.Intl.pluralLogic(
      minutes,
      locale: localeName,
      other: '$minutesString دقيقة',
      few: '$minutesString دقائق',
      two: 'دقيقتان',
      one: 'دقيقة واحدة',
    );
    return '$_temp0';
  }

  @override
  String get saleCreditButton => 'آجل / جزئي';

  @override
  String get settingCashReceived => 'حقل المبلغ المستلم';

  @override
  String get settingCashReceivedHint =>
      'إظهار حقل صغير «المبلغ المستلم» تحت الإجمالي يحسب الباقي للزبون';

  @override
  String get cashReceivedTitle => 'المبلغ المستلم';

  @override
  String cashReceivedValue(String amount) {
    return 'المستلم $amount';
  }

  @override
  String changeShort(String amount) {
    return 'الباقي $amount';
  }

  @override
  String get cashReceivedClear => 'مسح';
}
