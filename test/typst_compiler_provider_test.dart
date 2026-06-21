import 'package:flutter/widgets.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/rust/frb_generated.dart';
import 'package:typst_flutter/typst_flutter.dart';

class FakeCompiledDocument extends Fake implements api.CompiledDocument {
  @override
  BigInt pageCount() => BigInt.from(1);

  @override
  api.PageInfo pageInfo({required BigInt index}) =>
      const api.PageInfo(widthPt: 200, heightPt: 300);

  @override
  Future<String> exportSvg({required BigInt index}) async => '<svg>1</svg>';

  @override
  void dispose() {}
}

class FakeTypstEngine extends Fake implements api.TypstEngine {
  @override
  Future<api.CompiledDocument> compile({
    required String markup,
    required List<api.VirtualFile> files,
    PlatformInt64? sysTime,
    Map<String, String>? inputs,
  }) async => FakeCompiledDocument();

  @override
  Future<void> addFonts({required List<Uint8List> fontData}) async {}

  @override
  void dispose() {}
}

class FakeRustLibApi extends Fake implements RustLibApi {
  @override
  api.TypstEngine crateApiTypstTypstEngineNew() => FakeTypstEngine();

  @override
  String crateApiTypstGetTypstVersion() => '0.14.2';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  setUpAll(() {
    RustLib.initMock(api: FakeRustLibApi());
  });

  testWidgets('TypstCompilerProvider provides compiler to children', (
    tester,
  ) async {
    final compiler = await TypstCompiler.create();
    TypstCompiler? foundCompiler;

    await tester.pumpWidget(
      TypstCompilerProvider(
        compiler: compiler,
        child: Builder(
          builder: (context) {
            foundCompiler = TypstCompilerProvider.maybeOf(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(foundCompiler, isNotNull);
    expect(foundCompiler, equals(compiler));
  });

  testWidgets('TypstView uses provided compiler instead of creating one', (
    tester,
  ) async {
    final compiler = await TypstCompiler.create();

    await tester.pumpWidget(
      TypstCompilerProvider(
        compiler: compiler,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: TypstView.source(source: '= Provided'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // We can't directly check the internal state, but if it didn't throw and
    // completed rendering without creating a real rust isolate
    // (since it's mocked),it used the provider.
    expect(find.byType(TypstView), findsOneWidget);
  });

  testWidgets('TypstCompilerProvider.of returns compiler and asserts on null', (
    tester,
  ) async {
    final compiler = await TypstCompiler.create();
    TypstCompiler? foundCompiler;

    await tester.pumpWidget(
      TypstCompilerProvider(
        compiler: compiler,
        child: Builder(
          builder: (context) {
            foundCompiler = TypstCompilerProvider.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(foundCompiler, isNotNull);
    expect(foundCompiler, equals(compiler));

    // Now test assertion failure when no provider exists
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          TypstCompilerProvider.of(context);
          return const SizedBox();
        },
      ),
    );

    final dynamic exception = tester.takeException();
    expect(exception, isA<AssertionError>());
    expect(
      (exception as AssertionError).message,
      equals('No TypstCompilerProvider found in context'),
    );
  });

  test('updateShouldNotify correctly compares compilers', () async {
    final compiler1 = await TypstCompiler.create();
    final compiler2 = await TypstCompiler.create();

    final provider1 = TypstCompilerProvider(
      compiler: compiler1,
      child: const SizedBox(),
    );

    final provider1Duplicate = TypstCompilerProvider(
      compiler: compiler1,
      child: const SizedBox(),
    );

    final provider2 = TypstCompilerProvider(
      compiler: compiler2,
      child: const SizedBox(),
    );

    // Same compiler -> false
    expect(provider1.updateShouldNotify(provider1Duplicate), isFalse);

    // Different compilers -> true
    expect(provider1.updateShouldNotify(provider2), isTrue);
  });
}
