import 'dart:typed_data';
import 'dart:ui' as ui;

/// A document compiled by the Typst compiler.
///
/// Contains the output PDF bytes and/or rendered page frames.
class TypstDocument {
  const TypstDocument._({
    required this.pageCount,
    this.pdfBytes,
    Map<int, _PageFrame> frames = const {},
  }) : _frames = frames;

  /// Creates a [TypstDocument] from compiled PDF bytes.
  factory TypstDocument.fromPdf({
    required Uint8List pdfBytes,
    required int pageCount,
  }) => TypstDocument._(pdfBytes: pdfBytes, pageCount: pageCount);

  /// Creates a [TypstDocument] from a single rendered page frame.
  factory TypstDocument.fromFrame({
    required int pageIndex,
    required Uint8List rgba,
    required int width,
    required int height,
    required int pageCount,
  }) => TypstDocument._(
    pageCount: pageCount,
    frames: {pageIndex: _PageFrame(rgba: rgba, width: width, height: height)},
  );

  /// The raw PDF bytes of the compiled document.
  final Uint8List? pdfBytes;

  /// The total number of pages in the document.
  final int pageCount;

  final Map<int, _PageFrame> _frames;

  /// Returns the PDF bytes. Throws [StateError] if this document was
  /// only rendered as a frame and not compiled to PDF.
  Uint8List get pdf {
    if (pdfBytes == null) {
      throw StateError('PDF bytes not available. Use TypstCompiler.compile().');
    }
    return pdfBytes!;
  }

  /// Returns a Flutter [ui.Image] for the given [pageIndex].
  ///
  /// Throws [StateError] if the page has not been rendered.
  Future<ui.Image> imageForPage(int pageIndex) async {
    final frame = _frames[pageIndex];
    if (frame == null) {
      throw StateError('Page $pageIndex has not been rendered.');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  /// Returns the raw RGBA pixel data for the given [pageIndex], if available.
  Uint8List? rawRgbaForPage(int pageIndex) => _frames[pageIndex]?.rgba;

  /// Returns the pixel width for the given [pageIndex], if available.
  int? widthForPage(int pageIndex) => _frames[pageIndex]?.width;

  /// Returns the pixel height for the given [pageIndex], if available.
  int? heightForPage(int pageIndex) => _frames[pageIndex]?.height;
}

class _PageFrame {
  const _PageFrame({
    required this.rgba,
    required this.width,
    required this.height,
  });
  final Uint8List rgba;
  final int width;
  final int height;
}
