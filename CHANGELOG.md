## 2.2.1

### Bug Fixes

- **Android**: Fixed auto-download failing with `Cannot operate on packages inside the cache` — the setup command is now run from the consumer app root instead of the pub cache directory.
- **iOS**: Same root-cause fix — the podspec now runs `dart run typst_flutter:setup` from the app root (`File.expand_path('..', Dir.pwd)`) rather than from inside the pub cache.
- **macOS**: Added auto-download and fallback error — the podspec previously had no binary detection at all and would silently produce a broken build.
- **Linux**: Added auto-download via CMake `execute_process` from the app root, with a clear `FATAL_ERROR` if binaries are still missing.
- **Windows desktop**: Same as Linux, using `cmd /c` for Windows shell compatibility.

---

## 2.2.0

### Engine Upgrade

- **Typst 0.15.0**: Upgraded the underlying Typst compiler engine to [0.15.0](https://typst.app/docs/changelog/0.15.0/). This brings variable font support, improved diagnostics, and many layout refinements. All Typst sub-crates (`typst-pdf`, `typst-render`, `typst-svg`, `typst-layout`, `typst-utils`) are updated in lockstep.

### New Features & Optimizations

- **Shared Compiler Architecture**: Added `TypstCompilerProvider`, an `InheritedWidget` that allows `TypstView` and `TypstDocumentViewer` widgets to seamlessly discover and reuse a globally shared Rust engine instance. This eliminates thread spawning and font decoding overhead, reducing multi-widget rendering latency from ~200ms to **0ms**.
- **Data Extraction**: Added `TypstCompiler.query()` to extract JSON metadata and document structure programmatically using Typst selectors (e.g., `<heading>`).
- **Variable Injection**: Added `sys.inputs` support to `TypstCompiler.compile()`. You can now pass a `Map<String, String>` from Dart directly into the Typst `#sys.inputs` dictionary, safely injecting theme data, usernames, or configuration flags into your documents.
- **Enabled Thin LTO**: Release builds now use `lto = "thin"` for cross-crate link-time optimization, yielding ~5-15% smaller native binaries without major compile-time impact.

---

## 2.1.0

### Optimizations & API Refinements

- **Synchronous Metadata API**: `TypstDocument.pageCount`, `TypstDocument.pageInfo()`, and `TypstCompiler.compilerVersion` are now fully synchronous. By leveraging `flutter_rust_bridge` v2's `#[frb(sync)]` feature, these lightweight calls execute instantly on the main thread, eliminating `Future` overhead and preventing UI layout jumps during rendering.
- **Dynamic Versioning**: The Rust build script now dynamically extracts the exact `typst` crate version from `Cargo.toml`. `compilerVersion` will always be perfectly accurate without manual updates.
- **Robust Date Handling**: The Rust `SimpleWorld` environment now gracefully falls back to the native OS system time (`std::time::SystemTime::now()`) if no date is provided from Dart. This means calling `compile()` without a `date` parameter will no longer crash when evaluating `#datetime.today()` in Typst markup.

### Documentation

- **100% API Hover Docs**: Every public class, method, and field in the Dart API now has extensive documentation comments (`///`), providing a premium developer experience in IDEs.
- **Bundled Fonts Documented**: The built-in core fonts (`Libertinus Serif`, `DejaVu Sans Mono`, and `NewCM Math`) are now explicitly documented in the API so developers know what's available out-of-the-box.

## 2.0.0

### ⚠️ Breaking Changes

- **`TypstDocument` is now an opaque document handle.**
  The old `TypstDocument` (with `.pdf`, `.svgs`, `.imageForPage()`) has been replaced
  with a lightweight handle wrapping the compiled document in Rust memory. Rendering
  and export are now lazy — call `doc.exportPdf()`, `doc.renderSvg(pageIndex)`, or
  `doc.renderRaster(pageIndex: i)` on demand.

- **`compile()` now returns `TypstDocument`** (the opaque handle), not a container
  holding pre-generated PDF bytes. Call `doc.exportPdf()` to get the `Uint8List`.

- **Removed `compileDocument()` / `renderCachedPage()` / `renderCachedPageAsSvg()`.**
  These implicit shared-state APIs are gone. Use `compile()` → `TypstDocument` →
  `renderRaster()` / `renderSvg()` instead. Each `TypstDocument` is independent.

- **Removed `compileSvg()`** — Use `compile()` then `doc.renderSvg(pageIndex)` per page.

- **Removed `renderPage()` / `renderPageAsPng()`** — Use `compile()` then
  `doc.renderRaster()` or call `result.toPng()` for PNG bytes.

- **Removed `TypstSvgView` widget.** Use `TypstView` with
  `renderMode: TypstRenderMode.svg` instead.

- **Removed `PdfDocument`, `SvgDocument`, `RasterDocument`** sealed class hierarchy.
  All compilation now returns `TypstDocument`.

- **`TypstDocumentViewer` replaces `useSvg: bool` with `renderMode: TypstRenderMode`.**

- **`errorBuilder` signature changed from `Object` to `TypstCompileException`.**

### Migration Guide

```dart
// ── Before (1.x) ──────────────────────────────────────────

// PDF
final doc = await compiler.compile(source: markup);
final pdf = doc.pdf; // Uint8List directly

// Raster
final result = await compiler.renderPage(source: markup);
final image = await result.toImage();

// SVG
final doc = await compiler.compileSvg(source: markup);
final svgs = doc.svgs;

// Multi-page (implicit state — race condition prone)
final count = await compiler.compileDocument(source: markup);
final svg = await compiler.renderCachedPageAsSvg(pageIndex: 0);

// ── After (2.0) ───────────────────────────────────────────

// PDF
final doc = await compiler.compile(source: markup);
final pdf = await doc.exportPdf();

// Raster
final doc = await compiler.compile(source: markup);
final result = await doc.renderRaster(pageIndex: 0);
final image = await result.toImage();

// SVG
final doc = await compiler.compile(source: markup);
final svg = await doc.renderSvg(0);

// Multi-page (safe — each doc is independent)
final doc = await compiler.compile(source: markup);
for (var i = 0; i < doc.pageCount; i++) {
  final svg = await doc.renderSvg(i);
}

// Don't forget to dispose when done!
doc.dispose();
```

### New Features

- **`TypstDocument.dispose()`** — Explicit lifecycle management for the native
  Rust document handle. Calling `dispose()` eagerly frees the underlying
  `PagedDocument` memory (which can be several MB). Use-after-dispose throws
  `StateError`. Safe to call multiple times.

- **`TypstDocument.pageInfo(int pageIndex)`** — Query page dimensions in points
  without rendering.

- **`TypstView` dual constructor pattern:**
  - `TypstView(document: doc)` — renders from a pre-compiled document (shared compiler).
  - `TypstView.source(source: markup)` — self-manages compilation (convenience).

- **`TypstDocumentViewer.document()` constructor** — Accepts a pre-compiled
  `TypstDocument`, avoiding per-widget compiler creation.

- **`TypstRenderMode` enum** (`svg`, `raster`) — Replaces the fragile `useSvg: bool`
  flag on `TypstDocumentViewer`.

- **`@internal` annotation on `FontSource.load()`** — Prevents users from calling
  the internal font loading method directly.

### Fixes

- **Fixed image leak in `TypstRenderResult.toPng()`** — The method now creates a
  temporary image and disposes it immediately if no cached image exists, preventing
  native `ui.Image` leaks when `dispose()` is never called.

- **Fixed missing `dispose()` in widget lifecycle** — `TypstView` and
  `TypstDocumentViewer` now properly dispose their owned `TypstCompiler` instances
  in `State.dispose()` and when fonts change in `didUpdateWidget`.

- **Fixed implicit shared mutable state** — `compileDocument()` returned an int and
  stored the document in the Rust engine. Concurrent callers could silently clobber
  each other's documents. The new `TypstDocument` handle eliminates this entirely.

### Internal

- `TypstCompiler._engine` is now private (was `engine` public).
- `TypstCompiler` implements `Finalizable`.
- Typed `TypstCompileException` used throughout (was `Object` in error handlers).
- Added `prefer_expression_function_bodies` lint rule.
- Added `meta` dependency for `@internal` annotation.
- Updated `.pubignore` to exclude internal files from pub.dev.

---

## 1.1.1

- **Feature:** Truly Zero-Configuration native setup! Android and iOS builds now automatically execute `typst_flutter:setup` on the fly to download native binaries. No manual commands required.
- **Fix:** Fixed a severe path-parsing bug on Windows where `setup.dart` crashed with a `PathNotFoundException` while writing macOS binaries.
- **Fix:** Safely fall back to `cargokit` compilation if auto-downloads fail or the user is strictly offline.

## 1.1.0

- **New:** `TypstDocumentViewer` widget for efficiently displaying multi-page documents with lazy rendering.
- **New:** `TypstSvgView` widget for crisp, scalable vector graphics rendering (SVG) at any zoom level. _(Removed in 2.0.0 — use `TypstView` with `TypstRenderMode.svg`)_
- **New:** Structured Error Diagnostics via `TypstCompileException.diagnostics`. Errors now include severity, exact messages, and hints.
- **New:** Date Injection. You can now pass a `DateTime` into the compiler to provide the date for `#datetime.today()`.
- **New:** Support for rendering single pages directly to PNG bytes entirely in Rust (no Flutter UI thread or GPU roundtrip needed) via `renderPageAsPng`.

## 1.0.1

- Fix CI/CD publishing pipeline
- Initial stable release

## 1.0.0

- Initial stable release.
- Added `TypstCompiler` for native PDF compilation.
- Added `TypstView` widget for live preview rendering.
- Support for passing images and custom fonts via virtual files (`FileSource`, `FontSource`).
- Zero-Rust install workflow via `dart run typst_flutter:setup` using pre-built binaries.
- Full cross-platform support: Android, iOS, macOS, Windows, Linux.
