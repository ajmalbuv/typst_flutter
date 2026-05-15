# typst_flutter

[![Pub Version](https://img.shields.io/pub/v/typst_flutter)](https://pub.dev/packages/typst_flutter)
[![Pub Points](https://img.shields.io/pub/points/typst_flutter)](https://pub.dev/packages/typst_flutter)
[![style: very good analysis](https://img.shields.io/badge/style-very_good_analysis-B22C89.svg)](https://pub.dev/packages/very_good_analysis)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

Embed the **Typst typesetting compiler** natively into your Flutter apps via Rust FFI.

Compile Typst markup to high-quality PDF documents or rendered images on Android, iOS, macOS, Windows, and Linux. No WASM overhead, no WebView, no server required.

## Features

- **Native performance:** Typst runs directly on the device using a Rust core.
- **Zero Rust required:** End-users can download pre-built native binaries via a simple Dart script.
- **Virtual File System:** Pass Flutter assets and raw bytes directly into the Typst compiler via `FileSource`.
- **Live Preview:** Included `TypstView` widget with debounced live-reload, perfect for building editors.

## Getting started

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  typst_flutter: ^1.0.0
```

### Install native binaries

To avoid compiling the Rust core from source (which requires a full Rust toolchain), run the setup script once to download the pre-built native libraries for your current platform:

```bash
dart run typst_flutter:setup
```

## Usage

### Rendering a PDF

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
// You can now save doc.pdf to disk or display it with printing/pdf packages.
```

### Displaying a live preview widget

The `TypstView` widget automatically recompiles and renders when the source or assets change.

```dart
import 'package:flutter/material.dart';
import 'package:typst_flutter/typst_flutter.dart';

class MyEditor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TypstView(
      source: r'''
        = Live Preview
        Change this text and see the updates instantly.
        
        #image("logo.png")
      ''',
      files: FileSource.assets({
        'logo.png': 'assets/images/my_logo.png',
      }),
      pixelsPerPt: 2.0, // crisp high-DPI rendering
    );
  }
}

## Testing

Because this package relies on native Rust libraries via FFI, tests must be run as integration tests against a host platform.

1. Ensure you have downloaded the native binaries for your host machine:
   ```bash
   dart run typst_flutter:setup
   ```
2. Run the integration tests using the flutter test command:
   ```bash
   flutter test integration_test/simple_test.dart
   ```

## Author

Ajmal (`ajmalbuv`)
