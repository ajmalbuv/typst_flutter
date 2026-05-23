# typst_flutter

[![Pub Version](https://img.shields.io/pub/v/typst_flutter)](https://pub.dev/packages/typst_flutter)
[![Pub Points](https://img.shields.io/pub/points/typst_flutter)](https://pub.dev/packages/typst_flutter)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Embed the **Typst typesetting compiler** natively into your Flutter apps via Rust FFI.

Compile Typst markup to high-quality PDF documents or rendered images on Android, iOS, macOS, Windows, and Linux. No WASM overhead, no WebView, no server required.

## Features

- **Native Performance:** Typst runs directly on the device using a Rust core, compiling most documents in under 100ms.
- **Widgets Included:** Drop-in `TypstDocumentViewer` and `TypstView` widgets for instant live previews.
- **Structured Error Handling:** Get detailed `TypstDiagnostic` error lines when Typst compilation fails, perfect for building in-app editors.
- **Virtual File System:** Pass Flutter assets and raw memory bytes directly into the Typst compiler via `FontSource`.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  typst_flutter: ^1.0.0
```

That's it! When you run `flutter build` or `flutter run`, the platform build scripts (Gradle/CocoaPods) will automatically fetch the correct native binaries for your architecture in the background.

## Usage

### Rendering a PDF

Use `TypstCompiler.create()` to initialize the engine and build documents:

```dart
import 'package:typst_flutter/typst_flutter.dart';

final compiler = await TypstCompiler.create();

final doc = await compiler.compile(
  source: r'''
    #set page(width: 148mm, height: 210mm, margin: 1cm)
    = Hello Typst!

    This is rendered *natively* in Flutter.
  ''',
);

print('Generated a ${doc.pageCount}-page PDF (${doc.pdf.length} bytes).');
// You can now save doc.pdf to disk or share it!
```

### Live Preview Widget

The `TypstDocumentViewer` widget automatically compiles and renders your document, providing a scrollable, zoomable UI. It caches compiled pages internally for butter-smooth scrolling.

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
        And scrolling is instantly fast because the document is cached!
      ''',
      useSvg: true, // Use SVG for crisp vector text
    );
  }
}
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
