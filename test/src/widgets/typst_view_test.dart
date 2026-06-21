import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:typst_flutter/typst_flutter.dart';
import '../../mocks/typst_mocks.dart';

void main() {
  setUpAll(() {
    RustLib.initMock(api: FakeRustLibApi());
  });

  group('TypstView', () {
    testWidgets('renders SVG correctly from source with all constructor args', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(
              source: '= Hello',
              fonts: const FontSource.none(),
              files: const FileSource.none(),
              date: DateTime(2024),
              loadingBuilder: (ctx) => const Text('Loading...'),
              errorBuilder: (ctx, err) => Text('Err: $err'),
            ),
          ),
        ),
      );

      // Verify custom loading state
      expect(find.text('Loading...'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('didUpdateWidget recompiles when source inputs change', (
      tester,
    ) async {
      final customFonts = FontSource.bytes([
        Uint8List.fromList([1]),
      ]);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstView.source(source: 'Init')),
        ),
      );
      await tester.pumpAndSettle();

      // Update source
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstView.source(source: 'Updated')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);

      // Update fonts
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(source: 'Updated', fonts: customFonts),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Update files
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(
              source: 'Updated',
              fonts: customFonts,
              files: const FileSource.none(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Update date
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(
              source: 'Updated',
              fonts: customFonts,
              files: const FileSource.none(),
              date: DateTime(2024),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Update pageIndex, renderMode, pixelsPerPt
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(
              source: 'Updated',
              fonts: customFonts,
              files: const FileSource.none(),
              date: DateTime(2024),
              renderMode: TypstRenderMode.raster,
              pixelsPerPt: 3,
            ),
          ),
        ),
      );
      // decodeImageFromPixels requires the real event loop to complete in
      //widget tests
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget); // Now raster!
    });

    testWidgets('didUpdateWidget re-renders when document inputs change', (
      tester,
    ) async {
      final compiler = await TypstCompiler.create();
      final doc = await compiler.compile(source: '= Doc');
      final doc2 = await compiler.compile(source: '= Doc2');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstView(document: doc)),
        ),
      );
      await tester.pumpAndSettle();

      // Change document
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypstView(document: doc2)),
        ),
      );
      await tester.pumpAndSettle();

      // Change render parameters
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView(
              document: doc2,
              renderMode: TypstRenderMode.raster,
              pixelsPerPt: 3,
            ),
          ),
        ),
      );
      // decodeImageFromPixels requires the real event loop to complete in
      //widget tests
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(RawImage), findsOneWidget);

      doc.dispose();
      doc2.dispose();
      compiler.dispose();
    });

    testWidgets('renders error overlay when compilation fails after success', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstView.source(source: '= Success first')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);

      // Now update to error
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: TypstView.source(source: 'error')),
        ),
      );
      await tester.pumpAndSettle();

      // SvgPicture should still be there, but with error overlay
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.textContaining('Simulated error'), findsOneWidget);
    });

    testWidgets('disposes owned compiler when provider is added', (
      tester,
    ) async {
      final key = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(key: key, source: '= Init'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final compiler = await TypstCompiler.create();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCompilerProvider(
              compiler: compiler,
              child: TypstView.source(key: key, source: '= Updated'),
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
      final failingFonts = FailingFontSource();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstView.source(source: 'source', fonts: failingFonts),
          ),
        ),
      );

      await tester.pumpAndSettle();
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
                    ? const TypstView.source(source: 'delayed')
                    : const SizedBox(),
              ),
            );
          },
        ),
      );

      await tester.pump();

      show = false;
      setLocalState?.call(() {});
      await tester.pump();

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
                    ? const TypstView.source(source: 'error')
                    : const SizedBox(),
              ),
            );
          },
        ),
      );

      await tester.pump();

      show = false;
      setLocalState?.call(() {});
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 200));
    });

    testWidgets('throws TypstCompileException if page index is out of bounds', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TypstView.source(source: '= Out of bounds', pageIndex: 99),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.textContaining('Page index out of bounds'), findsOneWidget);
    });
  });

  group('TypstView - Coverage Tests', () {
    testWidgets('bails out safely if unmounted during renderRaster', (
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
                    ? const TypstView.source(
                        source: 'dummy',
                        renderMode: TypstRenderMode.raster,
                        pixelsPerPt: 99,
                      )
                    : const SizedBox(),
              ),
            );
          },
        ),
      );

      await tester.runAsync(() async {
        await tester.pump();
        show = false;
        setLocalState?.call(() {});
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('adds fonts to provider if available', (tester) async {
      final compiler = await TypstCompiler.create();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TypstCompilerProvider(
              compiler: compiler,
              child: const TypstView.source(
                source: 'fonts',
                fonts: FontSource.bytes([]),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      compiler.dispose();
    });

    testWidgets(
      'didUpdateWidget re-renders when document pixelsPerPt changes',
      (tester) async {
        var pixelsPerPt = 2.0;
        StateSetter? setLocalState;
        final doc = TypstDocument.fromInner(FakeCompiledDocument());

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              setLocalState = setState;
              return MaterialApp(
                home: Scaffold(
                  body: TypstView(
                    document: doc,
                    renderMode: TypstRenderMode.raster,
                    pixelsPerPt: pixelsPerPt,
                  ),
                ),
              );
            },
          ),
        );

        await tester.runAsync(() async {
          await tester.pump();
        });

        pixelsPerPt = 3.0;
        setLocalState?.call(() {});
        await tester.runAsync(() async {
          await tester.pump();
        });

        doc.dispose();
      },
    );

    testWidgets('didUpdateWidget re-renders when source pixelsPerPt changes', (
      tester,
    ) async {
      var pixelsPerPt = 2.0;
      StateSetter? setLocalState;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            setLocalState = setState;
            return MaterialApp(
              home: Scaffold(
                body: TypstView.source(
                  source: 'hello',
                  renderMode: TypstRenderMode.raster,
                  pixelsPerPt: pixelsPerPt,
                ),
              ),
            );
          },
        ),
      );

      await tester.runAsync(() async {
        await tester.pump();
      });

      pixelsPerPt = 3.0;
      setLocalState?.call(() {});
      await tester.runAsync(() async {
        await tester.pump();
      });
    });
  });
}
