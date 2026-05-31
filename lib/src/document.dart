import 'dart:typed_data';
import 'dart:ui' as ui;

/// A page within a rendered Typst document.
///
/// Provides synchronous access to dimensions ([width], [height], [aspectRatio])
/// and lazy-loaded, cached access to the rendered image via [toImage].
class TypstPage {
  /// Creates a [TypstPage] with the given dimensions and raw RGBA data.
  TypstPage({
    required this.index,
    required this.width,
    required this.height,
    required this.rgba,
  });

  /// Zero-based index of this page in the document.
  final int index;

  /// Width of the page in pixels.
  final int width;

  /// Height of the page in pixels.
  final int height;

  /// Raw RGBA pixel data (4 bytes per pixel).
  final Uint8List rgba;

  /// The ratio of [width] to [height].
  double get aspectRatio => width / height;

  ui.Image? _cachedImage;

  /// Decodes the raw RGBA pixels into a [ui.Image] that Flutter can display.
  ///
  /// The resulting image is cached. If the image is already decoded,
  /// this returns the cached instance immediately.
  Future<ui.Image> toImage() async {
    if (_cachedImage != null) return _cachedImage!;

    final buffer = await ui.ImmutableBuffer.fromUint8List(rgba);
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

  /// Releases the cached [ui.Image] if it exists.
  void dispose() {
    _cachedImage?.dispose();
    _cachedImage = null;
  }
}

/// A document compiled by the Typst compiler.
///
/// Use exhaustive pattern matching to handle specific document types:
/// ```dart
/// switch (document) {
///   case PdfDocument(bytes: var b): // Handle PDF
///   case SvgDocument(pages: var p): // Handle SVG
///   case RasterDocument(pages: var p): // Handle Raster
/// }
/// ```
sealed class TypstDocument {
  const TypstDocument({required this.pageCount});

  /// The total number of pages in the document.
  final int pageCount;
}

/// A document compiled into raw PDF bytes.
class PdfDocument extends TypstDocument {
  /// Creates a [PdfDocument] from compiled bytes.
  const PdfDocument({required this.bytes, required super.pageCount});

  /// The raw PDF bytes.
  final Uint8List bytes;

  @override
  String toString() =>
      'PdfDocument(pageCount: $pageCount, bytes: ${bytes.length} bytes)';
}

/// A document compiled into a list of SVG strings (one per page).
class SvgDocument extends TypstDocument {
  /// Creates an [SvgDocument] from a list of SVG page strings.
  const SvgDocument({required this.pages}) : super(pageCount: pages.length);

  /// The SVG string content for each page.
  final List<String> pages;

  @override
  String toString() => 'SvgDocument(pageCount: $pageCount)';
}

/// A document compiled into a set of rasterized images.
class RasterDocument extends TypstDocument {
  /// Creates a [RasterDocument] from a list of [TypstPage] objects.
  const RasterDocument({required this.pages}) : super(pageCount: pages.length);

  /// The rendered pages of this document.
  final List<TypstPage> pages;

  /// Releases native resources held by each page in the document.
  void dispose() {
    for (final page in pages) {
      page.dispose();
    }
  }

  @override
  String toString() => 'RasterDocument(pageCount: $pageCount)';
}
