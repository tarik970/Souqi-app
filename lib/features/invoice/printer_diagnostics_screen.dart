import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/platform/native_bridge.dart';
import '../../core/printing/calibration_pattern.dart';
import '../../core/printing/escpos.dart';
import '../../core/printing/print_geometry.dart';
import '../../core/printing/print_job.dart';
import '../../core/printing/printer_detect.dart';
import '../../core/utils/bidi.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_output.dart';
import 'invoice_providers.dart';
import 'output_messages.dart';
import 'printer_picker.dart';
import 'printer_widgets.dart';

/// Finds the settings a stubborn printer needs, by trying them on paper.
///
/// A printer that connects but prints nothing (or garbage) is almost always
/// one of three things: it speaks the other LANGUAGE (a dual label/receipt
/// printer left in label mode ignores ESC/POS), it does not know the IMAGE
/// command that was used, or it cannot take the bytes as fast as they come.
/// Each has a short test here; the user says whether it printed, and the
/// one that did becomes the setting.
///
/// The first of those the app answers BY ITSELF where it can ("Detect the
/// printer's language": by the printer's name, or by asking it).
///
/// And a printer that prints, but with one side cut off, is CALIBRATED
/// here — under "Advanced", because the defaults and the built-in profiles
/// are meant to fit without it: a ruler is printed across the printable
/// width, and the print is moved or narrowed step by step until both of
/// its ends are on the paper.
class PrinterDiagnosticsScreen extends ConsumerStatefulWidget {
  const PrinterDiagnosticsScreen({super.key});

  @override
  ConsumerState<PrinterDiagnosticsScreen> createState() =>
      _PrinterDiagnosticsScreenState();
}

/// One test of the screen: a language, or an ESC/POS image mode.
enum _Test {
  receipt,
  label,
  gsV0(EscPosImageMode.gsV0),
  escStar(EscPosImageMode.escStar),
  gsL(EscPosImageMode.gsL);

  const _Test([this.imageMode]);

  /// Set for the three image-mode tests.
  final EscPosImageMode? imageMode;
}

/// What the user said about a test that was sent.
enum _Answer { asking, printed, notPrinted }

