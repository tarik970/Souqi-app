import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/features.dart';
import '../../core/platform/native_bridge.dart';
import '../../core/printing/print_geometry.dart';
import '../../core/printing/print_job.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../core/widgets/numeric_input.dart';
import '../../domain/models/currency.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import '../license/license_providers.dart';
import '../security/pin_session.dart';
import 'invoice_output.dart';
import 'invoice_preview.dart';
import 'invoice_providers.dart';
import 'contact_numbers_settings.dart';
import 'logo_codec.dart';
import 'output_messages.dart';
import 'payment_qr_settings.dart';
import 'printer_diagnostics_screen.dart';
import 'printer_picker.dart';
import 'printer_widgets.dart';
import 'sample_invoice.dart';
import 'settings_parts.dart';

/// Invoice & printing settings with a live preview.
///
/// Every control writes straight into [invoiceSettingsProvider]: the state
/// changes first (so the preview repaints at once) and the changed keys are
/// then saved to the database. There is no Save button to forget.
class InvoiceSettingsScreen extends ConsumerWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final loaded = ref.watch(
      invoiceSettingsProvider.select((settings) => settings.hasValue),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.invoiceSettingsTitle)),
      body: loaded
          ? const _SettingsBody()
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

double? _parseDecimal(String text) {
  final value = double.tryParse(
    normalizeDigits(text.trim()).replaceAll('٫', '.').replaceAll(',', '.'),
  );
  return value == null || !value.isFinite ? null : value;
}

String _mmText(double mm) =>
    mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : '$mm';

class _SettingsBody extends ConsumerStatefulWidget {
  const _SettingsBody();

