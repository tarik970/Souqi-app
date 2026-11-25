/// Everything that shapes a printed or shared invoice, as one immutable
/// value. Stored key-by-key in the `settings` table (see [SettingsKeys]);
/// nothing here is hard-coded per shop.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants/settings_keys.dart';
import '../../core/printing/print_geometry.dart';
import '../../core/utils/normalize.dart';

/// What the main button does after a sale is saved.
enum OutputMode {
  print('PRINT'),
  share('SHARE'),
  both('BOTH');

  const OutputMode(this.db);

  final String db;

  static OutputMode fromDb(String? value) =>
      values.firstWhere((m) => m.db == value, orElse: () => OutputMode.print);

  bool get prints => this != OutputMode.share;
  bool get shares => this != OutputMode.print;
}

/// How a currency is written next to an amount.
enum CurrencyDisplay {
  symbol('SYMBOL'),
  code('CODE');

  const CurrencyDisplay(this.db);

  final String db;

  static CurrencyDisplay fromDb(String? value) => values
      .firstWhere((m) => m.db == value, orElse: () => CurrencyDisplay.symbol);
}

class InvoiceSettings {
  const InvoiceSettings({
    this.paperWidthMm = 80,
    this.printerDpi = 203,
    this.sideMarginMm = 3.5,
    this.printableDotsOverride,
    this.feedLines = 3,
    this.cutPaper = false,
    this.printerAddress,
    this.printerName,
    this.baseFontSize = 22,
    this.shopName = '',
    this.logoPng,
    this.headerText = '',
    this.footerText = '',
    this.language = 'ar',
    this.showItemCode = false,
    this.showUnit = true,
    this.showUnitPrice = true,
    this.showDateTime = true,
    this.showInvoiceNumber = true,
    this.showCustomerName = true,
    this.showCustomerPhone = true,
    this.showAccountNumber = true,
    this.maskAccountNumber = false,
    this.showPoweredBy = true,
    this.printCodeQr = false,
    this.codesOnSeparateSlips = false,
    this.currencyDisplay = CurrencyDisplay.symbol,
    this.extraCurrencies = const [],
    this.outputMode = OutputMode.print,
    this.shareWidthMm,
    this.defaultCountryCode = '963',
  });

  // Paper and printer.
  final double paperWidthMm;
  final int printerDpi;
  final double sideMarginMm;

  /// "Advanced: printable width (dots)". Null = computed from the three
  /// values above.
  final int? printableDotsOverride;
  final int feedLines;
  final bool cutPaper;

  /// The remembered default printer (Bluetooth MAC address and its name).
  final String? printerAddress;
  final String? printerName;

  // Content.
  /// In printer dots: the invoice is laid out with one logical pixel per dot.
  final int baseFontSize;
  final String shopName;

  /// The logo as PNG bytes (a local, downscaled copy), or null.
  final Uint8List? logoPng;
  final String headerText;
  final String footerText;

  /// The INVOICE language ('ar' / 'en'), independent of the app language.
  final String language;
  final bool showItemCode;
  final bool showUnit;
  final bool showUnitPrice;
  final bool showDateTime;
  final bool showInvoiceNumber;
  final bool showCustomerName;
  final bool showCustomerPhone;
  final bool showAccountNumber;
  final bool maskAccountNumber;
  final bool showPoweredBy;

  /// Print a QR code of each sold card code under its digits.
  final bool printCodeQr;

  /// Print each sold card on its own slip after the invoice, with a feed
  /// (and a cut) between slips. Printer only: a shared image or PDF always
  /// holds the invoice and its cards together.
  final bool codesOnSeparateSlips;
  final CurrencyDisplay currencyDisplay;

  /// Up to two extra currencies the total is also shown in.
  final List<String> extraCurrencies;

  // Output and sharing.
  final OutputMode outputMode;

  /// Width the SHARED image is laid out for. Null = same as the paper.
  final double? shareWidthMm;
  final String defaultCountryCode;

  static const double paper80 = 80;
  static const double paper58 = 58;
  static const int minFontSize = 14;
  static const int maxFontSize = 40;
  static const int maxFeedLines = 10;

  bool get isRtl => language == 'ar';

  bool get hasPrinter => printerAddress != null && printerAddress!.isNotEmpty;

  /// Printable width from paper, margins and resolution — before any
  /// override.
  int get computedPrintableDots => computePrintableDots(
        paperWidthMm: paperWidthMm,
        sideMarginMm: sideMarginMm,
        dpi: printerDpi,
      );

  /// The width the printer image is rendered at, in dots.
  int get printableDots => printableDotsOverride == null
      ? computedPrintableDots
      : snapDots(printableDotsOverride!);

  /// The logical width the shared image is laid out at. Follows the printer
  /// width unless a share width is set; printer-only settings (feed, cut)
  /// never apply to a shared image.
  int get shareDots => shareWidthMm == null
      ? printableDots
      : computePrintableDots(
          paperWidthMm: shareWidthMm!,
          sideMarginMm: sideMarginMm,
          dpi: printerDpi,
        );