class _PrinterDiagnosticsScreenState
    extends ConsumerState<PrinterDiagnosticsScreen> {
  _Test? _running;
  bool _calibrating = false;
  bool _detecting = false;

  /// What the last "detect" found, shown under its button.
  PrinterDetection? _detected;
  final _answers = <_Test, _Answer>{};

  /// One thing on the Bluetooth link at a time: a test, a calibration slip
  /// or the language question.
  bool get _busy => _running != null || _calibrating || _detecting;

  void _change(InvoiceSettings Function(InvoiceSettings s) update) {
    ref.read(invoiceSettingsProvider.notifier).change(update);
  }

  /// The bytes of [test] are built for what it tests, whatever is stored.
  PrintFormat _formatOf(_Test test, InvoiceSettings s) => switch (test) {
        _Test.receipt => s.printFormatFor(PrinterLanguage.escPos),
        _Test.label => s.printFormatFor(PrinterLanguage.tspl),
        _ => s
            .printFormatFor(PrinterLanguage.escPos)
            .copyWith(imageMode: test.imageMode),
      };

  /// Printed on the slip, so slips of different tests can be told apart.
  String _slipLabel(_Test test, InvoiceSettings s) => switch (test) {
        _Test.receipt => 'ESC/POS · ${s.escPosImageMode.label}',
        _Test.label => 'TSPL',
        _ => 'ESC/POS · ${test.imageMode!.label}',
      };

  String _buttonLabel(AppLocalizations l10n, _Test test) => switch (test) {
        _Test.receipt => l10n.testReceiptMode,
        _Test.label => l10n.testLabelMode,
        _ => l10n.testImageMode(imageModeCommand(test.imageMode!)),
      };

  /// Whether what [test] tests is what invoices are printed with now.
  bool _inUse(_Test test, InvoiceSettings s) => switch (test) {
        _Test.receipt => s.printerLanguage == PrinterLanguage.escPos,
        _Test.label => s.printerLanguage == PrinterLanguage.tspl,
        _ => s.printerLanguage == PrinterLanguage.escPos &&
            s.escPosImageMode == test.imageMode,
      };

  /// "Printed — use this": what [test] tested becomes the setting. An image
  /// mode that printed also settles the language — it is ESC/POS.
  void _use(_Test test) {
    setState(() => _answers[test] = _Answer.printed);
    _change((s) => switch (test) {
          _Test.receipt => s.withPrinterLanguage(PrinterLanguage.escPos),
          _Test.label => s.withPrinterLanguage(PrinterLanguage.tspl),
          _ => s
              .copyWith(escPosImageMode: test.imageMode)
              .withPrinterLanguage(PrinterLanguage.escPos),
        });
  }

  Future<void> _run(_Test test) async {
    if (_busy) return;
    final settings = ref.read(invoiceSettingsProvider).value;
    if (settings == null) return;
    // `ref` is only read before the first await.
    final output = ref.read(invoiceOutputProvider);
    setState(() {
      _running = test;
      _answers.remove(test);
    });
    final sent = await _guarded(
      () => output.printTest(
        format: _formatOf(test, settings),
        label: _slipLabel(test, settings),
      ),
    );
    if (!mounted) return;
    setState(() {
      _running = null;
      if (sent) _answers[test] = _Answer.asking;
    });
  }

  /// Finds out the chosen printer's language again — by its name, or by
  /// asking it — and makes what was found the setting (for a printer the
  /// app knows by name: its whole profile, width and position included).
  Future<void> _detect() async {
    if (_busy) return;
    final settings = ref.read(invoiceSettingsProvider).value;
    final address = settings?.printerAddress;
    if (settings == null || address == null || address.isEmpty) return;
    // `ref` is only read before the first await.
    final output = ref.read(invoiceOutputProvider);
    final notifier = ref.read(invoiceSettingsProvider.notifier);
    setState(() {
      _detecting = true;
      _detected = null;
    });
    PrinterDetection? found;
    await _guarded(() async {
      await output.ensureBluetoothReady();
      found = await output.detectPrinter(
        address: address,
        name: settings.printerName,
      );
    });
    final detection = found;
    if (detection != null) {
      await notifier.change((s) => s.withDetection(detection, address: address));
    }
    if (!mounted) return;
    setState(() {
      _detecting = false;
      _detected = detection;
    });
  }

  /// Prints the calibration ruler — after applying [step] first, when the
  /// print is being moved or resized: one tap changes the setting and shows
  /// the result on paper.
  Future<void> _calibrate([
    InvoiceSettings Function(InvoiceSettings s)? step,
  ]) async {
    if (_busy) return;
    final current = ref.read(invoiceSettingsProvider).value;
    if (current == null) return;
    // `ref` is only read before the first await.
    final output = ref.read(invoiceOutputProvider);
    final next = step == null ? current : step(current);
    if (step != null) ref.read(invoiceSettingsProvider.notifier).set(next);
    setState(() => _calibrating = true);
    // Printed with the settings just made, not with whatever a provider has
    // caught up to.
    await _guarded(() => output.printCalibration(next));
    if (mounted) setState(() => _calibrating = false);
  }

  /// Runs a print and shows why it failed, if it did. True when it was sent.
  Future<bool> _guarded(Future<void> Function() print) async {
    try {
      await print();
      return true;
    } on OutputException catch (e) {
      if (mounted) showOutputError(context, ref, e, offerInvoiceSettings: false);
    } catch (e) {
      if (mounted) {
        showOutputError(
          context,
          ref,
          OutputException(OutputFailure.unknown, '$e'),
          offerInvoiceSettings: false,
        );
      }
    }
    return false;
  }

  Widget _test(_Test test, InvoiceSettings s) {
    final l10n = AppLocalizations.of(context);
    return _TestTile(
      key: ValueKey('diag-test-${test.name}'),
      label: _buttonLabel(l10n, test),
      running: _running == test,
      enabled: !_busy,
      answer: _answers[test],
      inUse: _inUse(test, s),
      onTest: () => _run(test),
      onPrinted: () => _use(test),
      onNotPrinted: () =>
          setState(() => _answers[test] = _Answer.notPrinted),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final s = ref.watch(invoiceSettingsProvider).value;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.printerDiagnosticsTitle)),
      body: s == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                ListTile(
                  leading:
                      Icon(s.hasPrinter ? Icons.print : Icons.print_disabled),
                  title: Text(s.hasPrinter
                      ? (s.printerName ?? s.printerAddress!)
                      : l10n.printerNone),
                  subtitle: s.hasPrinter
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(printerLanguageName(l10n, s.printerLanguage)),
                            Text(printerCalibrationText(l10n, s)),
                          ],
                        )
                      : null,
                  trailing: TextButton(
                    onPressed: () => chooseAndRememberPrinter(context, ref),
                    child: Text(l10n.choosePrinter),
                  ),
                ),
                PrintWidthWarning(
                  settings: s,
                  onFix: () => _change((s) => s.fittedToHead()),
                ),

                // ---- Language ----
                _Title(l10n.diagLanguageSection),
                _Note(l10n.diagLanguageIntro),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: FilledButton.icon(
                    key: const ValueKey('diag-detect'),
                    onPressed: _busy || !s.hasPrinter ? null : _detect,
                    icon: _detecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_fix_high),
                    label: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        l10n.printerDetectButton,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                if (_detected != null)
                  _Note(
                    printerDetectionText(l10n, _detected!),
                    key: const ValueKey('diag-detect-result'),
                    strong: true,
                  ),
                _test(_Test.receipt, s),
                _test(_Test.label, s),
                _Note(l10n.diagLanguageHint, strong: true),

                // ---- ESC/POS image mode ----
                _Title(l10n.diagImageModeSection),
                _Note(l10n.diagImageModeHint),
                for (final mode in EscPosImageMode.values)
                  ListTile(
                    key: ValueKey('diag-image-mode-${mode.name}'),
                    dense: true,
                    selected: mode == s.escPosImageMode,
                    leading: Icon(
                      mode == s.escPosImageMode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: mode == s.escPosImageMode
                          ? theme.colorScheme.primary
                          : null,
                    ),
                    title: Text(imageModeName(l10n, mode)),
                    onTap: () =>
                        _change((s) => s.copyWith(escPosImageMode: mode)),
                  ),
                _test(_Test.gsV0, s),
                _test(_Test.escStar, s),
                _test(_Test.gsL, s),

                // ---- Pacing ----
                _Title(l10n.diagCompatSection),
                _Choice(
                  key: const ValueKey('diag-chunk-size'),
                  label: l10n.diagChunkSizeLabel,
                  values: InvoiceSettings.chunkSizes,
                  selected: s.printChunkSize,
                  onSelected: (size) =>
                      _change((s) => s.copyWith(printChunkSize: size)),
                ),
                _Choice(
                  key: const ValueKey('diag-chunk-delay'),
                  label: l10n.diagChunkDelayLabel,
                  values: InvoiceSettings.chunkDelaysMs,
                  selected: s.printChunkDelayMs,
                  onSelected: (delay) =>
                      _change((s) => s.copyWith(printChunkDelayMs: delay)),
                ),
                _Note(l10n.diagCompatHint),

                // ---- Advanced: calibration and the rare switches ----
                ExpansionTile(
                  key: const ValueKey('diag-advanced'),
                  title: Text(l10n.advancedSection),
                  subtitle: Text(l10n.diagAdvancedSubtitle),
                  // Open for a printer that has been calibrated: what was
                  // set stays in sight.
                  initiallyExpanded: s.tsplOneIsBlack ||
                      s.printerOffsetDots != 0 ||
                      s.printableDotsOverride != null,
                  expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ---- Calibration ----
                    // A printer that prints with one side cut off. Out of the
                    // way: the defaults and the built-in profiles fit, and a
                    // shop should not have to come here.
                    _Title(l10n.diagCalibrationSection),
                    _Note(l10n.diagCalibrationHint),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: FilledButton.tonalIcon(
                        key: const ValueKey('diag-calibration-test'),
                        onPressed: _busy ? null : _calibrate,
                        icon: _calibrating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.straighten),
                        label: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            l10n.calibrationTest,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                    _Stepper(
                      key: const ValueKey('diag-offset'),
                      label: l10n.horizontalOffsetValue(
                        ltrIsolate(formatOffsetDots(s.printerOffsetDots)),
                      ),
                      lessIcon: Icons.arrow_back,
                      moreIcon: Icons.arrow_forward,
                      lessTooltip: l10n.calibrationShiftLeft,
                      moreTooltip: l10n.calibrationShiftRight,
                      // The offset belongs to a printer: none, nothing to move.
                      onLess: _busy ||
                              !s.hasPrinter ||
                              s.printerOffsetDots <= -maxOffsetDots
                          ? null
                          : () => _calibrate(
                                (s) => s.withPrinterOffset(
                                  s.printerOffsetDots - offsetStepDots,
                                ),
                              ),
                      onMore: _busy ||
                              !s.hasPrinter ||
                              s.printerOffsetDots >= maxOffsetDots
                          ? null
                          : () => _calibrate(
                                (s) => s.withPrinterOffset(
                                  s.printerOffsetDots + offsetStepDots,
                                ),
                              ),
                    ),
                    _Stepper(
                      key: const ValueKey('diag-width'),
                      label: l10n.printableWidthValue('${s.printableDots}'),
                      lessIcon: Icons.remove,
                      moreIcon: Icons.add,
                      lessTooltip: l10n.calibrationNarrower,
                      moreTooltip: l10n.calibrationWider,
                      onLess: _busy || s.printableDots <= minPrintableDots
                          ? null
                          : () => _calibrate(
                                (s) => s.copyWith(
                                  printableDotsOverride: () =>
                                      snapDots(s.printableDots - 8),
                                ),
                              ),
                      onMore: _busy || s.printableDots >= maxPrintableDots
                          ? null
                          : () => _calibrate(
                                (s) => s.copyWith(
                                  printableDotsOverride: () =>
                                      snapDots(s.printableDots + 8),
                                ),
                              ),
                    ),
                    if (s.printerLanguage == PrinterLanguage.escPos)
                      _Note(l10n.calibrationReceiptNote),

                    SwitchListTile(
                      key: const ValueKey('diag-tspl-one-is-black'),
                      title: Text(l10n.tsplOneIsBlackLabel),
                      subtitle: Text(l10n.tsplOneIsBlackHint),
                      value: s.tsplOneIsBlack,
                      onChanged: (on) =>
                          _change((s) => s.copyWith(tsplOneIsBlack: on)),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {super.key, this.strong = false});

  final String text;

  /// The advice to act on, not a description: full contrast.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Text(
        text,
        style: strong
            ? theme.textTheme.bodyMedium
            : theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}

