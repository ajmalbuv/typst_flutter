import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:typst_flutter/typst_flutter.dart';

/// A manual "Fake" implementation of the TypstEngine.
class FakeTypstEngine extends Fake implements api.TypstEngine {
  @override
  Future<api.TypstResult> compilePdf({
    required String markup,
    required List<api.VirtualFile> files,
    PlatformInt64? sysTime,
  }) async {
    if (markup == 'error') {
      throw const api.TypstCompileError(
        diagnostics: [
          api.TypstDiagnostic(
            severity: 'error',
            message: 'Simulated error',
            hints: [],
          ),
        ],
      );
    }
    return api.TypstResult(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      pageCount: 1,
    );
  }

  @override
  Future<api.RenderResult> renderPage({
    required String markup,
    required List<api.VirtualFile> files,
    required BigInt pageIndex,
    required double pixelPerPt,
    PlatformInt64? sysTime,
  }) async => api.RenderResult(
    bytes: Uint8List.fromList(List.filled(100 * 100 * 4, 255)),
    width: 100,
    height: 100,
  );

  @override
  Future<void> addFonts({required List<Uint8List> fontData}) async {}
}

/// A manual "Fake" implementation of the Rust API.
class FakeRustLibApi extends Fake implements RustLibApi {
  @override
  api.TypstEngine crateApiTypstTypstEngineNew() => FakeTypstEngine();

  @override
  Future<String> crateApiTypstGetTypstVersion() async => '0.11.0-test';

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
      expect(await compiler.compilerVersion, equals('0.11.0-test'));
    });

    test('Successful compilation returns PDF bytes', () async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: 'Hello');

      expect(doc.pdf, isNotEmpty);
      expect(doc.pdf.length, equals(4));
      expect(doc.pageCount, equals(1));
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

    test('renderPage returns TypstRenderResult', () async {
      final compiler = await TypstCompiler.create();
      final result = await compiler.renderPage(source: 'Hello');

      expect(result.width, equals(100));
      expect(result.height, equals(100));
      expect(result.bytes.length, equals(100 * 100 * 4));
    });
  });

  group('TypstDocument', () {
    test('fromPdf creates document with PDF bytes', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final doc = TypstDocument.fromPdf(pdfBytes: bytes, pageCount: 5);

      expect(doc.pdf, equals(bytes));
      expect(doc.pageCount, equals(5));
      expect(doc.pdfBytes, isNotNull);
      expect(doc.svgPages, isNull);
    });

    test('fromSvg creates document with SVG pages', () {
      final pages = ['<svg>1</svg>', '<svg>2</svg>'];
      final doc = TypstDocument.fromSvg(svgPages: pages);

      expect(doc.svgs, equals(pages));
      expect(doc.pageCount, equals(2));
      expect(doc.pdfBytes, isNull);
      expect(doc.svgPages, isNotNull);
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
      final source = FontSource.none();
      final loaded = await source.load();
      expect(loaded, isEmpty);
    });
  });
}
