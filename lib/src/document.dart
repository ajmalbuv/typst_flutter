import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;

/// A compiled Typst document.
///
/// This is a lightweight handle to the immutable document living in
/// Rust's memory.
/// It exposes methods to lazily render pages as needed.
/// Memory is freed automatically when this object is garbage collected.
class TypstDocument {
  TypstDocument._({
    required api.CompiledDocument inner,
    required this.pageCount,
  }) : _inner = inner;

  final api.CompiledDocument _inner;

  /// The total number of pages in the compiled document.
  final int pageCount;

  /// Creates a [TypstDocument] from the inner native handle.
  static Future<TypstDocument> create(api.CompiledDocument inner) async {
    final count = await inner.pageCount();
    return TypstDocument._(inner: inner, pageCount: count.toInt());
  }

  /// Gets the dimensions of a specific page in points (pt).
  ///
  /// The aspect ratio can be calculated as `widthPt / heightPt`.
  Future<api.PageInfo> pageInfo(int pageIndex) async {
    try {
      return await _inner.pageInfo(index: BigInt.from(pageIndex));
    } catch (e) {
      throw TypstCompileException(e.toString());
    }
  }

  /// Exports the entire document to a raw PDF byte array.
  Future<Uint8List> exportPdf() async {
    try {
      return await _inner.exportPdf();
    } catch (e) {
      throw TypstCompileException(e.toString());
    }
  }

  /// Exports a specific page to an SVG string.
  Future<String> renderSvg(int pageIndex) async {
    try {
      return await _inner.exportSvg(index: BigInt.from(pageIndex));
    } catch (e) {
      throw TypstCompileException(e.toString());
    }
  }

  /// Renders a specific page to raw RGBA pixels.
  Future<TypstRenderResult> renderRaster({
    required int pageIndex,
    double pixelsPerPt = 2.0,
  }) async {
    try {
      final result = await _inner.renderPage(
        index: BigInt.from(pageIndex),
        pixelPerPt: pixelsPerPt,
      );
      return TypstRenderResult(
        index: pageIndex,
        bytes: result.bytes,
        width: result.width,
        height: result.height,
      );
    } catch (e) {
      throw TypstCompileException(e.toString());
    }
  }
}

/// The result of rendering a Typst document page to a raster image.
class TypstRenderResult {
  /// Creates a [TypstRenderResult].
  TypstRenderResult({
    required this.index,
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// Zero-based index of this page.
  final int index;

  /// Raw RGBA pixel data (4 bytes per pixel, row-major order).
  final Uint8List bytes;

  /// Width of the rendered image in pixels.
  final int width;

  /// Height of the rendered image in pixels.
  final int height;

  ui.Image? _cachedImage;

  /// Decodes the raw RGBA pixels into a [ui.Image] that Flutter can display.
  Future<ui.Image> toImage() async {
    if (_cachedImage != null) return _cachedImage!;

    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    _cachedImage = frameInfo.image;
    return _cachedImage!;
  }

  /// Encodes the raw RGBA pixels as a PNG and returns the PNG bytes.
  Future<Uint8List> toPng() async {
    final image = await toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('PNG encoding returned null.');
    }
    return byteData.buffer.asUint8List();
  }

  /// Releases the cached [ui.Image] if it exists.
  void dispose() {
    _cachedImage?.dispose();
    _cachedImage = null;
  }
}
