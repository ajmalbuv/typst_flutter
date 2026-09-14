import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:typst_flutter/typst_flutter.dart';

class FakeCompiledDocument extends Fake implements api.CompiledDocument {
  FakeCompiledDocument({this.pages = 1, this.renderThrows = false});
  final int pages;
  final bool renderThrows;
  bool disposed = false;
  int disposeCallCount = 0;
  double? lastPixelPerPt;

  @override
  BigInt pageCount() => BigInt.from(pages);

  @override
  api.PageInfo pageInfo({required BigInt index}) {
    if (index >= BigInt.from(pages)) throw Exception('Index out of bounds');
    if (pages == 3) {
      return api.PageInfo(
        widthPt: 100 * (index.toInt() + 1).toDouble(),
        heightPt: 200 * (index.toInt() + 1).toDouble(),
      );
    }
    return const api.PageInfo(widthPt: 200, heightPt: 300);
  }

  @override
  List<api.TypstDiagnostic> warnings() => const [
    api.TypstDiagnostic(
      severity: api.TypstSeverity.warning,
      message: 'Test warning',
      hints: [],
    ),
  ];

  @override
  Future<Uint8List> exportPdf() async {
    if (renderThrows) throw Exception('PDF export failed');
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<String> exportSvg({required BigInt index}) async {
    if (index >= BigInt.from(pages)) throw Exception('Index out of bounds');
    if (renderThrows) throw Exception('SVG failed');
    return '<svg>1</svg>';
  }

  @override
  Future<api.RenderResult> renderPage({
    required BigInt index,
    required double pixelPerPt,
  }) async {
    lastPixelPerPt = pixelPerPt;
    if (index >= BigInt.from(pages)) throw Exception('Index out of bounds');
    if (renderThrows) throw Exception('Render failed');
    if (pixelPerPt == 99) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return api.RenderResult(
      bytes: Uint8List.fromList(List.filled(100 * 100 * 4, 255)),
      width: 100,
      height: 100,
    );
  }

  @override
  void dispose() {
    disposed = true;
    disposeCallCount++;
  }
}

/// A manual "Fake" implementation of the TypstEngine.
class FakeTypstEngine extends Fake implements api.TypstEngine {
  @override
  Future<api.CompiledDocument> compile({
    required String markup,
    required List<api.VirtualFile> files,
    PlatformInt64? sysTime,
    Map<String, String>? inputs,
    bool allowPackages = true,
  }) async {
    if (markup == 'error') {
      throw const api.TypstCompileError(
        diagnostics: [
          api.TypstDiagnostic(
            severity: TypstSeverity.error,
            message: 'Simulated error',
            hints: [],
          ),
        ],
      );
    }
    if (markup == 'generic_error') {
      throw Exception('Generic error');
    }
    if (markup == 'delayed') {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return FakeCompiledDocument();
  }

  @override
  Future<void> addFonts({required List<Uint8List> fontData}) async {}

  @override
  Future<String> query({
    required api.CompiledDocument document,
    required String selector,
  }) async => '[{"type":"heading","level":1,"body":"Hello"}]';

  @override
  void dispose() {}
}

/// A manual "Fake" implementation of the Rust API.
class FakeRustLibApi extends Fake implements RustLibApi {
  @override
  api.TypstEngine crateApiTypstTypstEngineNew() => FakeTypstEngine();

  @override
  String crateApiTypstGetTypstVersion() => '0.14.2-test';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Fake whose export/render methods always throw, for error-wrapping tests.
class FailingCompiledDocument extends Fake implements api.CompiledDocument {
  @override
  BigInt pageCount() => BigInt.from(1);

  @override
  api.PageInfo pageInfo({required BigInt index}) =>
      const api.PageInfo(widthPt: 100, heightPt: 100);

  @override
  Future<Uint8List> exportPdf() async => throw Exception('PDF export failed');

  @override
  Future<String> exportSvg({required BigInt index}) async =>
      throw Exception('SVG failed');

  @override
  Future<api.RenderResult> renderPage({
    required BigInt index,
    required double pixelPerPt,
  }) async => throw Exception('Render failed');

  @override
  void dispose() {}
}

/// Multi-page fake (3 pages) with page-index-dependent dimensions.
class MultiPageCompiledDocument extends Fake implements api.CompiledDocument {
  @override
  BigInt pageCount() => BigInt.from(3);

  @override
  api.PageInfo pageInfo({required BigInt index}) => api.PageInfo(
    widthPt: 100.0 * (index.toInt() + 1),
    heightPt: 200.0 * (index.toInt() + 1),
  );

  @override
  void dispose() {}
}

class FailingFontSource extends FontSource {
  @override
  Future<List<Uint8List>> load() async => throw Exception('Generic font error');
  @override
  List<Object?> get props => [];
}
