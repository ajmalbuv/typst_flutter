# Typst Flutter TODO

This document tracks remaining features required for full feature parity with `typst.ts` and advanced Flutter integration.

## 🟡 P1: Core Feature Parity

- [ ] **`query()` API**: Allow extracting structured data (headings, `#metadata()`, TOC) from a compiled document. (e.g. `await compiler.query('<heading>')`).

## 🟢 P2: Advanced Features

- [ ] **Incremental Compilation**: Keep `comemo` caches alive across compilations to achieve sub-100ms roundtrips for live typing in a full-blown text editor.
- [ ] **Typst Package Registry**: Add support for `#import "@preview/..."` by implementing a `PackageSource` in Dart and resolving `FileId::package()` in `SimpleWorld`.
- [ ] **Responsive / Theme-Aware Render**: Add support for passing theme/breakpoint variables down to the Typst engine without full text substitution.

## 🔵 P3: Accessibility & DX

- [ ] **Layered Text Selection**: Overlay selectable HTML/Flutter text nodes on top of the SVG/Canvas render to allow copy-paste, highlighting, and hyperlinks (like `typst.ts` does in the browser).
- [ ] **Dynamic Font Loading**: Support lazily fetching missing fonts as new scripts are encountered during compilation, rather than requiring all fonts upfront via `FontSource`.
- [ ] **Error Location Highlighting**: Map diagnostic spans back to line/column numbers so editors can highlight the exact text range causing the error.

# To CHECK

Let me fetch the actual source files directly via the pub.dev API and raw GitHub content.Good, I've now got a thorough picture of the full public API surface from the generated docs. Here's the source-level analysis:

---

## Source-level Issues

### 1. `TypstDocument` — dual PDF/SVG/Frame state with no type safety

`TypstDocument` has three factory constructors (`fromPdf`, `fromSvg`, `fromFrame`) but is a single flat class. Both `pdf` and `svgs` throw `StateError` at runtime if you call the wrong one. This is a classic "tagged union done wrong" pattern — it's error-prone for callers and impossible to enforce at compile time. You should model this as a sealed class:

```dart
sealed class TypstDocument { ... }
class PdfDocument extends TypstDocument { final Uint8List pdf; ... }
class SvgDocument extends TypstDocument { final List<String> pages; ... }
class FrameDocument extends TypstDocument { ... }
```

This way Dart's exhaustive pattern matching handles it and runtime `StateError`s become impossible.

---

### 3. `compileDocument` returns `int` (page count) but keeps state implicitly

```dart
Future<int> compileDocument({required String source, ...})
```

This API compiles and holds the document in memory server-side (in Rust), returning just a page count. Callers are then expected to call `renderCachedPage` or `renderCachedPageAsSvg` separately. This is implicit shared mutable state — if two callers call `compileDocument` concurrently, the second one silently clobbers the first, and the first caller's subsequent `renderCachedPage` renders the wrong document. There's no handle, no cancellation token, nothing tying the render calls to a specific compilation. This will cause very subtle bugs in any multi-isolate or concurrent editor setup.

---

### 4. `TypstView` — debounce creates a compiler per widget

`TypstView` appears to manage its own compilation lifecycle (it accepts `fonts` and `files` and debounces on `source` changes), which means every `TypstView` in the tree is likely initializing its own Rust engine. Your own docs say "create a single instance per app" — but `TypstView` hides that from the user and almost certainly violates it. Either `TypstView` should accept an external `TypstCompiler` instance, or you need to expose a global/singleton compiler that widgets share via `InheritedWidget`.

---

### 7. `TypstSvgView` vs `TypstView` — redundant widget pair with a boolean flag

You have `TypstView` (raster), `TypstSvgView` (SVG), and `TypstDocumentViewer` with a `useSvg: bool` toggle. This is three entry points for essentially the same thing. The boolean flag on `TypstDocumentViewer` is especially fragile — it's easy to miss and it changes rendering behavior entirely. A cleaner design would be a `TypstRenderMode` enum (`raster`, `svg`) passed to a single multi-page viewer, and just one single-page widget.

---

### 8. `TypstDocument.imageForPage()` is async but `heightForPage`/`widthForPage` are sync

```dart
Future<Image> imageForPage(int pageIndex)
int? heightForPage(int pageIndex)
int? widthForPage(int pageIndex)
```

The dimensions are available synchronously (from the frame data) but the image is async. This means callers can't properly pre-size the widget before the image loads, which causes layout jumps. You should either make all of them synchronous (by decoding the image eagerly) or provide a way to get both dimensions and image in one async call.

---

**Summary by severity:**

| Issue                                      | Severity  |
| ------------------------------------------ | --------- |
| Implicit shared state in `compileDocument` | 🔴 High   |
| `TypstDocument` not a sealed class         | 🟠 Medium |
| Per-widget compiler in `TypstView`         | 🟠 Medium |
| Redundant widget pair                      | 🟡 Low    |
| Async/sync dimension mismatch              | 🟡 Low    |
