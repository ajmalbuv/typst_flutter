# Typst Flutter TODO

This document tracks remaining features required for full feature parity with `typst.ts` and advanced Flutter integration.

## 🟢 P2: Advanced Features

- [ ] **Typst Package Registry**: Add support for `#import "@preview/..."` by implementing a `PackageSource` in Dart and resolving `FileId::package()` in `SimpleWorld`.

## 🔵 P3: Accessibility & DX

- [ ] **Layered Text Selection**: Overlay selectable HTML/Flutter text nodes on top of the SVG/Canvas render to allow copy-paste, highlighting, and hyperlinks (like `typst.ts` does in the browser).
- [ ] **Dynamic Font Loading**: Support lazily fetching missing fonts as new scripts are encountered during compilation, rather than requiring all fonts upfront via `FontSource`.

──────

# ISSUES

## vs. typst.ts — What's Missing

typst.ts isn't just a compiler bridge — it's an ecosystem. Everything else in the todo.md is genuinely future features.
