import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:typst_flutter/typst_flutter.dart';

class _FailingFontSource extends FontSource {
  @override
  Future<List<Uint8List>> load() async => throw Exception('Generic font error');
  @override
  List<Object?> get props => [];
}

class FakeCompiledDocument extends Fake implements api.CompiledDocument {
  bool disposed = false;

  @override
  BigInt pageCount() => BigInt.from(3); // Simulate 3 pages

  @override
  api.PageInfo pageInfo({required BigInt index}) =>
      const api.PageInfo(widthPt: 200, heightPt: 300);

  @override
  Future<Uint8List> exportPdf() async => Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<String> exportSvg({required BigInt index}) async =>
      '<svg height="100" width="100"><circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="blue" /></svg>';

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
    if (markup == 'generic_error') {
      throw Exception('Generic error');
    }
    if (markup == 'delayed') {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return FakeCompiledDocument();
    }
    return FakeCompiledDocument();
  }

  @override
  Future<void> addFonts({required List<Uint8List> fontData}) async {}

  @override
  void dispose() {}
}

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

  group('TypstDocumentViewer', () {
    testWidgets('renders all pages from source', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstDocumentViewer(source: '= Hello')),
        ),
      );

      // Verify loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Wait for compilation and rendering
      await tester.pumpAndSettle();

      // Because the fake document has 3 pages, there should be 3 TypstViews
      // Actually, ListView.separated might only build visible ones,
      // but 3 should fit
      expect(find.byType(TypstView), findsWidgets);
    });

    testWidgets('renders error state when compilation fails', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstDocumentViewer(source: 'error')),
        ),
      );

      await tester.pumpAndSettle();

      // Verify error text is rendered
      expect(find.textContaining('Simulated error'), findsOneWidget);
    });

    testWidgets('uses TypstCompilerProvider if available', (tester) async {
      final compiler = await TypstCompiler.create();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCompilerProvider(
              compiler: compiler,
              child: const TypstDocumentViewer(source: '= Hello via provider'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.byType(TypstView), findsWidgets);
      compiler.dispose();
    });

    testWidgets('renders from pre-compiled document', (tester) async {
      final compiler = await TypstCompiler.create();
      final doc1 = await compiler.compile(source: '= Hello pre-compiled');
      final doc2 = await compiler.compile(source: '= Hello again');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstDocumentViewer.document(document: doc1)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TypstView), findsWidgets);

      // Trigger didUpdateWidget for document mode
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstDocumentViewer.document(document: doc2)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TypstView), findsWidgets);

      doc1.dispose();
      doc2.dispose();
      compiler.dispose();
    });

    testWidgets('didUpdateWidget recompiles when source changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstDocumentViewer(source: 'Init')),
        ),
      );
      await tester.pumpAndSettle();

      // Change source
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstDocumentViewer(source: 'Updated')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TypstView), findsWidgets);

      // Change fonts to trigger compiler reset
      final customFonts = FontSource.bytes([
        Uint8List.fromList([1]),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(source: 'Updated', fonts: customFonts),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TypstView), findsWidgets);

      // Change files
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(
              source: 'Updated',
              fonts: customFonts,
              files: const FileSource.none(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Change ONLY date to ensure the final || branch is evaluated
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(
              source: 'Updated',
              fonts: customFonts,
              files: const FileSource.none(),
              date: DateTime(2024),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TypstView), findsWidgets);
    });

    testWidgets('disposes owned compiler when provider is added', (
      tester,
    ) async {
      final key = GlobalKey();

      // Start WITHOUT provider
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(
              key: key,
              source: '= Init without provider',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Now wrap WITH provider, using same GlobalKey so state is preserved
      final compiler = await TypstCompiler.create();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCompilerProvider(
              compiler: compiler,
              child: TypstDocumentViewer(
                key: key,
                source: '= Updated with provider',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      compiler.dispose();
    });

    testWidgets('handles generic error gracefully via failing font source', (
      tester,
    ) async {
      // Create a font source that throws a generic exception
      final failingFonts = _FailingFontSource();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(source: 'source', fonts: failingFonts),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify generic error text is rendered
      expect(
        find.textContaining('Exception: Generic font error'),
        findsOneWidget,
      );
    });

    testWidgets('bails out safely if unmounted before compilation finishes', (
      tester,
    ) async {
      var show = true;
      StateSetter? setLocalState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setLocalState = setState;
            return MaterialApp(
              home: Scaffold(
                body: show
                    ? const TypstDocumentViewer(source: 'delayed')
                    : const SizedBox(),
              ),
            );
          },
        ),
      );
      await tester.pump();

      // Instantly unmount by rebuilding without the viewer
      show = false;
      setLocalState?.call(() {});
      await tester.pump();

      // Wait for the delayed future to complete so we trigger the !mounted
      // branch and ensure doc.dispose() is called safely.
      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('bails out safely if unmounted during typst exception', (
      tester,
    ) async {
      var show = true;
      StateSetter? setLocalState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setLocalState = setState;
            return MaterialApp(
              home: Scaffold(
                body: show
                    ? const TypstDocumentViewer(source: 'error')
                    : const SizedBox(),
              ),
            );
          },
        ),
      );

      // Start compilation
      await tester.pump();

      // Unmount
      show = false;
      setLocalState?.call(() {});
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('adds fonts to provider if available', (tester) async {
      final compiler = await TypstCompiler.create();
      final customFonts = FontSource.bytes([
        Uint8List.fromList([1]),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCompilerProvider(
              compiler: compiler,
              child: TypstDocumentViewer(
                source: '= Hello fonts',
                fonts: customFonts,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.byType(TypstView), findsWidgets);
      compiler.dispose();
    });

    testWidgets('bails out if unmounted before compilation finishes', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Navigator(
            onGenerateRoute: (settings) => MaterialPageRoute<void>(
              builder: (context) =>
                  const Scaffold(body: TypstDocumentViewer(source: 'delayed')),
            ),
          ),
        ),
      );
      await tester.pump();
      unawaited(
        tester
            .state<NavigatorState>(find.byType(Navigator).first)
            .pushReplacement(
              MaterialPageRoute<void>(builder: (context) => const SizedBox()),
            ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
      // No crashes should occur
    });

    testWidgets('separatorBuilder is executed', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TypstDocumentViewer(
              source: '= Separator test',
              pageSpacing: 20,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.height == 20),
        findsWidgets,
      );

      // Reset surface size
      await tester.binding.setSurfaceSize(null);
    });
  });
}
