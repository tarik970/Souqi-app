import 'package:flutter/widgets.dart';
import 'package:qr/qr.dart';

import '../../config/features.dart';
import '../../core/printing/print_geometry.dart';
import '../../core/printing/qr_bitmap.dart';
import '../../domain/models/invoice.dart';
import '../../domain/models/invoice_extras.dart';
import '../../domain/models/invoice_settings.dart';
import '../../l10n/generated/app_localizations.dart';
import 'invoice_text.dart';

const _ink = Color(0xFF000000);
const _paper = Color(0xFFFFFFFF);

// ---- Which papers print it ----------------------------------------------

/// "Only when something is left to pay" means something only with the debt
/// ledger: without it every sale is paid in full, so the code would never
/// print — the setting is hidden then and the code prints everywhere.
bool _unpaidOnly(InvoiceSettings s) =>
    s.paymentQrWhen == PaymentQrWhen.unpaidOnly && featureOn(Feature.debt);

/// The payment QR goes on [invoice]: it is switched on and set, the invoice
/// still counts (a voided invoice asks nobody to pay), and — with "only
/// when something is left to pay" — the sale left a remainder on credit.
bool paymentQrOnInvoice(InvoiceSettings s, Invoice invoice) {
  if (!s.hasPaymentQr || invoice.isVoided) return false;
  return !_unpaidOnly(s) || invoice.remainingMinor > 0;
}

/// The same for a payment receipt: its own switch, and with "only when
/// something is left to pay" a balance still owed after the payment. A
/// reversed (cancelled) receipt never carries it.
bool paymentQrOnReceipt(
  InvoiceSettings s, {
  required int? balanceAfterBaseMinor,
  bool reversed = false,
}) {
  if (!featureOn(Feature.debt) || !s.hasPaymentQr || !s.paymentQrOnReceipts) {
    return false;
  }
  if (reversed) return false;
  return !_unpaidOnly(s) || (balanceAfterBaseMinor ?? 0) > 0;
}

/// The same for an account statement: its own switch (on by default), and
/// with "only when something is left to pay" a closing balance owed.
bool paymentQrOnStatement(
  InvoiceSettings s, {
  required int closingBalanceBaseMinor,
}) {
  if (!featureOn(Feature.debt) ||
      !s.hasPaymentQr ||
      !s.paymentQrOnStatements) {
    return false;
  }
  return !_unpaidOnly(s) || closingBalanceBaseMinor > 0;
}

// ---- Size -----------------------------------------------------------------

/// White modules around the code: what the QR standard asks of a scanner.
const int paymentQrQuietModules = 4;

/// Error correction of the redrawn code. M (15 %) keeps the modules large
/// for a given text; a thermal print of a clean code does not need more.
const int paymentQrErrorLevel = QrErrorCorrectLevel.M;

/// Below this many dots per module a 203 dpi head prints a code that most
/// phones will not read: the settings warn about it.
const int paymentQrMinReadableModuleDots = 3;

/// The width of the code itself on the paper (quiet zone not included):
/// about 38 mm on an 80 mm roll, about 30 mm on 58 mm.
double paymentQrTargetMm(double paperWidthMm) => paperWidthMm < 70 ? 30 : 38;

int paymentQrTargetDots(InvoiceSettings s) =>
    mmToDots(paymentQrTargetMm(s.paperWidthMm), s.printerDpi).round();

final _matrices = <String, QrImage?>{};

/// The modules of [text] as a QR code, or null when it is too long for one.
/// Kept for the last few texts: the live preview rebuilds on every
/// keystroke elsewhere in the settings.
QrImage? paymentQrMatrix(String text) {
  if (text.isEmpty) return null;
  if (_matrices.containsKey(text)) return _matrices[text];
  QrImage? image;
  try {
    image = QrImage(
      QrCode.fromData(data: text, errorCorrectLevel: paymentQrErrorLevel),
    );
  } on Exception {
    image = null;
  }
  if (_matrices.length >= 4) _matrices.remove(_matrices.keys.first);
  return _matrices[text] = image;
}

/// Whole dots per module: the whole number that comes closest to the
/// target width (rounding down instead would print a dense code up to a
/// fifth smaller than asked), at least one, and never so many that the code
/// with its quiet zone is wider than [maxWidth].
int paymentQrModuleDots({
  required int modules,
  required int targetDots,
  required double maxWidth,
}) {
  var dot = (targetDots / modules).round();
  if (dot < 1) dot = 1;
  while (dot > 1 && (modules + 2 * paymentQrQuietModules) * dot > maxWidth) {
    dot--;
  }
  return dot;
}

/// Dots per module the stored text prints with on this paper; null when
/// the code is the "as is" picture or there is none.
int? paymentQrModuleDotsFor(InvoiceSettings s) {
  final matrix = paymentQrMatrix(s.paymentQrText);
  if (matrix == null) return null;
  return paymentQrModuleDots(
    modules: matrix.moduleCount,
    targetDots: paymentQrTargetDots(s),
    maxWidth: s.printableDots.toDouble(),
  );
}

/// [text] cut to [max] characters for a line on screen.
String shortenQrText(String text, {int max = 80}) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max - 1)}…';
}

// ---- On the paper ---------------------------------------------------------

