import 'dart:ui' as ui;

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
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
    try {
      await RustLib.init();
      // flutter_rust_bridge throws a StateError if init() is called more than
      // once. We ignore this specific error to remain robust in tests.
      // ignore: avoid_catching_errors
    } on StateError catch (e) {
      if (!e.message.contains('twice')) rethrow;
    }

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

  PlatformInt64? _dateTimeToSysTime(DateTime? date) {
    if (date == null) return null;
    return PlatformInt64Util.from((date.millisecondsSinceEpoch / 1000).round());
  }

  /// Compiles a document and keeps it in memory for rendering of multipages.
  /// Returns the total page count.
  Future<int> compileDocument({
    required String source,
    FileSource? files,
    DateTime? date,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);
    try {
      return await engine.compileDocument(
        markup: source,
        files: virtualFiles,
        sysTime: _dateTimeToSysTime(date),
      );
    } on api.TypstCompileError catch (e) {
      throw TypstCompileException(
        'Compilation failed',
        diagnostics: e.diagnostics,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Renders single page of the currently compiled document to a raster image.
  /// Call [compileDocument] first.
  Future<TypstRenderResult> renderCachedPage({
    int pageIndex = 0,
    double pixelsPerPt = 2.0,
  }) async {
    try {
      final result = await engine.renderCachedPage(
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

  /// Renders a single page of the currently compiled document to an SVG string.
  /// Call [compileDocument] first.
  Future<String> renderCachedPageAsSvg({int pageIndex = 0}) async {
    try {
      return await engine.renderCachedPageAsSvg(
        pageIndex: BigInt.from(pageIndex),
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Compiles Typst [source] markup to a PDF document.
  Future<TypstDocument> compile({
    required String source,
    FileSource? files,
    DateTime? date,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);

    try {
      final result = await engine.compilePdf(
        markup: source,
        files: virtualFiles,
        sysTime: _dateTimeToSysTime(date),
      );
      return TypstDocument.fromPdf(
        pdfBytes: result.bytes,
        pageCount: result.pageCount,
      );
    } on api.TypstCompileError catch (e) {
      throw TypstCompileException(
        'Compilation failed',
        diagnostics: e.diagnostics,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Renders a single page of [source] markup to a raster image.
  Future<TypstRenderResult> renderPage({
    required String source,
    int pageIndex = 0,
    double pixelsPerPt = 2.0,
    FileSource? files,
    DateTime? date,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);

    try {
      final result = await engine.renderPage(
        markup: source,
        files: virtualFiles,
        pageIndex: BigInt.from(pageIndex),
        pixelPerPt: pixelsPerPt,
        sysTime: _dateTimeToSysTime(date),
      );
      return TypstRenderResult(
        bytes: result.bytes,
        width: result.width,
        height: result.height,
      );
    } on api.TypstCompileError catch (e) {
      throw TypstCompileException(
        'Compilation failed',
        diagnostics: e.diagnostics,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Compiles Typst [source] markup into a list of SVG strings (one per page).
  Future<TypstDocument> compileSvg({
    required String source,
    FileSource? files,
    DateTime? date,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);

    try {
      final result = await engine.compileSvg(
        markup: source,
        files: virtualFiles,
        sysTime: _dateTimeToSysTime(date),
      );
      return TypstDocument.fromSvg(svgPages: result);
    } on api.TypstCompileError catch (e) {
      throw TypstCompileException(
        'Compilation failed',
        diagnostics: e.diagnostics,
      );
    } catch (e) {
      throw TypstCompileException('$e');
    }
  }

  /// Renders a single page of [source] markup as PNG bytes.
  Future<Uint8List> renderPageAsPng({
    required String source,
    int pageIndex = 0,
    double pixelsPerPt = 2.0,
    FileSource? files,
    DateTime? date,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);
    try {
      return await engine.renderPageAsPng(
        markup: source,
        files: virtualFiles,
        pageIndex: BigInt.from(pageIndex),
        pixelPerPt: pixelsPerPt,
        sysTime: _dateTimeToSysTime(date),
      );
    } on api.TypstCompileError catch (e) {
      throw TypstCompileException(
        'Compilation failed',
        diagnostics: e.diagnostics,
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
