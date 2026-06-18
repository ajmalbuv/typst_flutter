---
title: Getting Started
description: How to install and start using typst_flutter
---

`typst_flutter` is the easiest way to bring professional typesetting to your Flutter apps. Because it utilizes prebuilt Rust binaries, you don't even need a Rust toolchain to get started.

## Installation

Add the package to your Flutter project's `pubspec.yaml`:

```bash
flutter pub add typst_flutter
```

## Zero-Configuration Setup

That's it! You're completely done.

When you run `flutter build` or `flutter run`, the native Android Gradle and iOS CocoaPods build systems will automatically fetch the required prebuilt native libraries (about 15MB) in the background.

## Default Built-in Fonts

By default, the compiler is lightweight but comes bundled with the following core fonts to ensure your basic documents and math formulas render perfectly out of the box:

- **Libertinus Serif** (Regular) - The default serif font for Typst.
- **DejaVu Sans Mono** - The default monospaced font for code blocks.
- **NewCM Math** (Book) - The default font for rendering complex mathematical formulas.

If you need additional fonts (e.g., custom brand fonts or emoji fonts), you can pass them via the `FontSource` API when calling `TypstCompiler.create()`.

## Basic Usage (PDF Generation)

Use `TypstCompiler.create()` to initialize the engine, and pass your Typst source code to compile a high-quality PDF:

```dart
import 'package:typst_flutter/typst_flutter.dart';

// 1. Initialize the compiler (loads the native binaries)
final compiler = await TypstCompiler.create();

// 2. Compile your source code to an opaque handle
final doc = await compiler.compile(
  source: r'''
    #set page(width: 148mm, height: 210mm, margin: 1cm)

    = Hello Typst!

    This is rendered *natively* in Flutter.
  ''',
);

// 3. Export to PDF bytes
final pdfBytes = await doc.exportPdf();

print('Generated a ${doc.pageCount}-page PDF (${pdfBytes.length} bytes).');

// Don't forget to dispose the document when you're done!
doc.dispose();
```

You can then pass `pdfBytes` to packages like `printing` or save it to the device's file system using `path_provider`.

## Live Preview Widget

If you want to display Typst documents directly in your UI (like a real-time editor), use the `TypstDocumentViewer` widget. It automatically manages the compilation lifecycle.

```dart
import 'package:flutter/material.dart';
import 'package:typst_flutter/typst_flutter.dart';

class TypstPreview extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return TypstDocumentViewer(
      source: r'''
        = Multi-page Viewer
        This document spans multiple pages.
        #pagebreak()
        And scrolling is instantly fast because the document handle is immutable!
      ''',
      renderMode: TypstRenderMode.svg, // Use SVG for crisp vector rendering
    );
  }
}
```

## Advanced: Compiling from Source

If you are building for an unsupported architecture, or building offline, the auto-download mechanism will gracefully fail. In this case, the build will fall back to **Cargokit**, which will compile the Rust core from scratch.

To use the source-compilation fallback, you must install [Rust](https://rustup.rs/) on your build machine. First-time compilation will take 5–15 minutes depending on your CPU.