  @override
  ConsumerState<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends ConsumerState<_SettingsBody> {
  late final TextEditingController _shopName;
  late final TextEditingController _header;
  late final TextEditingController _footer;
  late bool _customPaper;
  final _sampleTime = DateTime.now();

  /// Bumped when the margin is changed from code (picking a paper preset),
  /// so its field is rebuilt with the new text.
  int _marginEpoch = 0;

  /// The same for the width override, when the width warning fixes it.
  int _dotsEpoch = 0;
  bool _testing = false;

  InvoiceSettings get _settings =>
      ref.read(invoiceSettingsProvider).requireValue;

  @override
  void initState() {
    super.initState();
    final s = _settings;
    _shopName = TextEditingController(text: s.shopName);
    _header = TextEditingController(text: s.headerText);
    _footer = TextEditingController(text: s.footerText);
    _customPaper = s.paperWidthMm != InvoiceSettings.paper80 &&
        s.paperWidthMm != InvoiceSettings.paper58;
  }

  @override
  void dispose() {
    _shopName.dispose();
    _header.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _change(InvoiceSettings Function(InvoiceSettings s) update) {
    ref.read(invoiceSettingsProvider.notifier).change(update);
  }

  void _selectPaper(String choice) {
    if (choice == 'custom') {
      setState(() => _customPaper = true);
      return;
    }
    final mm = choice == '58' ? InvoiceSettings.paper58 : InvoiceSettings.paper80;
    setState(() {
      _customPaper = false;
      _marginEpoch++;
    });
    // Each standard paper has its own print head, hence its own margin.
    _change((s) => s.copyWith(
          paperWidthMm: mm,
          sideMarginMm: defaultSideMarginFor(mm),
        ));
  }

  Future<void> _choosePrinter() => chooseAndRememberPrinter(context, ref);

  void _fitWidthToHead() {
    setState(() => _dotsEpoch++);
    _change((s) => s.fittedToHead());
  }

  Future<void> _forgetPrinter() async {
    _change((s) => s.copyWith(
          printerAddress: () => null,
          printerName: () => null,
        ));
    try {
      await ref.read(nativeBridgeProvider).disconnectPrinter();
    } on OutputException {
      // Nothing was connected.
    }
  }

  Future<void> _testPrint() async {
    if (_testing) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _testing = true);
    // `ref` is only read before the first await; after it the providers are
    // reached through the container, which outlives this screen.
    final container = ProviderScope.containerOf(context, listen: false);
    final output = ref.read(invoiceOutputProvider);
    final settings = _settings;
    try {
      final currencies = await container.read(currenciesProvider.future);
      final baseCode = await container.read(baseCurrencyCodeProvider.future);
      await output.printInvoice(
        buildSampleInvoice(
          settings: settings,
          currencies: currencies,
          baseCode: baseCode,
          withDebtLines: featureOn(Feature.debt),
        ),
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.printSent)));
    } on OutputException catch (e) {
      if (mounted) {
        showOutputError(context, ref, e, offerInvoiceSettings: false);
      }
    } catch (e) {
      if (mounted) {
        showOutputError(
          context,
          ref,
          OutputException(OutputFailure.unknown, '$e'),
          offerInvoiceSettings: false,
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _pickLogo() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // The photo picker is another app in front of this one, and it does not
    // go through the native bridge: the PIN locks are told here.
    final guard = ref.read(pinBackgroundGuardProvider)
      ..externalActionStarting();
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      // A downscaled PNG copy is stored with the settings; the original
      // photo can be moved or deleted afterwards.
      final png = await prepareLogo(await picked.readAsBytes());
      if (!mounted) return;
      _change((s) => s.copyWith(logoPng: () => png));
    } catch (_) {
      // No picker on this phone: nothing was opened.
      guard.externalActionFailed();
      messenger.showSnackBar(SnackBar(content: Text(l10n.logoError)));
    }
  }

  void _showFullPreview(Widget preview) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: preview,
            ),
            PositionedDirectional(
              top: 4,
              end: 4,
              child: IconButton.filledTonal(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final appLocale = ref.watch(appLocaleProvider).languageCode;
    final s = ref.watch(invoiceSettingsProvider).requireValue;
    final currencies = ref.watch(currenciesProvider).value;
    final baseCode = ref.watch(baseCurrencyCodeProvider).value;
    final logo = ref.watch(invoiceLogoProvider).value;

    Widget buildPreview({double maxWidth = 340}) {
      if (currencies == null || baseCode == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return InvoicePaperPreview(
        key: const ValueKey('invoice-preview'),
        invoice: buildSampleInvoice(
          settings: s,
          currencies: currencies,
          baseCode: baseCode,
          now: _sampleTime,
          withDebtLines: featureOn(Feature.debt),
        ),
        settings: s,
        currencies: {for (final c in currencies) c.code: c},
        logo: logo,
        maxWidth: maxWidth,
      );
    }

    final previewPane = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Stack(
        children: [
          Positioned.fill(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: buildPreview(),
            ),
          ),
          PositionedDirectional(
            top: 4,
            end: 4,
            child: IconButton.filledTonal(
              tooltip: l10n.previewTitle,
              icon: const Icon(Icons.fullscreen),
              onPressed: () => _showFullPreview(buildPreview(maxWidth: 480)),
            ),
          ),
        ],
      ),
    );

    final form = ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        ..._outputSection(l10n, theme, s),
        ..._printerSection(l10n, theme, s),
        ..._paperSection(l10n, theme, s),
        ..._shopSection(l10n, theme, s),
        const ContactNumbersSection(),
        const PaymentQrSettingsSection(),
        ..._contentSection(l10n, s),
        ..._currencySection(l10n, theme, s, currencies, baseCode, appLocale),
        ..._sharingSection(l10n, s),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 840) {
          return Row(
            children: [
              Expanded(child: form),
              SizedBox(width: 400, child: previewPane),
            ],
          );
        }
        final previewHeight =
            (constraints.maxHeight * 0.36).clamp(140.0, 340.0);
        return Column(
          children: [
            SizedBox(height: previewHeight, child: previewPane),
            Expanded(child: form),
          ],
        );
      },
    );
  }

  // ---- Sections --------------------------------------------------------

  List<Widget> _outputSection(
    AppLocalizations l10n,
    ThemeData theme,
    InvoiceSettings s,
  ) {
    return [
      _SectionTitle(l10n.sectionOutput),
      _Padded(
        child: SegmentedButton<OutputMode>(
          key: const ValueKey('output-mode'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: OutputMode.print,
              label: Text(l10n.outputModePrint),
            ),
            ButtonSegment(
              value: OutputMode.share,
              label: Text(l10n.outputModeShare),
            ),
            ButtonSegment(
              value: OutputMode.both,
              label: Text(l10n.outputModeBoth),
            ),
          ],
          selected: {s.outputMode},
          onSelectionChanged: (selection) =>
              _change((s) => s.copyWith(outputMode: selection.first)),
        ),
      ),
      _Hint(l10n.outputModeHint),
    ];
  }

  List<Widget> _printerSection(
    AppLocalizations l10n,
    ThemeData theme,
    InvoiceSettings s,
  ) {
    return [
      _SectionTitle(l10n.sectionPrinter),
      ListTile(
        leading: Icon(s.hasPrinter ? Icons.print : Icons.print_disabled),
        title: Text(s.hasPrinter
            ? (s.printerName ?? s.printerAddress!)
            : l10n.printerNone),
        subtitle: s.hasPrinter
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.printerAddress!, textDirection: TextDirection.ltr),
                  // Where its print sits (the diagnostics screen sets it).
                  Text(
                    printerCalibrationText(l10n, s),
                    key: const ValueKey('printer-calibration-info'),
                  ),
                ],
              )
            : null,
        trailing: TextButton(
          onPressed: _choosePrinter,
          child: Text(l10n.choosePrinter),
        ),
      ),
      _Padded(
        child: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('test-print'),
              onPressed: _testing ? null : _testPrint,
              icon: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long),
              label: Text(l10n.testPrint),
            ),
            if (s.hasPrinter)
              TextButton(
                onPressed: _forgetPrinter,
                child: Text(l10n.forgetPrinter),
              ),
          ],
        ),
      ),
      if (s.hasPrinter) ...[
        _Padded(
          child: Text(
            l10n.printerLanguageLabel,
            style: theme.textTheme.bodyLarge,
          ),
        ),
        PrinterLanguageSelector(
          value: s.printerLanguage,
          onChanged: (language) =>
              _change((s) => s.withPrinterLanguage(language)),
        ),
      ],
      ListTile(
        key: const ValueKey('printer-diagnostics'),
        leading: const Icon(Icons.troubleshoot),
        title: Text(l10n.printerDiagnosticsTitle),
        subtitle: Text(l10n.printerDiagnosticsSubtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PrinterDiagnosticsScreen()),
        ),
      ),
      ListTile(
        title: Text(l10n.feedLinesLabel),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: s.feedLines <= 0
                  ? null
                  : () => _change(
                      (s) => s.copyWith(feedLines: s.feedLines - 1)),
            ),
            SizedBox(
              width: 28,
              child: Text(
                '${s.feedLines}',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: s.feedLines >= InvoiceSettings.maxFeedLines
                  ? null
                  : () => _change(
                      (s) => s.copyWith(feedLines: s.feedLines + 1)),
            ),
          ],
        ),
      ),
      SwitchListTile(
        title: Text(l10n.cutPaperLabel),
        // A label printer has no cutter command: TSPL jobs never cut.
        subtitle: Text(s.printerLanguage == PrinterLanguage.tspl
            ? l10n.cutPaperTsplHint
            : l10n.cutPaperHint),
        value: s.cutPaper && s.printerLanguage != PrinterLanguage.tspl,
        onChanged: s.printerLanguage == PrinterLanguage.tspl
            ? null
            : (value) => _change((s) => s.copyWith(cutPaper: value)),
      ),
    ];
  }

  List<Widget> _paperSection(
    AppLocalizations l10n,
    ThemeData theme,
    InvoiceSettings s,
  ) {
    final paperChoice = _customPaper
        ? 'custom'
        : (s.paperWidthMm == InvoiceSettings.paper58 ? '58' : '80');
    final dots = s.printableDots;
    return [
      _SectionTitle(l10n.sectionPaper),
      _Padded(
        child: SegmentedButton<String>(
          key: const ValueKey('paper-width'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: '80', label: Text(l10n.paperWidthPreset('80'))),
            ButtonSegment(value: '58', label: Text(l10n.paperWidthPreset('58'))),
            ButtonSegment(value: 'custom', label: Text(l10n.paperCustom)),
          ],
          selected: {paperChoice},
          onSelectionChanged: (selection) => _selectPaper(selection.first),
        ),
      ),
      if (_customPaper)
        _NumberField(
          key: const ValueKey('paper-custom-mm'),
          label: l10n.paperWidthMmLabel,
          initialText: _mmText(s.paperWidthMm),
          onChanged: (text) {
            final mm = _parseDecimal(text);
            if (mm == null || mm < 20 || mm > 300) return false;
            if (mm - 2 * _settings.sideMarginMm < 10) return false;
            _change((s) => s.copyWith(paperWidthMm: mm));
            return true;
          },
        ),
      _NumberField(
        key: ValueKey('side-margin-$_marginEpoch'),
        label: l10n.sideMarginLabel,
        initialText: _mmText(s.sideMarginMm),
        onChanged: (text) {
          final mm = _parseDecimal(text);
          if (mm == null || mm < 0) return false;
          if (_settings.paperWidthMm - 2 * mm < 10) return false;
          _change((s) => s.copyWith(sideMarginMm: mm));
          return true;
        },
      ),
      _NumberField(
        key: const ValueKey('printer-dpi'),
        label: l10n.printerDpiLabel,
        initialText: '${s.printerDpi}',
        integer: true,
        onChanged: (text) {
          final dpi = int.tryParse(normalizeDigits(text.trim()));
          if (dpi == null || dpi < 100 || dpi > 600) return false;
          _change((s) => s.copyWith(printerDpi: dpi));
          return true;
        },
      ),
      _Padded(
        child: Text(
          l10n.printableWidthInfo(
            '$dots',
            dotsToMm(dots, s.printerDpi).toStringAsFixed(1),
          ),
          key: const ValueKey('printable-width-info'),
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary),
        ),
      ),
      PrintWidthWarning(settings: s, onFix: _fitWidthToHead),
      ExpansionTile(
        title: Text(l10n.advancedSection),
        initiallyExpanded: s.printableDotsOverride != null,
        children: [
          KeyedSubtree(
            key: const ValueKey('dots-override'),
            child: _NumberField(
              // A new field (with the new text) when the width warning
              // changes the override: the field owns what is typed in it.
              key: ValueKey('dots-override-$_dotsEpoch'),
              label: l10n.printableDotsOverrideLabel,
              helper: l10n.printableDotsOverrideHint,
              initialText: s.printableDotsOverride == null
                  ? ''
                  : '${s.printableDotsOverride}',
              integer: true,
              onChanged: (text) {
                if (text.trim().isEmpty) {
                  _change(
                    (s) => s.copyWith(printableDotsOverride: () => null),
                  );
                  return true;
                }
                final value = int.tryParse(normalizeDigits(text.trim()));
                if (value == null ||
                    value < minPrintableDots ||
                    value > maxPrintableDots) {
                  return false;
                }
                _change(
                  (s) => s.copyWith(printableDotsOverride: () => value),
                );
                return true;
              },
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _shopSection(
    AppLocalizations l10n,
    ThemeData theme,
    InvoiceSettings s,
  ) {
    final logoPng = s.logoPng;
    final licensedName = ref.watch(licenseProvider).shopName;
    return [
      _SectionTitle(l10n.sectionShop),
      // THE SHOP NAME COMES FROM THE LICENSE once the phone is activated:
      // shown here, not editable. (The header text under it stays the
      // shop's own.) Before that — on the trial — it is typed here.
      if (licensedName != null)
        ListTile(
          key: const ValueKey('shop-name-licensed'),
          leading: const Icon(Icons.verified_outlined),
          title: Text(licensedName),
          subtitle: Text(
            '${l10n.shopNameLabel} · ${l10n.shopNameFromLicense}',
          ),
        )
      else
        _Padded(
          child: TextField(
            key: const ValueKey('shop-name'),
            controller: _shopName,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: l10n.shopNameLabel),
            onChanged: (text) => _change((s) => s.copyWith(shopName: text)),
          ),
        ),
      ListTile(
        leading: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
          ),
          child: logoPng == null
              ? Icon(Icons.image_outlined, color: theme.colorScheme.outline)
              : Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.memory(logoPng, fit: BoxFit.contain),
                ),
        ),
        title: Text(l10n.logoLabel),
        subtitle: Text(l10n.logoHint),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logoPng != null)
              IconButton(
                tooltip: l10n.removeLogo,
                icon: const Icon(Icons.delete_outline),
                onPressed: () =>
                    _change((s) => s.copyWith(logoPng: () => null)),
              ),
            IconButton(
              tooltip: l10n.pickLogo,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _pickLogo,
            ),
          ],
        ),
      ),
      _Padded(
        child: TextField(
          key: const ValueKey('header-text'),
          controller: _header,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: l10n.headerTextLabel,
            alignLabelWithHint: true,
          ),
          onChanged: (text) => _change((s) => s.copyWith(headerText: text)),
        ),
      ),
      _Padded(
        child: TextField(
          key: const ValueKey('footer-text'),
          controller: _footer,
          minLines: 2,
          maxLines: 5,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            labelText: l10n.footerTextLabel,
            alignLabelWithHint: true,
          ),
          onChanged: (text) => _change((s) => s.copyWith(footerText: text)),
        ),
      ),
    ];
  }

  List<Widget> _contentSection(AppLocalizations l10n, InvoiceSettings s) {
    Widget toggle(
      String title,
      bool value,
      InvoiceSettings Function(InvoiceSettings s, bool value) apply, {
      Key? key,
      bool indent = false,
    }) {
      return SwitchListTile(
        key: key,
        dense: true,
        contentPadding: EdgeInsetsDirectional.only(
          start: indent ? 32 : 16,
          end: 16,
        ),
        title: Text(title),
        value: value,
        onChanged: (v) => _change((s) => apply(s, v)),
      );
    }

    return [
      _SectionTitle(l10n.sectionContent),
      ListTile(
        title: Text(l10n.invoiceLanguageLabel),
        trailing: SegmentedButton<String>(
          key: const ValueKey('invoice-language'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: 'ar', label: Text(l10n.languageArabic)),
            ButtonSegment(value: 'en', label: Text(l10n.languageEnglish)),
          ],
          selected: {s.language},
          onSelectionChanged: (selection) =>
              _change((s) => s.copyWith(language: selection.first)),
        ),
      ),
      ListTile(
        title: Text('${l10n.baseFontSizeLabel}: ${s.baseFontSize}'),
        subtitle: Slider(
          value: s.baseFontSize.toDouble(),
          min: InvoiceSettings.minFontSize.toDouble(),
          max: InvoiceSettings.maxFontSize.toDouble(),
          divisions: InvoiceSettings.maxFontSize - InvoiceSettings.minFontSize,
          label: '${s.baseFontSize}',
          onChanged: (value) =>
              _change((s) => s.copyWith(baseFontSize: value.round())),
        ),
      ),
      toggle(l10n.showInvoiceNumberLabel, s.showInvoiceNumber,
          (s, v) => s.copyWith(showInvoiceNumber: v)),
      toggle(l10n.showDateTimeLabel, s.showDateTime,
          (s, v) => s.copyWith(showDateTime: v)),
      toggle(l10n.showItemCodeLabel, s.showItemCode,
          (s, v) => s.copyWith(showItemCode: v),
          key: const ValueKey('toggle-item-code')),
      toggle(l10n.showUnitLabel, s.showUnit, (s, v) => s.copyWith(showUnit: v)),
      toggle(l10n.showUnitPriceLabel, s.showUnitPrice,
          (s, v) => s.copyWith(showUnitPrice: v)),
      if (featureOn(Feature.customers)) ...[
        toggle(l10n.showCustomerNameLabel, s.showCustomerName,
            (s, v) => s.copyWith(showCustomerName: v)),
        toggle(l10n.showCustomerPhoneLabel, s.showCustomerPhone,
            (s, v) => s.copyWith(showCustomerPhone: v)),
      ],
      if (featureOn(Feature.accounts)) ...[
        toggle(l10n.showAccountNumberLabel, s.showAccountNumber,
            (s, v) => s.copyWith(showAccountNumber: v)),
        if (s.showAccountNumber)
          toggle(l10n.maskAccountLabel, s.maskAccountNumber,
              (s, v) => s.copyWith(maskAccountNumber: v),
              indent: true),
      ],
      toggle(l10n.showPoweredBy, s.showPoweredBy,
          (s, v) => s.copyWith(showPoweredBy: v)),
      // How sold prepaid card codes are printed.
      if (featureOn(Feature.vouchers)) ...[
        _SectionTitle(l10n.sectionCardCodes),
        toggle(l10n.printCodeQrLabel, s.printCodeQr,
            (s, v) => s.copyWith(printCodeQr: v),
            key: const ValueKey('toggle-code-qr')),
        toggle(l10n.codesSeparateSlipsLabel, s.codesOnSeparateSlips,
            (s, v) => s.copyWith(codesOnSeparateSlips: v),
            key: const ValueKey('toggle-code-slips')),
        _Hint(l10n.codesSeparateSlipsHint),
      ],
      // What the invoice says about a sale on credit.
      if (featureOn(Feature.debt)) ...[
        _SectionTitle(l10n.debtLinesSection),
        toggle(l10n.showPaidAmount, s.showPaidAmount,
            (s, v) => s.copyWith(showPaidAmount: v),
            key: const ValueKey('toggle-paid-amount')),
        toggle(l10n.showRemainingAmount, s.showRemainingAmount,
            (s, v) => s.copyWith(showRemainingAmount: v),
            key: const ValueKey('toggle-remaining-amount')),
        toggle(l10n.showPreviousBalance, s.showPreviousBalance,
            (s, v) => s.copyWith(showPreviousBalance: v),
            key: const ValueKey('toggle-previous-balance')),
        toggle(l10n.showNewBalance, s.showNewBalance,
            (s, v) => s.copyWith(showNewBalance: v),
            key: const ValueKey('toggle-new-balance')),
        _Hint(l10n.debtLinesHint),
      ],
    ];
  }

  List<Widget> _currencySection(
    AppLocalizations l10n,
    ThemeData theme,
    InvoiceSettings s,
    List<Currency>? currencies,
    String? baseCode,
    String appLocale,
  ) {
    // Only currencies that can actually be converted: the base currency and
    // every active currency whose rate has been entered.
    final candidates = <Currency>[
      for (final c in currencies ?? const <Currency>[])
        if (c.isActive && (c.code == baseCode || c.rateUpdatedAt != null)) c,
    ];
    final selected = s.extraCurrencies;
    return [
      _SectionTitle(l10n.sectionCurrency),
      ListTile(
        title: Text(l10n.currencyDisplayLabel),
        trailing: SegmentedButton<CurrencyDisplay>(
          key: const ValueKey('currency-display'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: CurrencyDisplay.symbol,
              label: Text(l10n.currencyDisplaySymbol),
            ),
            ButtonSegment(
              value: CurrencyDisplay.code,
              label: Text(l10n.currencyDisplayCode),
            ),
          ],
          selected: {s.currencyDisplay},
          onSelectionChanged: (selection) =>
              _change((s) => s.copyWith(currencyDisplay: selection.first)),
        ),
      ),
      // The total in other currencies: only with more than one currency.
      if (featureOn(Feature.multiCurrency)) ...[
        _Padded(
          child: Text(l10n.extraCurrenciesLabel, style: theme.textTheme.bodyLarge),
        ),
        _Padded(
          child: candidates.length < 2
              ? Text(
                  l10n.extraCurrenciesNone,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                )
              : Wrap(
                  spacing: 8,
                  children: [
                    for (final currency in candidates)
                      FilterChip(
                        key: ValueKey('extra-currency-${currency.code}'),
                        label: Text('${currency.code} · '
                            '${currency.nameFor(appLocale)}'),
                        selected: selected.contains(currency.code),
                        // A third currency cannot be added: two at most.
                        onSelected: !selected.contains(currency.code) &&
                                selected.length >= 2
                            ? null
                            : (on) => _change((s) => s.copyWith(
                                  extraCurrencies: on
                                      ? [...s.extraCurrencies, currency.code]
                                      : [
                                          for (final code in s.extraCurrencies)
                                            if (code != currency.code) code,
                                        ],
                                )),
                      ),
                  ],
                ),
        ),
        _Hint(l10n.extraCurrenciesHint),
      ],
    ];
  }

  List<Widget> _sharingSection(AppLocalizations l10n, InvoiceSettings s) {
    return [
      _SectionTitle(l10n.sectionSharing),
      SwitchListTile(
        title: Text(l10n.shareWidthLabel),
        subtitle: Text(l10n.shareWidthSameAsPaper),
        value: s.shareWidthMm == null,
        onChanged: (sameAsPaper) => _change((s) => s.copyWith(
              shareWidthMm: () => sameAsPaper ? null : s.paperWidthMm,
            )),
      ),
      if (s.shareWidthMm != null)
        _NumberField(
          key: const ValueKey('share-width-mm'),
          label: l10n.shareWidthMmLabel,
          initialText: _mmText(s.shareWidthMm!),
          onChanged: (text) {
            final mm = _parseDecimal(text);
            if (mm == null || mm < 20 || mm > 300) return false;
            if (mm - 2 * _settings.sideMarginMm < 10) return false;
            _change((s) => s.copyWith(shareWidthMm: () => mm));
            return true;
          },
        ),
      _NumberField(
        key: const ValueKey('country-code'),
        label: l10n.defaultCountryCodeLabel,
        helper: l10n.defaultCountryCodeHint(s.defaultCountryCode),
        initialText: s.defaultCountryCode,
        integer: true,
        prefixText: '+',
        onChanged: (text) {
          final code = normalizePhone(text);
          if (code.isEmpty || code.length > 4 || code.startsWith('0')) {
            return false;
          }
          _change((s) => s.copyWith(defaultCountryCode: code));
          return true;
        },
      ),
    ];
  }
}