  /// Page width of a shared PDF.
  double get sharePageWidthMm => shareWidthMm ?? paperWidthMm;

  static double _mm(String? raw, double fallback) {
    if (raw == null) return fallback;
    final value = double.tryParse(normalizeDigits(raw.trim()));
    return value == null || !value.isFinite || value <= 0 ? fallback : value;
  }

  static bool _bool(String? raw) => raw == '1' || raw == 'true';

  /// Builds the settings from stored rows; missing keys take
  /// [SettingsKeys.defaults].
  factory InvoiceSettings.fromMap(Map<String, String> stored) {
    String get(String key) => stored[key] ?? SettingsKeys.defaults[key] ?? '';

    Uint8List? logo;
    final logoRaw = get(SettingsKeys.shopLogoBase64);
    if (logoRaw.isNotEmpty) {
      try {
        logo = base64Decode(logoRaw);
      } on FormatException {
        logo = null;
      }
    }

    var extras = const <String>[];
    try {
      final decoded = jsonDecode(get(SettingsKeys.extraTotalCurrencies));
      if (decoded is List) {
        extras = decoded.whereType<String>().toSet().take(2).toList();
      }
    } on FormatException {
      extras = const [];
    }

    final marginRaw = double.tryParse(get(SettingsKeys.sideMarginMm));
    final overrideRaw = int.tryParse(get(SettingsKeys.printableDotsOverride));
    final shareRaw = get(SettingsKeys.shareWidthMm);
    final printerAddress = get(SettingsKeys.printerMac);
    final printerName = get(SettingsKeys.printerName);
    final language = get(SettingsKeys.invoiceLanguage);

    return InvoiceSettings(
      paperWidthMm: _mm(get(SettingsKeys.paperWidthMm), paper80),
      printerDpi: (int.tryParse(get(SettingsKeys.printerDpi)) ?? 203)
          .clamp(100, 600),
      sideMarginMm: marginRaw == null || !marginRaw.isFinite || marginRaw < 0
          ? 3.5
          : marginRaw,
      printableDotsOverride:
          overrideRaw == null || overrideRaw <= 0 ? null : overrideRaw,
      feedLines: (int.tryParse(get(SettingsKeys.feedLines)) ?? 3)
          .clamp(0, maxFeedLines),
      cutPaper: _bool(get(SettingsKeys.cutPaper)),
      printerAddress: printerAddress.isEmpty ? null : printerAddress,
      printerName: printerName.isEmpty ? null : printerName,
      baseFontSize: (int.tryParse(get(SettingsKeys.baseFontSize)) ?? 22)
          .clamp(minFontSize, maxFontSize),
      shopName: get(SettingsKeys.shopName),
      logoPng: logo,
      headerText: get(SettingsKeys.headerText),
      footerText: get(SettingsKeys.footerText),
      language: language == 'en' ? 'en' : 'ar',
      showItemCode: _bool(get(SettingsKeys.showItemCode)),
      showUnit: _bool(get(SettingsKeys.showUnit)),
      showUnitPrice: _bool(get(SettingsKeys.showUnitPrice)),
      showDateTime: _bool(get(SettingsKeys.showDateTime)),
      showInvoiceNumber: _bool(get(SettingsKeys.showInvoiceNumber)),
      showCustomerName: _bool(get(SettingsKeys.showCustomerName)),
      showCustomerPhone: _bool(get(SettingsKeys.showCustomerPhone)),
      showAccountNumber: _bool(get(SettingsKeys.showAccountNumber)),
      maskAccountNumber: _bool(get(SettingsKeys.maskAccountNumber)),
      showPoweredBy: _bool(get(SettingsKeys.showPoweredBy)),
      printCodeQr: _bool(get(SettingsKeys.printCodeQr)),
      codesOnSeparateSlips: _bool(get(SettingsKeys.codesOnSeparateSlips)),
      currencyDisplay:
          CurrencyDisplay.fromDb(get(SettingsKeys.currencyDisplay)),
      extraCurrencies: extras,
      outputMode: OutputMode.fromDb(get(SettingsKeys.outputMode)),
      shareWidthMm: shareRaw.isEmpty ? null : _mm(shareRaw, paper80),
      defaultCountryCode: get(SettingsKeys.defaultCountryCode),
    );
  }

  static String _mmText(double mm) =>
      mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : '$mm';

