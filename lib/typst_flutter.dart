/// Native Typst typesetting compiler for Flutter.
///
/// Compiles [Typst](https://typst.app) markup natively via Rust FFI —
/// no WASM, no WebView, no server, no subprocess.
///
/// ### Quick start
/// ```dart
/// // 1. Compile to PDF
/// final compiler = await TypstCompiler.create();
/// final doc = await compiler.compile(source: r'= Hello, Typst!');
/// // doc.pdf is a Uint8List of raw PDF bytes
///
/// // 2. Render a page as a Flutter widget (live reload)
/// TypstView(source: myMarkupString)
/// ```
library;

export 'src/compiler.dart';
export 'src/document.dart';
export 'src/exceptions.dart';
export 'src/files.dart';
export 'src/fonts.dart';
export 'src/rust/api/typst.dart'
    show PageInfo, TypstDiagnostic, TypstSeverity, TypstSourceLocation;
export 'src/widgets/typst_compiler_provider.dart';
export 'src/widgets/typst_document_viewer.dart';
export 'src/widgets/typst_view.dart';
