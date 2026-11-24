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
  String get saleFavoritesHint => 'ضع نجمة على المنتجات لتظهر هنا كأزرار سريعة';

  @override
  String get saleSearchHint => 'الاسم أو الرمز — اضغط إدخال للرمز المطابق';

  @override
  String get cartEmpty => 'السلة فارغة';

  @override
  String get cartEmptyHint => 'اضغط على منتج مفضّل أو ابحث عن صنف';

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
  String get invoiceSavedTitle => 'تم حفظ الفاتورة';

  @override
  String invoiceNoLabel(String no) {
    return 'فاتورة رقم $no';
  }

  @override
  String get printInvoice => 'طباعة';

  @override
  String get sharePdf => 'مشاركة PDF';

  @override
  String get newSale => 'فاتورة جديدة';

  @override
  String get backToHome => 'العودة للرئيسية';
}
