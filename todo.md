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
- [ ] **Global Compiler Provider**: Implement a `TypstCompilerProvider` `InheritedWidget` so `TypstView.source()` can optionally reuse a shared compiler instead of always creating a new one per widget.

──────

# ISSUES

## vs. typst.ts — What's Missing

typst.ts isn't just a compiler bridge — it's an ecosystem. The functional gaps (scoped to no new features, just
table stakes parity) are: query() API for structured data extraction, source-location in error spans, and
TypstSeverity as an enum. Everything else in the todo.md is genuinely future features.
