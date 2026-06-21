import 'dart:ffi';

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
/// // Compile to a lightweight document handle
/// final doc = await compiler.compile(source: myMarkup);
///
/// // Lazily render pages or export PDF
/// final pdfBytes = await doc.exportPdf();
/// final result = await doc.renderRaster(pageIndex: 0);
/// ```
class TypstCompiler implements Finalizable {
  TypstCompiler._({required api.TypstEngine engine}) : _engine = engine;

  /// The underlying stateful Rust engine.
  final api.TypstEngine _engine;

  /// Releases the native resources associated with this compiler.
  ///
  /// After calling this, the compiler instance is no longer usable and any
  /// further calls to its methods will throw an error.
  void dispose() {
    _engine.dispose();
  }

  /// Creates a [TypstCompiler] and initialises the native bridge.
  ///
  /// [fonts] — additional font files to make available to the Typst compiler.
  /// These are added on top of the bundled core fonts (`Libertinus Serif`,
  /// `DejaVu Sans Mono`, and `NewCM Math`).
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
      await _engine.addFonts(fontData: fontBytes);
    }
  }

  PlatformInt64? _dateTimeToSysTime(DateTime? date) {
    if (date == null) return null;
    return PlatformInt64Util.from((date.millisecondsSinceEpoch / 1000).round());
  }

  /// Compiles Typst [source] markup into a lightweight document handle.
  ///
  /// Returns a [TypstDocument] which can be used to query page dimensions,
  /// lazily render raster/SVG pages, or export the full document to PDF.
  Future<TypstDocument> compile({
    required String source,
    FileSource? files,
    DateTime? date,
    Map<String, String>? inputs,
  }) async {
    final virtualFiles = await _buildVirtualFiles(files);
    try {
      final inner = await _engine.compile(
        markup: source,
        files: virtualFiles,
        sysTime: _dateTimeToSysTime(date),
        inputs: inputs,
      );
      return TypstDocument.fromInner(inner);
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
  String get compilerVersion => api.getTypstVersion();

  /// Queries the compiled [document] using a Typst [selector] string.
  ///
  /// Returns a JSON string containing the queried elements (e.g. headings).
  Future<String> query({
    required TypstDocument document,
    required String selector,
  }) async => _engine.query(document: document.inner, selector: selector);

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<List<api.VirtualFile>> _buildVirtualFiles(FileSource? source) async {
    final effectiveSource = source ?? const FileSource.none();
    final map = await effectiveSource.load();
    return map.entries
        .map((e) => api.VirtualFile(path: e.key, bytes: e.value))
        .toList();
  }
}
