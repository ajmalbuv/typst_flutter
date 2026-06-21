import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:meta/meta.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;

/// A compiled Typst document.
///
/// This is a lightweight handle to the immutable document living in
/// Rust's memory. It exposes methods to lazily render pages as needed.
///
/// **Lifecycle:** Call [dispose] when you are done with this document to
/// eagerly release the native memory held by the Rust `PagedDocument`.
/// If not disposed, resources will eventually be reclaimed by the Dart
/// garbage collector, but this is non-deterministic and the underlying
/// document can be several megabytes.
///
/// ```dart
/// final doc = await compiler.compile(source: markup);
/// try {
///   final pdf = await doc.exportPdf();
///   // ...use pdf bytes...
/// } finally {
///   doc.dispose();
/// }
/// ```
class TypstDocument {
  /// Creates a [TypstDocument] from the inner native handle.
  TypstDocument.fromInner(api.CompiledDocument inner) : _inner = inner;

  final api.CompiledDocument _inner;
  bool _disposed = false;

  /// The internal Rust handle. Do not use directly.
  @internal
  api.CompiledDocument get inner => _inner;

  /// The total number of pages in the compiled document.
  int get pageCount => _inner.pageCount().toInt();

  /// Any compiler warnings emitted during compilation.
  ///
  /// These are non-fatal diagnostics (e.g. deprecated syntax, ambiguous layout)
  /// that did not prevent compilation but may indicate issues.
  List<api.TypstDiagnostic> get warnings => _inner.warnings();

  void _checkNotDisposed() {
    if (_disposed) {
      throw StateError(
        'TypstDocument has already been disposed. '
        'Do not use a document after calling dispose().',
      );
    }
  }

  /// Releases the native resources held by this document.
  ///
  /// After calling this, all methods on this instance will throw
  /// [StateError]. It is safe to call [dispose] more than once.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _inner.dispose();
  }

  /// Gets the dimensions of a specific page in points (pt).
  ///
  /// The aspect ratio can be calculated as `widthPt / heightPt`.
  ///
  /// Throws a [RangeError] if [pageIndex] is negative or ≥ [pageCount].
  api.PageInfo pageInfo(int pageIndex) {
    _checkNotDisposed();
    RangeError.checkValidIndex(pageIndex, null, 'pageIndex', pageCount);
    return _inner.pageInfo(index: BigInt.from(pageIndex));
  }

  /// Exports the entire document to a raw PDF byte array.
  ///
  /// Throws [TypstRenderException] if the PDF export fails.
  Future<Uint8List> exportPdf() async {
    _checkNotDisposed();
    try {
      return await _inner.exportPdf();
    } catch (e) {
      throw TypstRenderException(e.toString());
    }
  }

  /// Exports a specific page to an SVG string.
  ///
  /// Throws a [RangeError] if [pageIndex] is negative or ≥ [pageCount].
  /// Throws [TypstRenderException] if the SVG export fails.
  Future<String> renderSvg(int pageIndex) async {
    _checkNotDisposed();
    RangeError.checkValidIndex(pageIndex, null, 'pageIndex', pageCount);
    try {
      return await _inner.exportSvg(index: BigInt.from(pageIndex));
    } catch (e) {
      throw TypstRenderException(e.toString());
    }
  }

  /// Renders a specific page to raw RGBA pixels.
  ///
  /// Throws a [RangeError] if [pageIndex] is negative or ≥ [pageCount].
  /// Throws [TypstRenderException] if the render fails.
  Future<TypstRenderResult> renderRaster({
    required int pageIndex,
    double pixelsPerPt = 2.0,
  }) async {
    _checkNotDisposed();
    RangeError.checkValidIndex(pageIndex, null, 'pageIndex', pageCount);
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
      throw TypstRenderException(e.toString());
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
  ///
  /// The resulting image is cached. Subsequent calls return the same instance
  /// without re-decoding. Call [dispose] to release the cached image.
  Future<ui.Image> toImage() async {
    if (_cachedImage != null) return _cachedImage!;
    _cachedImage = await _decodeImage();
    return _cachedImage!;
  }

  /// Encodes the raw RGBA pixels as a PNG and returns the PNG bytes.
  ///
  /// This method is self-contained: if no cached [ui.Image] exists, it
  /// creates a temporary one, encodes it, and disposes it immediately —
  /// no leak even if [dispose] is never called. If a cached image already
  /// exists (from a prior [toImage] call), it reuses that image without
  /// disposing it.
  Future<Uint8List> toPng() async {
    final hadCached = _cachedImage != null;
    final image = hadCached ? _cachedImage! : await _decodeImage();
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData!.buffer.asUint8List();
    } finally {
      // Only dispose the image if we created it ad-hoc for this call.
      if (!hadCached) image.dispose();
    }
  }

  /// Releases the cached [ui.Image] if it exists.
  void dispose() {
    _cachedImage?.dispose();
    _cachedImage = null;
  }

  /// Internal: decodes RGBA bytes into a [ui.Image].
  ///
  /// All interim native objects ([ui.ImmutableBuffer], [ui.ImageDescriptor],
  /// and [ui.Codec]) are disposed in reverse order via `try/finally`, regardless
  /// of whether an error occurs during decoding.
  Future<ui.Image> _decodeImage() async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      try {
        final codec = await descriptor.instantiateCodec();
        try {
          final frameInfo = await codec.getNextFrame();
          return frameInfo.image;
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
      }
    } finally {
      buffer.dispose();
    }
  }
}
