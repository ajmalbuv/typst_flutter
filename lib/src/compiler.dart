import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:typst_flutter/src/document.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';

/// The Typst compiler bridge.
///
/// Create a single instance per app or per compiler configuration and reuse
/// it — construction is lightweight; the heavy native library is loaded once
/// when [RustLib.init] is called.
///
/// ```dart
/// final compiler = await TypstCompiler.create(
///   fonts: FontSource.assets(['assets/fonts/Roboto.ttf']),
/// );
///
/// // Compile to PDF
/// final doc = await compiler.compile(source: myMarkup);
/// await Share.shareXFiles([XFile.fromData(doc.pdf, mimeType: 'application/pdf')]);
///
/// // Render to Flutter image (live preview)
/// final result = await compiler.renderPage(source: myMarkup);
/// ```
class TypstCompiler {
  TypstCompiler._({required this.engine});

  /// The underlying stateful Rust engine.
  final api.TypstEngine engine;

  /// Creates a [TypstCompiler] and initialises the native bridge.
  ///
  /// [fonts] — additional font files to make available to the Typst compiler.
  /// These are added on top of the bundled core fonts (Libertinus, NewCM Math).
  ///
  /// This is safe to call multiple times; the native library is only
  /// initialised once.
  static Future<TypstCompiler> create({FontSource? fonts}) async {
    await RustLib.init();
    final engine = api.TypstEngine();
    if (fonts != null) {
      final fontBytes = await fonts.load();
      if (fontBytes.isNotEmpty) {
        await engine.addFonts(fontData: fontBytes);
      }
    }
    return TypstCompiler._(engine: engine);
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Adds more fonts to this compiler instance.
  Future<void> addFonts(FontSource fonts) async {
    final fontBytes = await fonts.load();
    if (fontBytes.isNotEmpty) {
      await engine.addFonts(fontData: fontBytes);
    }
  }

  /// Compiles Typst [source] markup to a PDF document.
  ///
  /// [files] — optional virtual file system for images, data files, or
  /// included `.typ` files referenced in [source]. The map key must match
  /// the path written in the markup exactly (e.g. `'logo.png'` for
  /// `#image("logo.png")`).
  ///
  /// Returns a [TypstDocument] whose [TypstDocument.pdf] property contains
  /// the raw PDF bytes.
  ///
  /// Throws [TypstCompileException] if the Typst source has errors.
  Future<TypstDocument> compile({
    required String source,
    FileSource? files,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);

    try {
      final result = await engine.compilePdf(
        markup: source,
        files: virtualFiles,
      );
      return TypstDocument.fromPdf(
        pdfBytes: result.bytes,
        pageCount: result.pageCount,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Renders a single page of [source] markup to a raster image.
  ///
  /// [pageIndex]    — zero-based page index (default: 0).
  /// [pixelsPerPt]  — rendering density; use 2.0 for crisp display on
  ///                  high-DPI screens (default: 2.0).
  /// [files]        — optional virtual file system for images, data files,
  ///                  or included `.typ` files.
  ///
  /// Returns a [TypstRenderResult] whose [TypstRenderResult.toImage] method
  /// converts the raw pixels into a [ui.Image] ready for display.
  ///
  /// Throws [TypstCompileException] if the Typst source has errors.
  Future<TypstRenderResult> renderPage({
    required String source,
    int pageIndex = 0,
    double pixelsPerPt = 2.0,
    FileSource? files,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);

    try {
      final result = await engine.renderPage(
        markup: source,
        files: virtualFiles,
        pageIndex: BigInt.from(pageIndex),
        pixelPerPt: pixelsPerPt,
      );
      return TypstRenderResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Compiles Typst [source] markup into a list of SVG strings (one per page).
  ///
  /// [files] — optional virtual file system for images, data files, or
  /// included `.typ` files.
  ///
  /// Returns a [TypstDocument] containing the SVG strings for each page.
  ///
  /// Throws [TypstCompileException] if the Typst source has errors.
  Future<TypstDocument> compileSvg({
    required String source,
    FileSource? files,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);

    try {
      final result = await engine.compileSvg(
        markup: source,
        files: virtualFiles,
      );
      return TypstDocument.fromSvg(svgPages: result);
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Renders a single page of [source] markup as PNG bytes.
  ///
  /// This is the preferred way to get a PNG — encoding happens inside Rust
  /// (via `tiny_skia`) so there is no GPU texture round-trip.
  ///
  /// [pageIndex]    — zero-based page index (default: 0).
  /// [pixelsPerPt]  — rendering density; use 2.0 for HiDPI (default: 2.0).
  /// [files]        — optional virtual file system for images, includes, etc.
  ///
  /// Returns a [Uint8List] of raw PNG bytes ready to write to disk or share:
  /// ```dart
  /// final png = await compiler.renderPageAsPng(source: myMarkup);
  /// await Share.shareXFiles([XFile.fromData(png, mimeType: 'image/png')]);
  /// ```
  ///
  /// Throws [TypstCompileException] if the Typst source has errors.
  Future<Uint8List> renderPageAsPng({
    required String source,
    int pageIndex = 0,
    double pixelsPerPt = 2.0,
    FileSource? files,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);
    try {
      return await engine.renderPageAsPng(
        markup: source,
        files: virtualFiles,
        pageIndex: BigInt.from(pageIndex),
        pixelPerPt: pixelsPerPt,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Returns the version string of the embedded Typst compiler engine.
  Future<String> get compilerVersion => api.getTypstVersion();

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<List<api.VirtualFile>> _buildVirtualFiles(FileSource? source) async {
    if (source == null) return const [];
    final map = await source.load();
    return map.entries
        .map((e) => api.VirtualFile(path: e.key, bytes: e.value))
        .toList();
  }
}

/// The result of rendering a Typst document page to a raster image.
class TypstRenderResult {
  /// Creates a new render result containing the raw RGBA pixels and dimensions.
  const TypstRenderResult({
    required this.bytes,
    required this.width,
    required this.height,
  });

  /// Raw RGBA pixel data (4 bytes per pixel, row-major order).
  final Uint8List bytes;

  /// Width of the rendered image in pixels.
  final int width;

  /// Height of the rendered image in pixels.
  final int height;

  /// Decodes the raw RGBA pixel data into a [ui.Image] that Flutter can
  /// display with a `RawImage` widget or a `CustomPainter`.
  Future<ui.Image> toImage() async {
    // The Rust render_page function returns raw RGBA bytes — 4 bytes per
    // pixel in row-major order. ui.ImageDescriptor.raw() decodes these
    // directly into a gpu texture without any intermediate PNG roundtrip.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  /// Encodes the raw RGBA pixels as a PNG and returns the PNG bytes.
  ///
  /// Prefer [TypstCompiler.renderPageAsPng] when you only need PNG bytes —
  /// that path encodes entirely in Rust with no GPU round-trip.
  ///
  /// Use this method when you already have a [TypstRenderResult] (e.g. you
  /// displayed the image first and now want to export it).
  ///
  /// ```dart
  /// final result = await compiler.renderPage(source: myMarkup);
  /// final png = await result.toPng();
  /// await Share.shareXFiles([XFile.fromData(png, mimeType: 'image/png')]);
  /// ```
  Future<Uint8List> toPng() async {
    final image = await toImage();
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('PNG encoding returned null — image may be invalid.');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }
}
