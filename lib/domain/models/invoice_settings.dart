/// Everything that shapes a printed or shared invoice, as one immutable
/// value. Stored key-by-key in the `settings` table (see [SettingsKeys]);
/// nothing here is hard-coded per shop.
library;

import 'dart:convert';
import 'dart:typed_data';

import '../../core/constants/settings_keys.dart';
import '../../core/printing/escpos.dart';
import '../../core/printing/print_geometry.dart';
import '../../core/printing/print_job.dart';
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
    this.sideMarginMm = defaultSideMargin80Mm,
    this.printableDotsOverride,
    this.feedLines = 3,
    this.cutPaper = false,
    this.printerAddress,
    this.printerName,
    this.printerLanguages = const {},
    this.printerOffsets = const {},
    this.escPosImageMode = EscPosImageMode.gsV0,
    this.printChunkSize = 1024,
    this.printChunkDelayMs = 12,
    this.tsplOneIsBlack = false,
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
    this.showPaidAmount = true,
    this.showRemainingAmount = true,
    this.showPreviousBalance = false,
    this.showNewBalance = false,
    this.printCodeQr = false,
    this.codesOnSeparateSlips = false,
    this.currencyDisplay = CurrencyDisplay.symbol,
    this.extraCurrencies = const [],
    this.outputMode = OutputMode.print,
    this.shareWidthMm,
    this.defaultCountryCode = '963',
    this.trialNotice = false,
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

  // Printer compatibility (the printer diagnostics screen).
  /// The command language of every printer chosen so far, by address. A
  /// printer that is not in here speaks ESC/POS.
  final Map<String, PrinterLanguage> printerLanguages;

  /// The calibration of every printer chosen so far, by address: how many
  /// dots its print is moved to the right (negative = left). A printer
  /// that is not in here prints where the defaults put it.
  final Map<String, int> printerOffsets;

  /// How the picture is sent to an ESC/POS printer.
  final EscPosImageMode escPosImageMode;

  /// Bytes written to the printer at a time, and the pause between two
  /// writes: a slow printer drops what arrives faster than it can take.
  final int printChunkSize;
  final int printChunkDelayMs;

  /// TSPL only: this printer's firmware burns a dot for a 1 bit (the
  /// convention is 0).
  final bool tsplOneIsBlack;

  static const List<int> chunkSizes = [1024, 512, 256];
  static const List<int> chunkDelaysMs = [12, 30, 60];

  /// The language of the chosen printer.
  PrinterLanguage get printerLanguage =>
      printerLanguages[printerAddress] ?? PrinterLanguage.escPos;

  /// The language remembered for the printer at [address], if it was ever
  /// chosen before.
  PrinterLanguage languageOf(String address) =>
      printerLanguages[address] ?? PrinterLanguage.escPos;

  /// These settings with [language] remembered for the printer at
  /// [address] (default: the chosen printer; nothing changes without one).
  InvoiceSettings withPrinterLanguage(
    PrinterLanguage language, {
    String? address,
  }) {
    final target = address ?? printerAddress;
    if (target == null || target.isEmpty) return this;
    return copyWith(printerLanguages: {...printerLanguages, target: language});
  }

  /// The calibration offset of the chosen printer, in dots.
  int get printerOffsetDots => printerOffsets[printerAddress] ?? 0;

  /// These settings with the chosen printer's print moved to [dots] (made
  /// a valid offset first). Nothing changes without a printer.
  InvoiceSettings withPrinterOffset(int dots) {
    final target = printerAddress;
    if (target == null || target.isEmpty) return this;
    return copyWith(
      printerOffsets: {...printerOffsets, target: snapOffsetDots(dots)},
    );
  }

  /// What shapes the bytes of a print job for the chosen printer.
  PrintFormat get printFormat => printFormatFor(printerLanguage);

  /// The same for the chosen printer spoken to in [language] — what a
  /// diagnostics test of the OTHER language is built with. The head, and
  /// with it where the image sits, depends on the language.
  PrintFormat printFormatFor(PrinterLanguage language) => PrintFormat(
        language: language,
        imageMode: escPosImageMode,
        dpi: printerDpi,
        cut: cutPaper,
        tsplZeroIsBlack: !tsplOneIsBlack,
        offsetDots: printerOffsetDots,
        headDots: headDotsFor(language),
        paperWidthMm: paperWidthMm,
      );

  /// Dots of the print head a printer for this paper normally has.
  int get headDots => headDotsFor(printerLanguage);

  int headDotsFor(PrinterLanguage language) => standardHeadDots(
        paperWidthMm: paperWidthMm,
        dpi: printerDpi,
        labelPrinter: language == PrinterLanguage.tspl,
      );

  /// The image is wider than the print head can print.
  bool get widerThanHead => printableDots > headDots;

  /// These settings with the printable width brought down to [headDots]:
  /// back to the computed width when that fits, else an explicit override.
  InvoiceSettings fittedToHead() => copyWith(
        printableDotsOverride: () =>
            computedPrintableDots <= headDots ? null : headDots,
      );

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

  // Debt lines (the debt ledger). Paid and remaining are printed only on a
  // sale that was not simply paid in full; the two balances only when the
  // invoice has a customer whose balance is not zero.
  final bool showPaidAmount;
  final bool showRemainingAmount;
  final bool showPreviousBalance;
  final bool showNewBalance;

  /// These settings with every debt line switched off — what the invoice is
  /// rendered with while the debt ledger feature is off, so that nothing of
  /// it reaches the paper, not even on an invoice saved while it was on.
  InvoiceSettings withoutDebtLines() => copyWith(
        showPaidAmount: false,
        showRemainingAmount: false,
        showPreviousBalance: false,
        showNewBalance: false,
      );

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

  /// Print the small "trial version" line. NOT a stored setting: it is set
  /// for rendering while the app runs on its trial (`LicenseStatus.isTrial`)
  /// and is in neither [fromMap] nor [toMap].
  final bool trialNotice;

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

    var languages = const <String, PrinterLanguage>{};
    try {
      final decoded = jsonDecode(get(SettingsKeys.printerLanguages));
      if (decoded is Map) {
        languages = {
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is String)
              entry.key as String:
                  PrinterLanguage.fromDb(entry.value as String),
        };
      }
    } on FormatException {
      languages = const {};
    }
    var offsets = const <String, int>{};
    try {
      final decoded = jsonDecode(get(SettingsKeys.printerOffsets));
      if (decoded is Map) {
        offsets = {
          for (final entry in decoded.entries)
            if (entry.key is String && entry.value is int)
              entry.key as String: snapOffsetDots(entry.value as int),
        };
      }
    } on FormatException {
      offsets = const {};
    }
    final chunkSize = int.tryParse(get(SettingsKeys.printChunkSize));
    final chunkDelay = int.tryParse(get(SettingsKeys.printChunkDelayMs));

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
          ? defaultSideMargin80Mm
          : marginRaw,
      printableDotsOverride:
          overrideRaw == null || overrideRaw <= 0 ? null : overrideRaw,
      feedLines: (int.tryParse(get(SettingsKeys.feedLines)) ?? 3)
          .clamp(0, maxFeedLines),
      cutPaper: _bool(get(SettingsKeys.cutPaper)),
      printerAddress: printerAddress.isEmpty ? null : printerAddress,
      printerName: printerName.isEmpty ? null : printerName,
      printerLanguages: languages,
      printerOffsets: offsets,
      escPosImageMode:
          EscPosImageMode.fromDb(get(SettingsKeys.escPosImageMode)),
      printChunkSize: chunkSizes.contains(chunkSize) ? chunkSize! : 1024,
      printChunkDelayMs:
          chunkDelaysMs.contains(chunkDelay) ? chunkDelay! : 12,
      tsplOneIsBlack: _bool(get(SettingsKeys.tsplOneIsBlack)),
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
      showPaidAmount: _bool(get(SettingsKeys.showPaidAmount)),
      showRemainingAmount: _bool(get(SettingsKeys.showRemainingAmount)),
      showPreviousBalance: _bool(get(SettingsKeys.showPreviousBalance)),
      showNewBalance: _bool(get(SettingsKeys.showNewBalance)),
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
        SettingsKeys.printerOffsets: jsonEncode(printerOffsets),
        SettingsKeys.printerLanguages: jsonEncode({
          for (final entry in printerLanguages.entries)
            entry.key: entry.value.db,
        }),
        SettingsKeys.escPosImageMode: escPosImageMode.db,
        SettingsKeys.printChunkSize: '$printChunkSize',
        SettingsKeys.printChunkDelayMs: '$printChunkDelayMs',
        SettingsKeys.tsplOneIsBlack: tsplOneIsBlack ? '1' : '0',
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
        SettingsKeys.showPaidAmount: showPaidAmount ? '1' : '0',
        SettingsKeys.showRemainingAmount: showRemainingAmount ? '1' : '0',
        SettingsKeys.showPreviousBalance: showPreviousBalance ? '1' : '0',
        SettingsKeys.showNewBalance: showNewBalance ? '1' : '0',
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
    Map<String, PrinterLanguage>? printerLanguages,
    Map<String, int>? printerOffsets,
    EscPosImageMode? escPosImageMode,
    int? printChunkSize,
    int? printChunkDelayMs,
    bool? tsplOneIsBlack,
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
    bool? showPaidAmount,
    bool? showRemainingAmount,
    bool? showPreviousBalance,
    bool? showNewBalance,
    bool? printCodeQr,
    bool? codesOnSeparateSlips,
    CurrencyDisplay? currencyDisplay,
    List<String>? extraCurrencies,
    OutputMode? outputMode,
    double? Function()? shareWidthMm,
    String? defaultCountryCode,
    bool? trialNotice,
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
      printerLanguages: printerLanguages ?? this.printerLanguages,
      printerOffsets: printerOffsets ?? this.printerOffsets,
      escPosImageMode: escPosImageMode ?? this.escPosImageMode,
      printChunkSize: printChunkSize ?? this.printChunkSize,
      printChunkDelayMs: printChunkDelayMs ?? this.printChunkDelayMs,
      tsplOneIsBlack: tsplOneIsBlack ?? this.tsplOneIsBlack,
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
      showPaidAmount: showPaidAmount ?? this.showPaidAmount,
      showRemainingAmount: showRemainingAmount ?? this.showRemainingAmount,
      showPreviousBalance: showPreviousBalance ?? this.showPreviousBalance,
      showNewBalance: showNewBalance ?? this.showNewBalance,
      printCodeQr: printCodeQr ?? this.printCodeQr,
      codesOnSeparateSlips: codesOnSeparateSlips ?? this.codesOnSeparateSlips,
      currencyDisplay: currencyDisplay ?? this.currencyDisplay,
      extraCurrencies: extraCurrencies ?? this.extraCurrencies,
      outputMode: outputMode ?? this.outputMode,
      shareWidthMm: shareWidthMm != null ? shareWidthMm() : this.shareWidthMm,
      defaultCountryCode: defaultCountryCode ?? this.defaultCountryCode,
      trialNotice: trialNotice ?? this.trialNotice,
    );
  }
}
