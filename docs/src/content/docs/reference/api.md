---
title: API & Widgets
description: Reference documentation for the typst_flutter package.
---

## Core Classes

### `TypstCompiler`

The main entry point for interacting with the Typst engine via Rust FFI.

#### `Future<TypstCompiler> create({FontSource? fonts})`

Initializes the compiler and loads the native libraries into memory.
You can optionally provide a `FontSource` to load custom fonts.

#### `Future<TypstDocument> compile({required String source})`

Compiles the Typst `source` into a PDF. Returns a `TypstDocument` containing the raw PDF bytes.

#### `Future<TypstDocument> renderPage({required String source, int pageIndex = 0, double pixelsPerPt = 2.0})`

Compiles the document and renders a specific page as a raw RGBA image buffer (useful for high-performance custom painting).

---

### `TypstDocument`

Represents the result of a successful compilation.

- `Uint8List get pdf`: The raw bytes of the generated PDF document.
- `int get pageCount`: The total number of pages in the compiled document.
- `Future<ui.Image> imageForPage(int pageIndex)`: Retrieves the rendered image of a specific page.

---

### `FontSource`

An abstraction for loading custom fonts into the compiler.

- `FontSource.none()`: Uses only Typst's built-in fonts.
- `FontSource.assets(List<String> assetPaths)`: Loads font files directly from Flutter assets.
- `FontSource.bytes(List<Uint8List> data)`: Loads fonts from raw memory buffers.

---

### `TypstDiagnostic`

When compilation fails, the compiler throws a `TypstCompileException` which contains a list of `TypstDiagnostic` objects. These provide structured error information, perfect for showing squiggly red lines in a code editor.

- `String get message`: The human-readable error description.
- `String get severity`: The severity (e.g. `error`, `warning`).
- `int? get line`: The 1-indexed line number where the error occurred.

## Widgets

### `TypstDocumentViewer`

A high-level, production-ready widget for displaying scrollable Typst documents.

```dart
TypstDocumentViewer(
  source: "= Hello",
  useSvg: true, // true for crisp SVG vector text, false for fast raster images
)
```

### `TypstView`

A lower-level widget that renders exactly one page of a Typst document. Useful for custom paging logic.