typedef _SectionTitle = SettingsSectionTitle;
typedef _Padded = SettingsPadded;
typedef _Hint = SettingsHint;

/// A numeric text field that owns its text. [onChanged] applies the value
/// when it is valid and returns whether it was; an invalid entry shows an
/// error and leaves the stored setting untouched.
class _NumberField extends StatefulWidget {
  const _NumberField({
    super.key,
    required this.label,
    required this.initialText,
    required this.onChanged,
    this.helper,
    this.prefixText,
    this.integer = false,
  });

  final String label;
  final String initialText;
  final bool Function(String text) onChanged;
  final String? helper;
  final String? prefixText;
  final bool integer;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final _controller = TextEditingController(text: widget.initialText);
  bool _invalid = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // Gaining focus selects the whole number: the first keystroke
      // replaces the setting's current value instead of appending to it.
      child: SelectAllOnFocus(
        controller: _controller,
        child: _field(l10n),
      ),
    );
  }

  Widget _field(AppLocalizations l10n) {
    return TextField(
      controller: _controller,
      keyboardType: TextInputType.numberWithOptions(decimal: !widget.integer),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(widget.integer ? r'[0-9٠-٩۰-۹]' : r'[0-9٠-٩۰-۹.,٫]'),
        ),
      ],
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        helperMaxLines: 3,
        prefixText: widget.prefixText,
        errorText: _invalid ? l10n.invalidNumber : null,
      ),
      onChanged: (text) {
        final valid = widget.onChanged(text);
        if (valid == _invalid) setState(() => _invalid = !valid);
      },
    );
  }
}
