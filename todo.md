# Typst Flutter TODO

This document tracks completed milestones and upcoming features for full feature parity with `typst.ts` and advanced Flutter integration.

## 🟡 P2: Performance & Optimization

- [ ] **Incremental Compilation Cache**: Implement `Source::edit` and memoization caching to update documents incrementally during live editing.
- [ ] **Font Subsetting**: Reduce bundled binary and font footprint by pruning unused glyphs at build time.
- [ ] **Disk Cache for Packages**: Persist downloaded `@preview/...` packages to platform application cache directories between app restarts.

## 🔵 P3: Accessibility & DX

- [ ] **Layered Text Selection**: Overlay selectable Flutter text widgets over rendered SVG/Canvas pages for copy-paste and hyperlink interaction.
- [ ] **Dynamic Font Loading**: Lazily stream missing font glyphs when encountering unmapped Unicode ranges.
