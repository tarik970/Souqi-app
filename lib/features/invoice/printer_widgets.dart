import 'package:material_ui/material_ui.dart';

import '../../core/printing/calibration_pattern.dart';
import '../../core/printing/escpos.dart';
import '../../core/printing/print_job.dart';
import '../../core/utils/bidi.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';

String printerLanguageName(AppLocalizations l10n, PrinterLanguage language) =>
    switch (language) {
      PrinterLanguage.escPos => l10n.printerLanguageReceipt,
      PrinterLanguage.tspl => l10n.printerLanguageTspl,
    };

String _printerLanguageHint(AppLocalizations l10n, PrinterLanguage language) =>
    switch (language) {
      PrinterLanguage.escPos => l10n.printerLanguageReceiptHint,
      PrinterLanguage.tspl => l10n.printerLanguageTsplHint,
    };

/// "Width 576 dots · offset +16" — where the chosen printer's print sits,
/// shown under the printer.
String printerCalibrationText(AppLocalizations l10n, InvoiceSettings s) =>
    l10n.printerCalibrationInfo(
      '${s.printableDots}',
      ltrIsolate(formatOffsetDots(s.printerOffsetDots)),
    );

/// The command of [mode] ("ESC *") kept in one left-to-right piece, so its
/// punctuation does not wander inside an Arabic sentence.
String imageModeCommand(EscPosImageMode mode) => ltrIsolate(mode.label);

/// An ESC/POS image mode as the diagnostics screen names it: the command
/// itself, with what sets it apart.
String imageModeName(AppLocalizations l10n, EscPosImageMode mode) =>
    switch (mode) {
      EscPosImageMode.gsV0 => l10n.imageModeDefault(imageModeCommand(mode)),
      EscPosImageMode.escStar =>
        l10n.imageModeEscStar(imageModeCommand(mode)),
      EscPosImageMode.gsL => imageModeCommand(mode),
    };

/// Receipt (ESC/POS) or Label (TSPL), each with one line saying which
/// printers it is for. Two rows instead of a segmented button: the names do
/// not fit side by side in a dialog.
class PrinterLanguageSelector extends StatelessWidget {
  const PrinterLanguageSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.contentPadding,
  });

  final PrinterLanguage value;
  final ValueChanged<PrinterLanguage> onChanged;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final language in PrinterLanguage.values)
          ListTile(
            key: ValueKey('printer-language-${language.name}'),
            dense: true,
            contentPadding: contentPadding,
            selected: language == value,
            leading: Icon(
              language == value
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: language == value ? theme.colorScheme.primary : null,
            ),
            title: Text(printerLanguageName(l10n, language)),
            subtitle: Text(_printerLanguageHint(l10n, language)),
            onTap: () => onChanged(language),
          ),
      ],
    );
  }
}

/// Shown while the image is wider than the print head: says so in plain
/// words and offers the width that fits (576 dots for 80 mm paper, 384 for
/// 58 mm). Takes no space when the width is fine.
class PrintWidthWarning extends StatelessWidget {
  const PrintWidthWarning({
    super.key,
    required this.settings,
    required this.onFix,
  });

  final InvoiceSettings settings;

  /// Apply [InvoiceSettings.fittedToHead].
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    if (!s.widerThanHead) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final paper = s.paperWidthMm == s.paperWidthMm.roundToDouble()
        ? s.paperWidthMm.toStringAsFixed(0)
        : '${s.paperWidthMm}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: DecoratedBox(
        key: const ValueKey('print-width-warning'),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.widthTooWideWarning(
                        '${s.printableDots}',
                        paper,
                        '${s.headDots}',
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: FilledButton(
                  key: const ValueKey('print-width-fix'),
                  onPressed: onFix,
                  child: Text(l10n.widthUseHead('${s.headDots}')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
