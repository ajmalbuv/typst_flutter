import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/typst_flutter.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Standard single-page fake that succeeds on all operations.
class FakeCompiledDocument extends Fake implements api.CompiledDocument {
  bool disposed = false;
  int disposeCallCount = 0;

  /// Records the last pixelPerPt passed to [renderPage].
  double? lastPixelPerPt;

  @override
  BigInt pageCount() => BigInt.from(1);

  @override
  List<api.TypstDiagnostic> warnings() => const [
    api.TypstDiagnostic(
      severity: api.TypstSeverity.warning,
      message: 'Test warning',
      hints: [],
    ),
  ];

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
  }) async {
    lastPixelPerPt = pixelPerPt;
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── TypstDocument ──────────────────────────────────────────────────────

  group('TypstDocument', () {
    // -- Construction ---------------------------------------------------

    test('fromInner constructor creates a valid document', () {
      final inner = FakeCompiledDocument();
      final doc = TypstDocument.fromInner(inner);

      expect(doc, isNotNull);
      expect(doc, isA<TypstDocument>());
    });

    // -- pageCount ------------------------------------------------------

    test('pageCount returns the correct value for a single-page document', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(doc.pageCount, equals(1));
    });

    test('warnings returns inner warnings', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      final warnings = doc.warnings;
      expect(warnings.length, equals(1));
      expect(warnings.first.message, equals('Test warning'));
    });

    test('pageCount returns the correct value for a multi-page document', () {
      final doc = TypstDocument.fromInner(MultiPageCompiledDocument());
      expect(doc.pageCount, equals(3));
    });

    // -- dispose() ------------------------------------------------------

    test('dispose() calls inner.dispose()', () {
      final inner = FakeCompiledDocument();
      final doc = TypstDocument.fromInner(inner);

      expect(inner.disposed, isFalse);
      doc.dispose();
      expect(inner.disposed, isTrue);
    });

    test('dispose() is idempotent — inner.dispose() called only once', () {
      final inner = FakeCompiledDocument();
      TypstDocument.fromInner(inner)
        ..dispose()
        ..dispose()
        ..dispose();

      expect(inner.disposeCallCount, equals(1));
    });

    // -- pageInfo -------------------------------------------------------

    test('pageInfo returns correct dimensions', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      final info = doc.pageInfo(0);

      expect(info.widthPt, equals(200));
      expect(info.heightPt, equals(300));
    });

    test('pageInfo returns index-dependent dimensions for multi-page doc', () {
      final doc = TypstDocument.fromInner(MultiPageCompiledDocument());

      final info0 = doc.pageInfo(0);
      expect(info0.widthPt, equals(100));
      expect(info0.heightPt, equals(200));

      final info1 = doc.pageInfo(1);
      expect(info1.widthPt, equals(200));
      expect(info1.heightPt, equals(400));

      final info2 = doc.pageInfo(2);
      expect(info2.widthPt, equals(300));
      expect(info2.heightPt, equals(600));
    });

    test('pageInfo throws RangeError for negative index', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.pageInfo(-1), throwsRangeError);
    });

    test('pageInfo throws RangeError for index equal to pageCount', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.pageInfo(1), throwsRangeError);
    });

    test('pageInfo throws RangeError for index greater than pageCount', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.pageInfo(99), throwsRangeError);
    });

    test('pageInfo throws StateError after dispose', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument())..dispose();
      expect(() => doc.pageInfo(0), throwsStateError);
    });

    // -- exportPdf ------------------------------------------------------

    test('exportPdf returns PDF bytes', () async {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      final pdf = await doc.exportPdf();

      expect(pdf, isA<Uint8List>());
      expect(pdf, equals(Uint8List.fromList([1, 2, 3, 4])));
    });

    test('exportPdf throws StateError after dispose', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument())..dispose();

      expect(doc.exportPdf, throwsStateError);
    });

    test('exportPdf wraps inner errors as TypstRenderException', () {
      final doc = TypstDocument.fromInner(FailingCompiledDocument());

      expect(
        doc.exportPdf,
        throwsA(
          isA<TypstRenderException>().having(
            (e) => e.message,
            'message',
            contains('PDF export failed'),
          ),
        ),
      );
    });

    // -- renderSvg ------------------------------------------------------

    test('renderSvg returns SVG string', () async {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      final svg = await doc.renderSvg(0);

      expect(svg, equals('<svg>1</svg>'));
    });

    test('renderSvg throws RangeError for negative index', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.renderSvg(-1), throwsRangeError);
    });

    test('renderSvg throws RangeError for index >= pageCount', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.renderSvg(1), throwsRangeError);
    });

    test('renderSvg throws StateError after dispose', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument())..dispose();

      expect(() => doc.renderSvg(0), throwsStateError);
    });

    test('renderSvg wraps inner errors as TypstRenderException', () {
      final doc = TypstDocument.fromInner(FailingCompiledDocument());

      expect(
        () => doc.renderSvg(0),
        throwsA(
          isA<TypstRenderException>().having(
            (e) => e.message,
            'message',
            contains('SVG failed'),
          ),
        ),
      );
    });

    // -- renderRaster ---------------------------------------------------

    test(
      'renderRaster returns TypstRenderResult with correct fields',
      () async {
        final doc = TypstDocument.fromInner(FakeCompiledDocument());
        final result = await doc.renderRaster(pageIndex: 0);

        expect(result, isA<TypstRenderResult>());
        expect(result.index, equals(0));
        expect(result.width, equals(100));
        expect(result.height, equals(100));
        expect(result.bytes.length, equals(100 * 100 * 4));
        // All pixels are 0xFF (white/opaque) from the fake
        expect(result.bytes.every((b) => b == 255), isTrue);
      },
    );

    test('renderRaster throws RangeError for negative index', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.renderRaster(pageIndex: -1), throwsRangeError);
    });

    test('renderRaster throws RangeError for index >= pageCount', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument());
      expect(() => doc.renderRaster(pageIndex: 1), throwsRangeError);
    });

    test('renderRaster throws StateError after dispose', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument())..dispose();

      expect(() => doc.renderRaster(pageIndex: 0), throwsStateError);
    });

    test('renderRaster wraps inner errors as TypstRenderException', () {
      final doc = TypstDocument.fromInner(FailingCompiledDocument());

      expect(
        () => doc.renderRaster(pageIndex: 0),
        throwsA(
          isA<TypstRenderException>().having(
            (e) => e.message,
            'message',
            contains('Render failed'),
          ),
        ),
      );
    });

    test('renderRaster passes default pixelsPerPt (2.0) to inner', () async {
      final inner = FakeCompiledDocument();
      final doc = TypstDocument.fromInner(inner);

      await doc.renderRaster(pageIndex: 0);
      expect(inner.lastPixelPerPt, equals(2.0));
    });

    test('renderRaster passes custom pixelsPerPt to inner', () async {
      final inner = FakeCompiledDocument();
      final doc = TypstDocument.fromInner(inner);

      await doc.renderRaster(pageIndex: 0, pixelsPerPt: 3.5);
      expect(inner.lastPixelPerPt, equals(3.5));
    });

    test('renderRaster passes very low pixelsPerPt to inner', () async {
      final inner = FakeCompiledDocument();
      final doc = TypstDocument.fromInner(inner);

      await doc.renderRaster(pageIndex: 0, pixelsPerPt: 0.5);
      expect(inner.lastPixelPerPt, equals(0.5));
    });

    // -- StateError message verification --------------------------------

    test('StateError after dispose contains helpful message', () {
      final doc = TypstDocument.fromInner(FakeCompiledDocument())..dispose();

      expect(
        () => doc.pageInfo(0),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('already been disposed'),
          ),
        ),
      );
    });
  });

  // ── TypstRenderResult ──────────────────────────────────────────────────

  group('TypstRenderResult', () {
    test('constructor stores all fields correctly', () {
      final bytes = Uint8List.fromList([10, 20, 30, 40]);
      final result = TypstRenderResult(
        index: 2,
        bytes: bytes,
        width: 640,
        height: 480,
      );

      expect(result.index, equals(2));
      expect(result.bytes, same(bytes));
      expect(result.width, equals(640));
      expect(result.height, equals(480));
    });

    test('constructor stores zero-sized dimensions', () {
      final result = TypstRenderResult(
        index: 0,
        bytes: Uint8List(0),
        width: 0,
        height: 0,
      );

      expect(result.index, equals(0));
      expect(result.bytes.length, equals(0));
      expect(result.width, equals(0));
      expect(result.height, equals(0));
    });

    test(
      'dispose() can be called without prior toImage() (no-op, no crash)',
      () {
        final result = TypstRenderResult(
          index: 0,
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          width: 1,
          height: 1,
        );

        // Should not throw — _cachedImage is null, dispose is a no-op.
        expect(result.dispose, returnsNormally);
      },
    );

    test('dispose() can be called multiple times safely', () {
      final result = TypstRenderResult(
        index: 0,
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        width: 1,
        height: 1,
      );

      expect(() {
        result
          ..dispose()
          ..dispose()
          ..dispose();
      }, returnsNormally);
    });

    test('fields are immutable after construction', () {
      final bytes = Uint8List.fromList([0, 0, 0, 255]);
      final result = TypstRenderResult(
        index: 0,
        bytes: bytes,
        width: 1,
        height: 1,
      );

      // Verify that accessing fields returns the same values consistently.
      expect(result.index, equals(0));
      expect(result.width, equals(1));
      expect(result.height, equals(1));
      expect(result.bytes, same(bytes));

      // Access again — still the same.
      expect(result.index, equals(0));
      expect(result.width, equals(1));
      expect(result.height, equals(1));
      expect(result.bytes, same(bytes));
    });

    test('toImage() decodes raw bytes and caches result', () async {
      final bytes = Uint8List.fromList([255, 0, 0, 255]); // 1x1 red pixel
      final result = TypstRenderResult(
        index: 0,
        bytes: bytes,
        width: 1,
        height: 1,
      );

      final image1 = await result.toImage();
      expect(image1.width, equals(1));
      expect(image1.height, equals(1));

      final image2 = await result.toImage();
      expect(identical(image1, image2), isTrue); // Should be cached

      result.dispose(); // Should dispose the cached image
    });

    test('toPng() encodes ad-hoc if not cached', () async {
      final bytes = Uint8List.fromList([255, 0, 0, 255]);
      final result = TypstRenderResult(
        index: 0,
        bytes: bytes,
        width: 1,
        height: 1,
      );

      final pngBytes = await result.toPng();
      expect(pngBytes, isNotEmpty);
      // It should self-dispose since it was ad-hoc
    });

    test('toPng() reuses cached image if available', () async {
      final bytes = Uint8List.fromList([255, 0, 0, 255]);
      final result = TypstRenderResult(
        index: 0,
        bytes: bytes,
        width: 1,
        height: 1,
      );

      await result.toImage(); // Cache the image
      final pngBytes = await result.toPng();

      expect(pngBytes, isNotEmpty);
      result.dispose();
    });
  });
}
