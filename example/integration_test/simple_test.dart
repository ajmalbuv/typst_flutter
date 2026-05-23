import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:typst_flutter/typst_flutter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('TypstCompiler', () {
    late TypstCompiler compiler;

    setUpAll(() async {
      compiler = await TypstCompiler.create();
    });

    test('compilerVersion returns non-empty string', () async {
      final version = await compiler.compilerVersion;
      expect(version, isNotEmpty);
    });

    test('compile() produces valid PDF bytes', () async {
      final doc = await compiler.compile(source: '= Hello, Typst!');
      // PDF files start with the %PDF- header
      expect(doc.pdf.length, greaterThan(100));
      expect(doc.pageCount, equals(1));
    });

    test('compile() sets correct pageCount', () async {
      final doc = await compiler.compile(
        source: '= Page 1\n#pagebreak()\n= Page 2',
      );
      expect(doc.pageCount, equals(2));
    });

    test('compile() exposes structured TypstDiagnostic', () async {
      try {
        await compiler.compile(source: '#invalid_xyz()');
        fail('Should have thrown TypstCompileException');
      } on TypstCompileException catch (e) {
        expect(e.diagnostics.length, greaterThan(0));
        expect(e.diagnostics.first.severity, equals('error'));
        expect(e.diagnostics.first.message, contains('invalid_xyz'));
      }
    });

    test('renderPage() returns raw RGBA pixels', () async {
      final result = await compiler.renderPage(
        source: '= Hello',
        pixelsPerPt: 1,
      );
      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
      // 4 bytes per pixel (RGBA)
      expect(result.bytes.length, equals(result.width * result.height * 4));
    });

    test('compileSvg() produces valid SVG strings', () async {
      final doc = await compiler.compileSvg(source: '= Hello, Typst!');
      expect(doc.svgs, isNotEmpty);
      expect(doc.svgs.first, contains('<svg'));
      expect(doc.pageCount, equals(1));
    });

    test('compileDocument() caching works for SVG renders', () async {
      final count = await compiler.compileDocument(
        source: '= P1\n#pagebreak()\n= P2',
        date: DateTime.utc(2025),
      );
      expect(count, equals(2));

      final svg0 = await compiler.renderCachedPageAsSvg();
      expect(svg0, contains('<svg'));

      final svg1 = await compiler.renderCachedPageAsSvg(pageIndex: 1);
      expect(svg1, contains('<svg'));
    });

    testWidgets('TypstDocumentViewer renders without throwing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(
              source: '= Flutter + Typst Document Viewer',
              date: DateTime.now(),
            ),
          ),
        ),
      );
      // Allow async compilation to complete
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(TypstDocumentViewer), findsOneWidget);
    });
  });
}
