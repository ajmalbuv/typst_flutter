# GEMINI.md — typst_flutter

> **Project context for AI assistants.**
> This file describes the intent, architecture, current state, and conventions
> of `typst_flutter`. Read this before touching any file in the repo.

---

## What this project is

`typst_flutter` is a Flutter package that embeds the **Typst typesetting compiler**
natively into Flutter apps via Rust FFI. It is the Flutter/mobile equivalent of
[typst.ts](https://github.com/Myriad-Dreamin/typst.ts) — which does the same for
the web via WASM — but targets native platforms (Android, iOS, macOS, Linux, Windows)
with no WASM overhead, no WebView, no server, and no subprocess.

The goal is to make **fast, consistent, reliable typesetting and PDF generation**
a first-class citizen in Flutter — the same way typst.ts made it a first-class
citizen in web development.

### What Typst is

[Typst](https://typst.app) is a modern typesetting system written in Rust,
designed as a replacement for LaTeX. It compiles a markup language into
beautifully laid-out documents. It is:

- **Fast** — incremental compilation, sub-100ms for most documents
- **Consistent** — deterministic output, no layout surprises
- **Programmable** — full scripting language built in (variables, functions, loops)
- **Beautiful** — professional typography out of the box

### Why Flutter needs this

Flutter has no built-in solution for professional document generation. Current
options are all painful:

| Option                    | Problem                                                  |
| ------------------------- | -------------------------------------------------------- |
| `pdf` package (pure Dart) | Manual layout, no typesetting, no scripting              |
| `printing` package        | Wraps platform print dialogs, not a compiler             |
| WebView + typst.ts        | Heavy, requires internet or bundled WASM, no mobile perf |
| Shell out to typst CLI    | Not possible on iOS/Android, requires install            |
| Server-side rendering     | Round-trip latency, requires infrastructure              |

`typst_flutter` solves all of these by compiling Typst directly in the Flutter
process via a Rust shared library loaded with `dart:ffi`.

---

## Author

**Ajmal** (`ajmalbuv` on GitHub and LinkedIn)
Kerala, India — Flutter/mobile engineer, also building
[Kriyax](https://github.com/ajmalbuv) and a hotel invoice generator
([invoice.ajmalbuv.duckdns.org](http://invoice.ajmalbuv.duckdns.org))
using Typst for PDF generation — which is the direct motivation for this package.

---

## Repository layout

```
typst_flutter/                  ← Flutter FFI plugin (pub.dev package root)
│
├── rust/                       ← Rust crate: the FFI bridge (via flutter_rust_bridge)
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs              ← crate root (re-exports api module)
│       └── api/
│           └── typst.rs        ← FRB-bridged types: TypstEngine, CompiledDocument, SimpleWorld
│
├── lib/                        ← Dart package source
│   ├── typst_flutter.dart      ← barrel export
│   └── src/
│       ├── compiler.dart       ← TypstCompiler: wraps TypstEngine, public API entry point
│       ├── document.dart       ← TypstDocument: opaque handle to CompiledDocument in Rust
│       ├── fonts.dart          ← FontSource abstraction (assets / bytes / none)
│       ├── files.dart          ← FileSource abstraction (virtual files for images/includes)
│       ├── exceptions.dart     ← TypstCompileException, TypstRenderException
│       ├── widgets/
│       │   ├── typst_view.dart             ← single-page renderer (raster or SVG via TypstRenderMode)
│       │   └── typst_document_viewer.dart  ← multi-page scrollable viewer
│       └── rust/               ← FRB-generated bridge code (do not edit)
│           ├── api/typst.dart
│           ├── frb_generated.dart
│           └── ...
│
├── bin/
│   └── setup.dart              ← dart run typst_flutter:setup (binary downloader)
│
├── example/                    ← standalone Flutter app demonstrating the package
│   └── lib/
│       └── main.dart
│
├── android/                    ← Android platform glue
├── ios/                        ← iOS platform glue + podspec
│
├── .github/
│   └── workflows/
│       ├── release.yml         ← CI: cross-compile + GitHub Release + pub.dev publish
│       └── ci.yml              ← CI: lint, format, test (Dart + Rust)
│
├── pubspec.yaml
├── CHANGELOG.md
├── GEMINI.md                   ← YOU ARE HERE (ignored for pub.dev)
└── README.md
```

---

## Architecture: how the bridge works

```
Flutter app (Dart)
│
│  compiler.dart
│  TypstCompiler.compile(source)
│       │
│       └── TypstEngine.compile()  ← FRB managed Isolate
│                   │
│                    ══════════════════
│                    FRB Generated Bridge
│                    ══════════════════
│                           │
│                   rust/src/api/typst.rs
│                   TypstEngine::compile(markup, files, sys_time)
│                           │
│                           ├── configures SimpleWorld (implements typst::World)
│                           ├── calls typst::compile(&world)
│                           └── returns CompiledDocument { inner: PagedDocument }
│
│  document.dart
│  TypstDocument (wraps CompiledDocument)
│       │
│       ├── .exportPdf()     → CompiledDocument.export_pdf()   → typst_pdf::pdf()
│       ├── .renderSvg(i)    → CompiledDocument.export_svg(i)  → typst_svg::svg()
│       ├── .renderRaster(i) → CompiledDocument.render_page(i) → typst_render::render()
│       ├── .pageInfo(i)     → page dimensions in points
│       └── .dispose()       → drops the Rust PagedDocument
```

### Key design decisions

**Using flutter_rust_bridge (FRB).**
We use FRB v2 to handle the bridge between Dart and Rust. This eliminates manual memory management, pointer arithmetic, and `extern "C"` boilerplate. FRB generates safe wrappers, handles complex data types (like `Vec<Vec<u8>>`), and manages background Isolates automatically.

**Opaque Document Handle.**
`TypstCompiler.compile()` returns a `TypstDocument` wrapping a Rust `CompiledDocument` (an opaque FRB handle). The compiled `PagedDocument` lives in Rust memory and is never serialised across the FFI boundary. Rendering, SVG export, and PDF export are all lazy — they happen on demand via the handle. This eliminates the old implicit-state pattern where the engine held a "current document" and concurrent callers could clobber each other.

**Automated Native Builds with Cargokit.**
The project includes a `rust_builder` package that uses **Cargokit**. This allows the Rust library to be compiled automatically as part of the Flutter build process, provided the developer has Rust installed.

**Automatic Isolate Management.**
FRB automatically executes heavy Rust functions on a background Isolate, keeping the Flutter UI thread responsive.

**Explicit Resource Lifecycle.**
Both `TypstCompiler` and `TypstDocument` expose `dispose()` methods for deterministic cleanup of native memory. `TypstDocument` guards against use-after-dispose with a `StateError`.

**Fonts are passed as raw bytes.**
Typst needs fonts at compile time. Dart loads font bytes from Flutter assets and passes them as a `List<Uint8List>`, which FRB efficiently converts to `Vec<Vec<u8>>` for the Rust engine.

---

---

## The distribution problem and how it's solved

pub.dev has a **100MB compressed package size limit**. The compiled Typst Rust
library is ~15-30MB per platform target. Across 8 targets this is well over
the limit. pub.dev is also a source registry — it does not host binary artifacts.

### Solution: GitHub Releases + setup script

The package on pub.dev contains **only Dart source and Rust source** (~small).
Prebuilt native binaries live on **GitHub Releases**, one artifact per platform/arch,
as `.tar.gz` or `.zip` files with SHA-256 checksums.

End users run once after `flutter pub get`:

```bash
dart run typst_flutter:setup
```

`bin/setup.dart` detects the OS and CPU architecture, downloads the correct
artifact from the matching GitHub Release tag, verifies its SHA-256 checksum,
extracts the library, and places it in the correct platform directory.

A `.typst_flutter_version` stamp file prevents redundant re-downloads.

### CI pipeline (`.github/workflows/release.yml`)

Triggered by `git push tag v*`. Runs 8 parallel jobs:

| Job                  | Target                              | Output                |
| -------------------- | ----------------------------------- | --------------------- |
| `build-linux-x64`    | `x86_64-unknown-linux-gnu`          | `libtypst_flutter.so` |
| `build-linux-arm64`  | `aarch64-unknown-linux-gnu`         | `libtypst_flutter.so` |
| `build-macos`        | universal (x64 + arm64)             | `libtypst_flutter.a`  |
| `build-windows-x64`  | `x86_64-pc-windows-msvc`            | `typst_flutter.dll`   |
| `build-android` (×4) | arm64-v8a, armeabi-v7a, x86_64, x86 | `.so` per ABI         |
| `build-ios`          | device + simulator xcframework      | `.xcframework`        |

After all jobs complete:

1. All artifacts are collected and attached to a GitHub Release
2. `SHA256SUMS` file is generated and attached
3. Package is published to pub.dev via OIDC (no stored secrets)

---

## Current state (as of v2.0.0)

### Future / nice to have

- [ ] Incremental compilation cache (reuse world across calls with same fonts)
- [ ] Font subsetting to reduce bundle size
- [ ] Multi-file project support (directory-based VFS)
- [ ] Typst Package Registry (`#import "@preview/..."`)

---

## Rust crate details

### `rust/Cargo.toml` key dependencies

```toml
typst = "0.15.0"          # core compiler
typst-pdf = "0.15.0"      # PDF export
typst-render = "0.15.0"   # raster image render (RGBA pixels)
typst-svg = "0.15.0"      # SVG export
flutter_rust_bridge = "2"  # Dart ↔ Rust bridge
time = "0.3"               # date/time for typst::World::today()
```

### `rust/src/api/typst.rs` — FRB-bridged API

```rust
// ── TypstEngine (opaque, stateful) ──────────────────────────
#[frb(opaque)]
pub struct TypstEngine { world: SimpleWorld }

impl TypstEngine {
    #[frb(sync)]
    pub fn new() -> Self;                              // bundled fonts loaded
    pub fn add_fonts(&mut self, font_data: Vec<Vec<u8>>);
    pub fn compile(&mut self, markup: String,
        files: Vec<VirtualFile>, sys_time: Option<i64>,
    ) -> Result<CompiledDocument, TypstCompileError>;
}

// ── CompiledDocument (opaque, immutable) ────────────────────
#[frb(opaque)]
pub struct CompiledDocument { inner: PagedDocument }

impl CompiledDocument {
    pub fn page_count(&self) -> usize;
    pub fn page_info(&self, index: usize) -> Result<PageInfo, String>;
    pub fn render_page(&self, index: usize, pixel_per_pt: f32) -> Result<RenderResult, String>;
    pub fn export_pdf(&self) -> Result<Vec<u8>, String>;
    pub fn export_svg(&self, index: usize) -> Result<String, String>;
}
```

### `SimpleWorld` — the Typst World implementation

Typst requires a `World` trait implementation that provides:

- `library()` — built-in Typst standard library
- `book()` — font book (index of available fonts)
- `main()` — the main source file
- `source(id)` — resolve file IDs to source text
- `file(id)` — resolve file IDs to binary data (images, data files)
- `font(index)` — get font by index
- `today(offset)` — current date (uses `sys_time` passed from Dart)

`SimpleWorld` implements all of these from data passed in via FFI.
It does not touch the filesystem. Everything is in-memory.
The virtual file system is reset on every `compile()` call.

---

## Dart API surface

### `TypstCompiler`

```dart
// Create a compiler instance (loads native library, resolves fonts)
static Future<TypstCompiler> create({FontSource? fonts})

// Add more fonts after creation
Future<void> addFonts(FontSource fonts)

// Compile source → opaque TypstDocument handle
Future<TypstDocument> compile({
  required String source,
  FileSource? files,
  DateTime? date,
  Map<String, String>? inputs,
})

// Query document structure/metadata using a Typst selector
Future<String> query({
  required TypstDocument document,
  required String selector,
})

// Release native resources
void dispose()

// Version of embedded Typst compiler
Future<String> get compilerVersion
```

### `TypstDocument`

```dart
int pageCount                                       // total pages
Future<PageInfo> pageInfo(int pageIndex)             // dimensions in points
Future<Uint8List> exportPdf()                        // full PDF bytes
Future<String> renderSvg(int pageIndex)              // SVG string for one page
Future<TypstRenderResult> renderRaster({             // RGBA pixels for one page
  required int pageIndex,
  double pixelsPerPt = 2.0,
})
void dispose()                                      // release native memory
```

### `TypstRenderResult`

```dart
Uint8List bytes       // raw RGBA pixel data
int width             // image width in pixels
int height            // image height in pixels
Future<ui.Image> toImage()  // cached Flutter image
Future<Uint8List> toPng()   // self-contained PNG encoding (no leak)
void dispose()              // release cached ui.Image
```

### `FontSource`

```dart
FontSource.assets(List<String> assetPaths)  // from Flutter assets
FontSource.bytes(List<Uint8List> data)       // raw bytes
FontSource.none()                            // Typst built-in fonts only
```

### `TypstView` widget

```dart
// Option 1: From a pre-compiled document (recommended)
TypstView(
  document: myTypstDoc,
  pageIndex: 0,
  renderMode: TypstRenderMode.svg,  // or .raster
)

// Option 2: Self-managed compilation (convenience)
TypstView.source(
  source: r'= Hello, Typst!',
  fonts: FontSource.assets(['assets/NotoSans.ttf']),
  pageIndex: 0,
  renderMode: TypstRenderMode.svg,
)
```

### `TypstDocumentViewer` widget

```dart
// Option 1: From a pre-compiled document
TypstDocumentViewer.document(
  document: myTypstDoc,
  renderMode: TypstRenderMode.svg,
)

// Option 2: Self-managed compilation
TypstDocumentViewer(
  source: myMarkup,
  fonts: FontSource.assets(['assets/NotoSans.ttf']),
  renderMode: TypstRenderMode.svg,
)
```

### `TypstCompilerProvider` widget

```dart
// Wrap your app/page to share a single background compiler globally
TypstCompilerProvider(
  compiler: mySharedCompiler,
  child: MyApp(),
)
// Any TypstView or TypstDocumentViewer deep inside will automatically reuse it!
```

---

## Conventions and preferences

- **Language**: Dart (Flutter) + Rust. No C/C++ glue files — the `plugin_ffi`
  template generates a placeholder `.c` file for iOS; keep it, it's required
  by the podspec but does nothing.

- **Error handling**: Typed exceptions (`TypstCompileException`) not error strings.
  Never swallow errors silently.

- **Async**: Every call that touches native code goes through background isolates (managed automatically by FRB v2).
  The public API is fully async. Never call FFI functions on the UI thread.

- **Memory**: Managed by FRB v2. Safe serialization across the FFI boundary.

- **Formatting**: `dart format` enforced. Rust: `cargo fmt` enforced.

- **Using flutter_rust_bridge**: We use FRB v2 for safe, efficient, and easy-to-maintain FFI. It handles complex data types and background isolates automatically.

- **Catppuccin Mocha** color palette used in example app UI and any
  documentation visuals (consistent with author's personal brand).

- **Commit style**: conventional commits (`feat:`, `fix:`, `chore:`, `docs:`).

---

## How to work on this locally

```bash
# Clone
git clone https://github.com/ajmalbuv/typst_flutter
cd typst_flutter

# Install Dart/Flutter deps
flutter pub get

# Build the native library (first time is slow — Typst has a large dep tree)
cd rust
cargo build --release
cd ..

# Copy the built library to the right place (Linux example)
cp rust/target/release/libtypst_flutter.so linux/libs/

# Run the example app
cd example
flutter pub get
flutter run -d linux   # or macos, android, etc.
```

### First-time Rust build time

Expect **5–15 minutes** on first `cargo build --release`. Typst pulls in:

- `resvg` (SVG rendering)
- `ttf-parser` (font parsing)
- `comemo` (memoization framework)
- `unicode-bidi`, `rustybuzz`, `harfbuzz` (text shaping)
- ...and ~80 other transitive deps

Subsequent builds are fast due to Cargo's incremental compilation.

---

## Comparison to typst.ts

|                      | [typst.ts](https://github.com/Myriad-Dreamin/typst.ts) | typst_flutter              |
| -------------------- | ------------------------------------------------------ | -------------------------- |
| Target               | Web (browser)                                          | Mobile + Desktop (Flutter) |
| Runtime              | WASM                                                   | Native Rust via dart:ffi   |
| Distribution         | npm package                                            | pub.dev + GitHub Releases  |
| Font loading         | Web fonts / bundled                                    | Flutter assets / raw bytes |
| PDF output           | ✅                                                     | ✅                         |
| SVG output           | ✅                                                     | ✅                         |
| Image render         | ✅                                                     | ✅                         |
| Incremental compile  | ✅                                                     | Planned                    |
| Offline              | ✅                                                     | ✅                         |
| Mobile (iOS/Android) | ❌                                                     | ✅                         |
| Binary size overhead | WASM (~8MB)                                            | Native (~15MB)             |

The goal is to match typst.ts in features and developer experience,
but for the Flutter ecosystem.

---

## Links

- Typst language docs: https://typst.app/docs
- Typst crate (lib.rs): https://docs.rs/typst
- typst-pdf crate: https://docs.rs/typst-pdf
- typst-render crate: https://docs.rs/typst-render
- typst.ts (web equivalent): https://github.com/Myriad-Dreamin/typst.ts
- dart:ffi docs: https://dart.dev/guides/libraries/c-interop
- Flutter FFI plugin guide: https://docs.flutter.dev/platform-integration/android/c-interop
- pub.dev package: https://pub.dev/packages/typst_flutter (not yet published)
- GitHub repo: https://github.com/ajmalbuv/typst_flutter
