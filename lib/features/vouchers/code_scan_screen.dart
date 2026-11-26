import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/money/money_format.dart';
import '../../core/providers.dart';
import '../../core/utils/normalize.dart';
import '../../core/utils/voucher_format.dart';
import '../../l10n/generated/app_localizations.dart';
import '../invoice/invoice_providers.dart';

/// What became of one scanned value.
enum ScanOutcome { added, duplicate, ignored }

/// The cards scanned so far, each once.
///
/// Pure: no camera here, so the "same card twice" rule is unit-tested. Two
/// scans are the same card when their codes are equal after [normalizeCode],
/// exactly as in a pasted list.
class ScanCollector {
  ScanCollector([Iterable<String> initial = const []]) {
    for (final code in initial) {
      add(code);
    }
  }

  final List<String> _codes = [];
  final Set<String> _seen = {};

  /// In scan order.
  List<String> get codes => List.unmodifiable(_codes);

  int get count => _codes.length;

  /// The last card added, masked — the only form shown on screen.
  String? get lastMasked => _codes.isEmpty ? null : maskCode(_codes.last);

  ScanOutcome add(String? raw) {
    final code = raw?.trim() ?? '';
    final normalized = normalizeCode(code);
    if (normalized.isEmpty) return ScanOutcome.ignored;
    if (!_seen.add(normalized)) return ScanOutcome.duplicate;
    _codes.add(code);
    return ScanOutcome.added;
  }
}

/// Scans cards one by one with the camera — the QR code or barcode printed
/// on each card. Every new card gets a beep, a vibration and a running
/// count; a card scanned twice is counted once.
///
/// Pops the list of scanned codes (also on the back button, so a batch of
/// scans is never thrown away by a slip of the thumb). The codes go straight
/// back to the "load codes" page, which shows only their masked preview.
class CodeScanScreen extends ConsumerStatefulWidget {
  const CodeScanScreen({super.key, this.initial = const []}) : single = false;

  /// ONE product barcode (the product form, the sale screen): the first
  /// value read pops it as a String. See [scanOneBarcode].
  const CodeScanScreen.single({super.key})
      : initial = const [],
        single = true;

  /// Cards scanned in an earlier visit to this screen.
  final List<String> initial;

  final bool single;

  @override
  ConsumerState<CodeScanScreen> createState() => _CodeScanScreenState();
}

/// Opens the camera for one barcode; null when the seller backs out.
Future<String?> scanOneBarcode(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<String>(builder: (_) => const CodeScanScreen.single()),
    );

class _CodeScanScreenState extends ConsumerState<CodeScanScreen> {
  late final ScanCollector _collector = ScanCollector(widget.initial);
  final MobileScannerController _controller = MobileScannerController(
    // One report per card held in front of the camera, not thirty a second.
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _lastWasDuplicate = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (!mounted) return;
    if (widget.single) {
      if (_done) return;
      for (final barcode in capture.barcodes) {
        final value = barcode.rawValue?.trim() ?? '';
        if (normalizeCode(value).isEmpty) continue;
        _done = true;
        ref.read(nativeBridgeProvider).beep();
        HapticFeedback.mediumImpact();
        Navigator.of(context).pop(value);
        return;
      }
      return;
    }
    var added = false;
    var duplicate = false;
    for (final barcode in capture.barcodes) {
      switch (_collector.add(barcode.rawValue)) {
        case ScanOutcome.added:
          added = true;
        case ScanOutcome.duplicate:
          duplicate = true;
        case ScanOutcome.ignored:
          break;
      }
    }
    if (!added && !duplicate) return;
    if (added) {
      ref.read(nativeBridgeProvider).beep();
      HapticFeedback.mediumImpact();
    } else {
      // Felt, not heard: the beep means "one more card".
      HapticFeedback.heavyImpact();
    }
    setState(() => _lastWasDuplicate = !added);
  }

  void _finish() => Navigator.of(context).pop(_collector.codes);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = ref.watch(appLocaleProvider).languageCode;
    final theme = Theme.of(context);
    final last = _collector.lastMasked;

    if (widget.single) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.scanBarcodeTitle)),
        body: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.scanCameraError,
                      key: const ValueKey('scan-error'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            Material(
              elevation: 8,
              color: theme.colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.scanBarcodeHint,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        key: const ValueKey('scan-cancel'),
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancel),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return PopScope<List<String>>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.scanTitle)),
        body: Column(
          children: [
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      l10n.scanCameraError,
                      key: const ValueKey('scan-error'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            Material(
              elevation: 8,
              color: theme.colorScheme.surface,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.scanCount(formatMinor(
                          _collector.count,
                          decimals: 0,
                          locale: locale,
                        )),
                        key: const ValueKey('scan-count'),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _lastWasDuplicate
                            ? l10n.scanDuplicate
                            : last ?? l10n.scanHint,
                        textAlign: TextAlign.center,
                        textDirection: _lastWasDuplicate || last == null
                            ? null
                            : TextDirection.ltr,
                        style: TextStyle(
                          color: _lastWasDuplicate
                              ? theme.colorScheme.error
                              : theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const ValueKey('scan-done'),
                        onPressed: _finish,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(l10n.done),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
