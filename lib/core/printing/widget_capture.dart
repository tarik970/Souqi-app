/// Renders a widget OFF-SCREEN into raw pixels.
///
/// The widget is laid out in its own little render tree (its own
/// [BuildOwner], [PipelineOwner] and [RenderView]) at an exact logical width
/// and whatever height its content needs, then rasterised at [pixelRatio].
/// Nothing is shown on the display, and the app's theme, text scale and
/// locale do not leak in: the widget gets no [MediaQuery] and no [Theme].
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'raster.dart';

/// Rasterised rows per captured slice. Each slice is one GPU image; keeping
/// it short stays far below the maximum texture size of low-end phones
/// (often 4096), which a long receipt would exceed as a single image.
const int _sliceRows = 1024;

class _SliceBoundary extends RenderRepaintBoundary {
  /// Rasterises [bounds] (logical pixels, in this boundary's coordinates).
  Future<ui.Image> slice(Rect bounds, double pixelRatio) {
    final offsetLayer = layer! as OffsetLayer;
    return offsetLayer.toImage(bounds, pixelRatio: pixelRatio);
  }
}

/// Lays [child] out [logicalWidth] logical pixels wide and returns it as
/// pixels. The result is exactly `logicalWidth × pixelRatio` pixels wide, so
/// with `pixelRatio: 1` one logical pixel is one printer dot.
///
/// [child] must paint an opaque background and must not depend on anything
/// that loads asynchronously (pass decoded images, not image providers).
Future<RgbaImage> captureWidget(
  Widget child, {
  required int logicalWidth,
  double pixelRatio = 1,
}) async {
  assert(logicalWidth > 0 && pixelRatio > 0);
  final width = logicalWidth.toDouble();
  final boundary = _SliceBoundary();
  final renderView = RenderView(
    view: WidgetsBinding.instance.platformDispatcher.views.first,
    configuration: ViewConfiguration(
      // Tight width, free height: the view takes the height of its content.
      logicalConstraints: BoxConstraints(minWidth: width, maxWidth: width),
      devicePixelRatio: pixelRatio,
    ),
    child: boundary,
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focusManager = FocusManager();
  final buildOwner = BuildOwner(
    focusManager: focusManager,
    onBuildScheduled: () {},
  );
  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: Directionality(textDirection: TextDirection.ltr, child: child),
  ).attachToRenderTree(buildOwner);

  try {
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

    final pixelWidth = (width * pixelRatio).round();
    final pixelHeight = (boundary.size.height * pixelRatio).ceil();
    if (pixelHeight <= 0) {
      throw StateError('the captured widget has no height');
    }
    final rgba = Uint8List(pixelWidth * pixelHeight * 4);
    for (var row = 0; row < pixelHeight; row += _sliceRows) {
      final rows =
          row + _sliceRows > pixelHeight ? pixelHeight - row : _sliceRows;
      final image = await boundary.slice(
        Rect.fromLTWH(0, row / pixelRatio, width, rows / pixelRatio),
        pixelRatio,
      );
      try {
        if (image.width != pixelWidth || image.height != rows) {
          throw StateError(
            'slice is ${image.width}×${image.height}, expected $pixelWidth×$rows',
          );
        }
        final data = await image.toByteData();
        if (data == null) throw StateError('could not read the rendered image');
        rgba.setRange(
          row * pixelWidth * 4,
          (row + rows) * pixelWidth * 4,
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      } finally {
        image.dispose();
      }
    }
    return RgbaImage(width: pixelWidth, height: pixelHeight, rgba: rgba);
  } finally {
    // Unmount the element tree, then let go of the render tree.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(buildOwner, root);
    buildOwner
      ..buildScope(root)
      ..finalizeTree();
    pipelineOwner.rootNode = null;
    renderView.dispose();
    focusManager.dispose();
  }
}