  /// One row per setting, ready for the `settings` table.
  Map<String, String> toMap() => {
        SettingsKeys.paperWidthMm: _mmText(paperWidthMm),
        SettingsKeys.printerDpi: '$printerDpi',
        SettingsKeys.sideMarginMm: _mmText(sideMarginMm),
        SettingsKeys.printableDotsOverride:
            printableDotsOverride == null ? '' : '$printableDotsOverride',
        SettingsKeys.feedLines: '$feedLines',
        SettingsKeys.cutPaper: cutPaper ? '1' : '0',
        SettingsKeys.printerMac: printerAddress ?? '',
        SettingsKeys.printerName: printerName ?? '',
        SettingsKeys.baseFontSize: '$baseFontSize',
        SettingsKeys.shopName: shopName,
        SettingsKeys.shopLogoBase64:
            logoPng == null ? '' : base64Encode(logoPng!),
        SettingsKeys.headerText: headerText,
        SettingsKeys.footerText: footerText,
        SettingsKeys.invoiceLanguage: language,
        SettingsKeys.showItemCode: showItemCode ? '1' : '0',
        SettingsKeys.showUnit: showUnit ? '1' : '0',
        SettingsKeys.showUnitPrice: showUnitPrice ? '1' : '0',
        SettingsKeys.showDateTime: showDateTime ? '1' : '0',
        SettingsKeys.showInvoiceNumber: showInvoiceNumber ? '1' : '0',
        SettingsKeys.showCustomerName: showCustomerName ? '1' : '0',
        SettingsKeys.showCustomerPhone: showCustomerPhone ? '1' : '0',
        SettingsKeys.showAccountNumber: showAccountNumber ? '1' : '0',
        SettingsKeys.maskAccountNumber: maskAccountNumber ? '1' : '0',
        SettingsKeys.showPoweredBy: showPoweredBy ? '1' : '0',
        SettingsKeys.printCodeQr: printCodeQr ? '1' : '0',
        SettingsKeys.codesOnSeparateSlips: codesOnSeparateSlips ? '1' : '0',
        SettingsKeys.currencyDisplay: currencyDisplay.db,
        SettingsKeys.extraTotalCurrencies: jsonEncode(extraCurrencies),
        SettingsKeys.outputMode: outputMode.db,
        SettingsKeys.shareWidthMm:
            shareWidthMm == null ? '' : _mmText(shareWidthMm!),
        SettingsKeys.defaultCountryCode: defaultCountryCode,
      };

  InvoiceSettings copyWith({
    double? paperWidthMm,
    int? printerDpi,
    double? sideMarginMm,
    int? Function()? printableDotsOverride,
    int? feedLines,
    bool? cutPaper,
    String? Function()? printerAddress,
    String? Function()? printerName,
    int? baseFontSize,
    String? shopName,
    Uint8List? Function()? logoPng,
    String? headerText,
    String? footerText,
    String? language,
    bool? showItemCode,
    bool? showUnit,
    bool? showUnitPrice,
    bool? showDateTime,
    bool? showInvoiceNumber,
    bool? showCustomerName,
    bool? showCustomerPhone,
    bool? showAccountNumber,
    bool? maskAccountNumber,
    bool? showPoweredBy,
    bool? printCodeQr,
    bool? codesOnSeparateSlips,
    CurrencyDisplay? currencyDisplay,
    List<String>? extraCurrencies,
    OutputMode? outputMode,
    double? Function()? shareWidthMm,
    String? defaultCountryCode,
  }) {
    return InvoiceSettings(
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      printerDpi: printerDpi ?? this.printerDpi,
      sideMarginMm: sideMarginMm ?? this.sideMarginMm,
      printableDotsOverride: printableDotsOverride != null
          ? printableDotsOverride()
          : this.printableDotsOverride,
      feedLines: feedLines ?? this.feedLines,
      cutPaper: cutPaper ?? this.cutPaper,
      printerAddress:
          printerAddress != null ? printerAddress() : this.printerAddress,
      printerName: printerName != null ? printerName() : this.printerName,
      baseFontSize: baseFontSize ?? this.baseFontSize,
      shopName: shopName ?? this.shopName,
      logoPng: logoPng != null ? logoPng() : this.logoPng,
      headerText: headerText ?? this.headerText,
      footerText: footerText ?? this.footerText,
      language: language ?? this.language,
      showItemCode: showItemCode ?? this.showItemCode,
      showUnit: showUnit ?? this.showUnit,
      showUnitPrice: showUnitPrice ?? this.showUnitPrice,
      showDateTime: showDateTime ?? this.showDateTime,
      showInvoiceNumber: showInvoiceNumber ?? this.showInvoiceNumber,
      showCustomerName: showCustomerName ?? this.showCustomerName,
      showCustomerPhone: showCustomerPhone ?? this.showCustomerPhone,
      showAccountNumber: showAccountNumber ?? this.showAccountNumber,
      maskAccountNumber: maskAccountNumber ?? this.maskAccountNumber,
      showPoweredBy: showPoweredBy ?? this.showPoweredBy,
      printCodeQr: printCodeQr ?? this.printCodeQr,
      codesOnSeparateSlips: codesOnSeparateSlips ?? this.codesOnSeparateSlips,
      currencyDisplay: currencyDisplay ?? this.currencyDisplay,
      extraCurrencies: extraCurrencies ?? this.extraCurrencies,
      outputMode: outputMode ?? this.outputMode,
      shareWidthMm: shareWidthMm != null ? shareWidthMm() : this.shareWidthMm,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
    );
  }
}