/// A test button, and under it — once the test was sent — the question
/// whether it printed, or the answer that was given.
class _TestTile extends StatelessWidget {
  const _TestTile({
    super.key,
    required this.label,
    required this.running,
    required this.enabled,
    required this.answer,
    required this.inUse,
    required this.onTest,
    required this.onPrinted,
    required this.onNotPrinted,
  });

  final String label;
  final bool running;
  final bool enabled;
  final _Answer? answer;
  final bool inUse;
  final VoidCallback onTest;
  final VoidCallback onPrinted;
  final VoidCallback onNotPrinted;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final answer = this.answer;

    Widget verdict(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(color: color),
                ),
              ),
            ],
          ),
        );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.tonalIcon(
            onPressed: enabled ? onTest : null,
            icon: running
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.receipt_long),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
          if (answer == _Answer.asking) ...[
            const SizedBox(height: 6),
            Text(l10n.diagDidItPrint, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilledButton(
                  onPressed: onPrinted,
                  child: Text(l10n.diagPrintedUseThis),
                ),
                OutlinedButton(
                  onPressed: onNotPrinted,
                  child: Text(l10n.diagDidNotPrint),
                ),
              ],
            ),
          ] else if (answer == _Answer.printed)
            verdict(
              Icons.check_circle,
              theme.colorScheme.primary,
              inUse ? l10n.diagWorksInUse : l10n.diagWorks,
            )
          else if (answer == _Answer.notPrinted)
            verdict(
              Icons.cancel_outlined,
              theme.colorScheme.error,
              l10n.diagNotPrinted,
            ),
        ],
      ),
    );
  }
}

/// A value with a pair of buttons that step it down or up. The pair is
/// always laid out left to right — "move left" is the LEFT button in Arabic
/// too, and its arrow is not mirrored.
class _Stepper extends StatelessWidget {
  const _Stepper({
    super.key,
    required this.label,
    required this.lessIcon,
    required this.moreIcon,
    required this.lessTooltip,
    required this.moreTooltip,
    required this.onLess,
    required this.onMore,
  });

  final String label;
  final IconData lessIcon;
  final IconData moreIcon;
  final String lessTooltip;
  final String moreTooltip;
  final VoidCallback? onLess;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
          const SizedBox(width: 8),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  tooltip: lessTooltip,
                  onPressed: onLess,
                  icon: Icon(lessIcon),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: moreTooltip,
                  onPressed: onMore,
                  icon: Icon(moreIcon),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A label over a row of numbers to pick one from (chunk size, delay).
class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<int> values;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: [
              for (final value in values)
                ButtonSegment(value: value, label: Text('$value')),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => onSelected(selection.first),
          ),
        ],
      ),
    );
  }
}
