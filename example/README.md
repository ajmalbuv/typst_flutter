# typst_flutter_example

This directory contains a complete, runnable Flutter application demonstrating the `typst_flutter` package.

## Running the Example

Because `typst_flutter` is zero-configuration, you do not need to install Rust or run any setup scripts to test the example.

Simply run:

```bash
flutter run
```

The native build systems will automatically fetch the required prebuilt Typst binaries for your target architecture in the background.

## What it demonstrates

- Initializing the `TypstCompiler` with embedded font assets.
- Using the `TypstDocumentViewer` widget for a scrollable, cached PDF preview UI.
- Rendering pages as `ui.Image` pixels or crisp SVGs.
- Handling compiler errors elegantly using the `TypstDiagnostic` class.
