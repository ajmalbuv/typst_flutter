import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:typst_flutter/typst_flutter.dart';

class FakeCompiledDocument extends Fake implements api.CompiledDocument {
  bool disposed = false;

  @override
  BigInt pageCount() => BigInt.from(1);

  @override
  api.PageInfo pageInfo({required BigInt index}) =>
      const api.PageInfo(widthPt: 200, heightPt: 300);

  @override
  Future<Uint8List> exportPdf() async => Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<String> exportSvg({required BigInt index}) async => '<svg>1</svg>';

  @override
  Future<api.RenderResult> renderPage({
    required BigInt index,
    required double pixelPerPt,
  }) async => api.RenderResult(
    bytes: Uint8List.fromList(List.filled(100 * 100 * 4, 255)),
    width: 100,
    height: 100,
  );

  @override
  void dispose() {
    disposed = true;
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

void main() {
  setUpAll(() {
    RustLib.initMock(api: FakeRustLibApi());
  });

  group('TypstCompiler', () {
    test('Can create a compiler instance', () async {
      final compiler = await TypstCompiler.create();
      expect(compiler, isNotNull);
      expect(compiler.compilerVersion, equals('0.14.2-test'));
    });

    test('Successful compilation returns a TypstDocument', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');

      expect(doc, isA<TypstDocument>());
      expect(doc.pageCount, equals(1));
    });

    test('Compilation with inputs works successfully', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(
        source: 'Hello',
        inputs: {'theme': 'dark'},
      );

      expect(doc, isA<TypstDocument>());
    });

    test('query returns extracted JSON', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: '= Hello');
      final result = await compiler.query(document: doc, selector: '<heading>');

      expect(result, contains('heading'));
      expect(result, contains('Hello'));
    });

    test('Compilation error throws TypstCompileException', () async {
      final compiler = await TypstCompiler.create();

      expect(
        () => compiler.compile(source: 'error'),
        throwsA(
          isA<TypstCompileException>().having(
            (e) => e.message,
            'message',
            contains('Compilation failed'),
          ),
        ),
      );
    });

    test('renderRaster returns TypstRenderResult', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');
      final result = await doc.renderRaster(pageIndex: 0);

      expect(result.width, equals(100));
      expect(result.height, equals(100));
      expect(result.bytes.length, equals(100 * 100 * 4));
    });

    test('exportPdf returns bytes', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');
      final pdf = await doc.exportPdf();

      expect(pdf.length, equals(4));
    });

    test('dispose() releases resources', () async {
      final compiler = await TypstCompiler.create();
      compiler.dispose();
    });
  });

  group('TypstDocument', () {
    test('dispose() is safe to call multiple times', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');

      doc.dispose();
    });

    test('use after dispose throws StateError', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');
      doc.dispose();

      expect(doc.exportPdf, throwsStateError);
      expect(() => doc.renderSvg(0), throwsStateError);
      expect(() => doc.renderRaster(pageIndex: 0), throwsStateError);
      expect(() => doc.pageInfo(0), throwsStateError);
    });

    test('renderSvg returns SVG string', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');
      final svg = await doc.renderSvg(0);

      expect(svg, contains('<svg'));
    });

    test('pageInfo returns dimensions', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');
      final info = doc.pageInfo(0);

      expect(info.widthPt, equals(200));
      expect(info.heightPt, equals(300));
    });
  });

  group('FontSource', () {
    test('bytes() source returns provided bytes', () async {
      final bytes = Uint8List.fromList([10, 20]);
      final source = FontSource.bytes([bytes]);
      final loaded = await source.load();

      expect(loaded.length, equals(1));
      expect(loaded.first, equals(bytes));
    });

    test('none() source returns empty list', () async {
      const source = FontSource.none();
      final loaded = await source.load();
      expect(loaded, isEmpty);
    });
  });
}
