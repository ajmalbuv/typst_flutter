# Typst Flutter TODO

This document tracks completed milestones and upcoming features for full feature parity with `typst.ts` and advanced Flutter integration.

## 🔴 P1: Architecture, CI/CD & Tooling

- [ ] **CI: Linux arm64 Release Target**:
  - Add `aarch64-unknown-linux-gnu` cross-compilation target to `.github/workflows/release.yml`.
- [ ] **CI: iOS Build Matrix**:
  - Parallelize iOS device and simulator architecture compilation jobs before assembling the unified `.xcframework`.
- [ ] **Dart & Flutter Native Assets (`hook/build.dart`)**:
  - Migrate from Cargokit and brittle CMake/Podspec/Gradle auto-download scripts to Dart's official Native Assets hooks (supported in FRB v2.13+).
  - Unify cross-platform native compilation and prebuilt binary linking across Android, iOS, Windows, macOS, and Linux.
- [ ] **Desktop Toolchain Fallback (Immediate)**:
  - Add compile-from-source fallback to `windows/CMakeLists.txt`, `macos/typst_flutter.podspec`, and `linux/CMakeLists.txt` when prebuilt binaries cannot be downloaded (e.g., offline or air-gapped environments).

## 🟡 P2: Performance & Optimization

- [ ] **Persistent Disk Cache for Packages**:
  - Persist downloaded `@preview/...` packages to platform application cache directories (`path_provider` / local app data) rather than keeping them solely in memory.
  - Enable offline package compilation after first download.
- [ ] **Font Subsetting**:
  - Reduce bundled binary and font footprint by pruning unused glyphs at build time.

## 🔵 P3: Accessibility & Interactive UX

- [ ] **Dynamic Font Loading**:
  - Lazily stream missing font glyphs when encountering unmapped Unicode ranges.

## 🟣 P4: Platform & Font Expansion

- [ ] **Host System Font Discovery**:
  - Auto-discover fonts installed in host OS directories (Windows Fonts, macOS `/Library/Fonts`, Linux fontconfig, Android fallback) so users don't need to manually bundle standard fonts.
- [ ] **Flutter Web Support (WASM)**:
  - Branch networking from blocking `ureq` to browser `fetch()` for `wasm32-unknown-unknown`.
  - Evaluate Web Worker isolate bridges and bundle size mitigation for `typst_flutter.wasm`.
