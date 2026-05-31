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

#### `Future<void> addFonts(FontSource fonts)`

Adds additional fonts to an already initialized compiler.

#### `Future<TypstDocument> compile({required String source, FileSource? files, DateTime? date})`

Compiles the Typst `source` into an opaque `TypstDocument` handle. The compiled document lives in Rust memory, ensuring extremely fast metadata access and eliminating race conditions.

#### `void dispose()`

Releases the native resources associated with the compiler.

---

### `TypstDocument`

An opaque handle to the compiled document living in Rust memory. All rendering and export operations are lazy.

- `int get pageCount`: The total number of pages in the compiled document.
- `Future<PageInfo> pageInfo(int pageIndex)`: Gets the dimensions of a specific page in points (pt).
- `Future<Uint8List> exportPdf()`: Exports the entire document to a raw PDF byte array.
- `Future<String> renderSvg(int pageIndex)`: Exports a specific page to an SVG string.
- `Future<TypstRenderResult> renderRaster({required int pageIndex, double pixelsPerPt = 2.0})`: Renders a specific page to raw RGBA pixels.
- `void dispose()`: Eagerly releases the native memory held by the Rust `PagedDocument`.

---

### `TypstRenderResult`

The result of rendering a Typst document page to a raster image.

- `Uint8List bytes`: Raw RGBA pixel data.
- `int width`: Width of the rendered image in pixels.
- `int height`: Height of the rendered image in pixels.
- `Future<ui.Image> toImage()`: Decodes the raw RGBA pixels into a cached Flutter `ui.Image`.
- `Future<Uint8List> toPng()`: Encodes the raw RGBA pixels as a self-contained PNG byte array.
- `void dispose()`: Releases the cached Flutter `ui.Image` if it exists.

---

### `FontSource` & `FileSource`

Abstractions for loading custom assets into the compiler.

- `FontSource.none()` / `FileSource.none()`: No additional assets.
- `FontSource.assets(...)` / `FileSource.assets(...)`: Loads files directly from Flutter assets.
- `FontSource.bytes(...)` / `FileSource.bytes(...)`: Loads files from raw memory buffers.

---

### `TypstDiagnostic`

When compilation fails, the compiler throws a `TypstCompileException` which contains a list of `TypstDiagnostic` objects. These provide structured error information, perfect for showing squiggly red lines in a code editor.

- `String get message`: The human-readable error description.
- `String get severity`: The severity (e.g. `error`, `warning`).
- `List<String> get hints`: Additional hints to help fix the error.

## Widgets

### `TypstDocumentViewer`

A high-level, production-ready widget for displaying scrollable Typst documents.

```dart
// Option 1: Self-managed compilation
TypstDocumentViewer(
  source: "= Hello",
  renderMode: TypstRenderMode.svg, // .svg or .raster
)

// Option 2: From a pre-compiled document
TypstDocumentViewer.document(
  document: myTypstDoc,
  renderMode: TypstRenderMode.raster,
)
```

### `TypstView`

A widget that renders exactly one page of a Typst document. Useful for custom paging logic.

```dart
TypstView(
  document: myTypstDoc,
  pageIndex: 0,
  renderMode: TypstRenderMode.svg,
)
```
