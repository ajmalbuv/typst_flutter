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
      final version = compiler.compilerVersion;
      expect(version, isNotEmpty);
    });

    test('compile() produces valid PDF bytes', () async {
      final doc = await compiler.compile(source: '= Hello, Typst!');
      final pdf = await doc.exportPdf();
      // PDF files start with the %PDF- header
      expect(pdf.length, greaterThan(100));
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
        expect(e.diagnostics.first.severity, equals(TypstSeverity.error));
        expect(e.diagnostics.first.message, contains('invalid_xyz'));
      }
    });

    test('renderRaster() returns raw RGBA pixels', () async {
      final doc = await compiler.compile(source: '= Hello');
      final result = await doc.renderRaster(pageIndex: 0, pixelsPerPt: 1);
      expect(result.width, greaterThan(0));
      expect(result.height, greaterThan(0));
      // 4 bytes per pixel (RGBA)
      expect(result.bytes.length, equals(result.width * result.height * 4));
    });

    test('renderSvg() produces valid SVG strings', () async {
      final doc = await compiler.compile(source: '= Hello, Typst!');
      final svg = await doc.renderSvg(0);
      expect(svg, contains('<svg'));
      expect(doc.pageCount, equals(1));
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
