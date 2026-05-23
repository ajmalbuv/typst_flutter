## 1.0.0

- Initial stable release.
- Added `TypstCompiler` for native PDF compilation.
- Added `TypstView` widget for live preview rendering.
- Support for passing images and custom fonts via virtual files (`FileSource`, `FontSource`).
- Zero-Rust install workflow via `dart run typst_flutter:setup` using pre-built binaries.
- Full cross-platform support: Android, iOS, macOS, Windows, Linux.

## 1.1.0

- **New:** `TypstDocumentViewer` widget for efficiently displaying multi-page documents with lazy rendering.
- **New:** `TypstSvgView` widget for crisp, scalable vector graphics rendering (SVG) at any zoom level.
- **New:** Structured Error Diagnostics via `TypstCompileException.diagnostics`. Errors now include severity, exact messages, and hints.
- **New:** Date Injection. You can now pass a `DateTime` into the compiler to provide the date for `#datetime.today()`.
- **New:** Support for rendering single pages directly to PNG bytes entirely in Rust (no Flutter UI thread or GPU roundtrip needed) via `renderPageAsPng`.

## 1.0.1

- Fix CI/CD publishing pipeline
- Initial stable release