/// The payment block: the line above, the code, the line under. Worded in
/// the INVOICE language like the rest of the paper.
class PaymentQrBlock extends StatelessWidget {
  const PaymentQrBlock({super.key, required this.settings, required this.base});

  final InvoiceSettings settings;

  /// The paper's base font size, in dots.
  final double base;

  @override
  Widget build(BuildContext context) {
    final s = settings;
    final l10n = lookupAppLocalizations(Locale(s.language));
    final caption = (s.paymentQrCaption ?? l10n.paymentQrDefaultCaption).trim();
    final note = s.paymentQrNote.trim();
    return Column(
      key: const ValueKey('paper-payment-qr'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (caption.isNotEmpty)
          Text(
            isolateSpacedNumbers(caption),
            key: const ValueKey('paper-payment-qr-caption'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        PaymentQrSymbol(
          text: s.paymentQrText,
          picture: s.paymentQrPicture,
          targetDots: paymentQrTargetDots(s),
        ),
        if (note.isNotEmpty)
          Text(
            // A bank account number written in groups keeps its order.
            isolateSpacedNumbers(note),
            key: const ValueKey('paper-payment-qr-note'),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}

/// The code itself, centred, with its quiet zone, drawn on whole dots with
/// antialiasing off: every module is a solid black square of the same whole
/// number of dots, so the 1-bit printer image is exactly the code.
///
/// From [text] when it was read out of the shop's image (the normal case);
/// otherwise the black-and-white [picture], scaled by nearest neighbour.
class PaymentQrSymbol extends StatelessWidget {
  const PaymentQrSymbol({
    super.key,
    required this.text,
    required this.picture,
    required this.targetDots,
  });

  final String text;
  final QrPicture? picture;

  /// The width of the code (quiet zone not included), in dots.
  final int targetDots;

  @override
  Widget build(BuildContext context) {
    final matrix = paymentQrMatrix(text);
    final bitmap = picture?.bitmap;
    if (matrix == null && bitmap == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : targetDots * 1.5;
        final double side;
        final CustomPainter painter;
        if (matrix != null) {
          final dot = paymentQrModuleDots(
            modules: matrix.moduleCount,
            targetDots: targetDots,
            maxWidth: maxWidth,
          );
          side = ((matrix.moduleCount + 2 * paymentQrQuietModules) * dot)
              .toDouble();
          painter = _MatrixPainter(matrix, dot);
        } else {
          // No module grid is known for a picture: about the same size as
          // a redrawn code, with a white margin standing in for the quiet
          // zone.
          var inner = targetDots;
          if (inner > maxWidth * 0.8) inner = (maxWidth * 0.8).floor();
          final pad = (inner * 0.12).round();
          side = (inner + 2 * pad).toDouble();
          painter = _BitmapPainter(bitmap!, inner, pad);
        }
        return Center(
          child: SizedBox(
            key: const ValueKey('paper-payment-qr-symbol'),
            width: side,
            height: side,
            child: ColoredBox(
              color: _paper,
              child: CustomPaint(painter: painter),
            ),
          ),
        );
      },
    );
  }
}

class _MatrixPainter extends CustomPainter {
  _MatrixPainter(this.matrix, this.dot);

  final QrImage matrix;
  final int dot;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..isAntiAlias = false;
    final n = matrix.moduleCount;
    final d = dot.toDouble();
    const q = paymentQrQuietModules;
    for (var row = 0; row < n; row++) {
      var col = 0;
      while (col < n) {
        if (!matrix.isDark(row, col)) {
          col++;
          continue;
        }
        final start = col;
        while (col < n && matrix.isDark(row, col)) {
          col++;
        }
        // One rectangle per run of dark modules: fewer edges, same dots.
        canvas.drawRect(
          Rect.fromLTWH((start + q) * d, (row + q) * d, (col - start) * d, d),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MatrixPainter oldDelegate) =>
      oldDelegate.matrix != matrix || oldDelegate.dot != dot;
}

class _BitmapPainter extends CustomPainter {
  _BitmapPainter(this.bitmap, this.inner, this.pad);

  final QrBitmap bitmap;
  final int inner;
  final int pad;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _ink
      ..isAntiAlias = false;
    final n = bitmap.side;
    // Nearest neighbour: source pixel i covers the whole dots
    // [i·inner/n, (i+1)·inner/n) — never a fraction of a dot.
    int edge(int i) => i * inner ~/ n;
    for (var row = 0; row < n; row++) {
      final y0 = edge(row);
      final y1 = edge(row + 1);
      if (y1 == y0) continue;
      var col = 0;
      while (col < n) {
        if (!bitmap.isBlack(col, row)) {
          col++;
          continue;
        }
        final start = col;
        while (col < n && bitmap.isBlack(col, row)) {
          col++;
        }
        final x0 = edge(start);
        final x1 = edge(col);
        if (x1 == x0) continue;
        canvas.drawRect(
          Rect.fromLTRB(
            (pad + x0).toDouble(),
            (pad + y0).toDouble(),
            (pad + x1).toDouble(),
            (pad + y1).toDouble(),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BitmapPainter oldDelegate) =>
      oldDelegate.bitmap != bitmap ||
      oldDelegate.inner != inner ||
      oldDelegate.pad != pad;
}
