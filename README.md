# typst_flutter

[![CI](https://github.com/ajmalbuv/typst_flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/ajmalbuv/typst_flutter/actions/workflows/ci.yml)
[![Pub Version](https://img.shields.io/pub/v/typst_flutter)](https://pub.dev/packages/typst_flutter)
[![Documentation](https://img.shields.io/badge/docs-pub.dev-blue)](https://pub.dev/documentation/typst_flutter/latest/)
[![Pub Points](https://img.shields.io/pub/points/typst_flutter)](https://pub.dev/packages/typst_flutter)
[![codecov](https://codecov.io/gh/ajmalbuv/typst_flutter/graph/badge.svg)](https://codecov.io/gh/ajmalbuv/typst_flutter)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Embed the **Typst typesetting compiler** natively into your Flutter apps via Rust FFI.

Compile Typst markup to high-quality PDF documents or rendered images on Android, iOS, macOS, Windows, and Linux. No WASM overhead, no WebView, no server required.

## Links

- **Documentation:** [pub.dev/documentation/typst_flutter](https://pub.dev/documentation/typst_flutter/latest/)
- **GitHub:** [github.com/ajmalbuv/typst_flutter](https://github.com/ajmalbuv/typst_flutter)
- **Pub.dev:** [pub.dev/packages/typst_flutter](https://pub.dev/packages/typst_flutter)

## Features

- **Native Performance:** Typst runs directly on the device using a Rust core, compiling most documents in under 100ms.
- **Opaque Handle Architecture:** Compiled documents live in Rust memory, ensuring high performance and zero race conditions.
- **Shared Compiler Architecture:** Use `TypstCompilerProvider` to reuse a single engine globally across your widget tree for 0ms overhead rendering.
- **Data Extraction:** Native `query()` API to extract JSON metadata and document structure using Typst selectors.
- **Widgets Included:** Drop-in `TypstDocumentViewer` and `TypstView` widgets for instant live previews with Raster or SVG support.
- **Structured Error Handling:** Get detailed `TypstDiagnostic` error lines when Typst compilation fails, perfect for building in-app editors.
- **Virtual File System & Inputs:** Pass Flutter assets, raw memory bytes, and `sys.inputs` dictionaries directly into the Typst compiler.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  typst_flutter: ^2.0.0
```

Then fetch dependencies and run the **required** one-time setup:

```bash
flutter pub get
dart run typst_flutter:setup
```

> **Why is this required?**
> `typst_flutter` ships a native Rust library (~15MB per ABI). Because pub.dev has a 100MB size limit, the pre-built binaries live on GitHub Releases. The setup script downloads the correct binaries for your platform and places them where the Flutter build system expects them.
>
> You only need to run this once per version upgrade.

> **Tip:** The native build systems (Gradle, CocoaPods, CMake) will try to run `dart run typst_flutter:setup` automatically at build time if binaries are missing. This is best-effort — if it fails for any reason, just run it manually from your app root and rebuild.

## Usage

### Rendering a PDF

Use `TypstCompiler.create()` to initialize the engine and build documents:

```dart
import 'package:typst_flutter/typst_flutter.dart';

final compiler = await TypstCompiler.create();

// Compile to an opaque document handle
final doc = await compiler.compile(
  source: r'''
    #set page(width: 148mm, height: 210mm, margin: 1cm)
    = Hello Typst!

    This is rendered *natively* in Flutter.
    #sys.inputs.at("theme", default: "light")
  ''',
  inputs: {'theme': 'dark'}, // Safely pass variables to Typst
);

// Query metadata/structure from the compiled document
final headingJson = await compiler.query(document: doc, selector: '<heading>');

// Export to PDF bytes
final pdfBytes = await doc.exportPdf();

print('Generated a ${doc.pageCount}-page PDF (${pdfBytes.length} bytes).');
// You can now save pdfBytes to disk or share it!

// Don't forget to dispose the document handle
doc.dispose();
```

### Live Preview Widget

The `TypstDocumentViewer` widget automatically compiles and renders your document, providing a scrollable, zoomable UI.

```dart
import 'package:flutter/material.dart';
import 'package:typst_flutter/typst_flutter.dart';

class MyEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TypstDocumentViewer(
      source: r'''
        = Multi-page Viewer
        This document spans multiple pages.
        #pagebreak()
        And scrolling is instantly fast because the document handle is immutable!
      ''',
      renderMode: TypstRenderMode.svg, // Use SVG for crisp vector text
    );
  }
}
```

### Shared Compiler Performance (Best Practice)

To avoid spawning a new Rust thread for every widget, wrap your app or page in a `TypstCompilerProvider`. Any `TypstView` or `TypstDocumentViewer` underneath will automatically discover and reuse the shared compiler instantly!

```dart
// 1. Initialize once
final compiler = await TypstCompiler.create();

// 2. Wrap your app
TypstCompilerProvider(
  compiler: compiler,
  child: Scaffold(
    body: ListView(
      children: [
        // 3. These render instantly using the shared engine!
        TypstView.source(source: '$ x^2 + y^2 = r^2 $'),
        TypstView.source(source: '$ e^(i pi) + 1 = 0 $'),
      ],
    )
  )
)
```

## Advanced Fallback (Cargokit)

If you are building for a custom architecture or operating completely offline, the auto-download mechanism will gracefully fail and fall back to compiling the Rust core from source using **Cargokit**.

_Note: Source compilation requires a full Rust toolchain (`rustup`) installed on your build machine and may take 5–15 minutes on the first run._

## Testing

Because this package relies on native Rust libraries via FFI, unit tests must be run as integration tests against a host platform.

```bash
flutter test integration_test/simple_test.dart
```

## Author

Ajmal ([@ajmalbuv](https://github.com/ajmalbuv))
