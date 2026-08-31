# Issues and Planned Fixes

### GitHub Actions / CI Improvements

1. **Release Race Conditions**: The old `release.yml` had each parallel build job push directly to the GitHub Release. This causes race conditions and clobbered artifacts. (Fix: create a single `publish-release` job that downloads all artifacts first).
2. **Missing Linux arm64 Support**: The package only built Linux x86_64 binaries, breaking compatibility for ARM Linux users. (Fix: add `aarch64-unknown-linux-gnu` target).
3. **Extremely Slow Android Builds**: The Android job was running `cargo install cross`, which compiles the `cross` tool from source, wasting ~5-10 minutes per run. (Fix: use `houseabsolute/actions-rust-cross` to use a pre-built binary).
4. **Missing Rust Caching**: The CI was re-compiling the entire 300+ crate dependency tree from scratch on every run. (Fix: add `swatinem/rust-cache@v4`).
5. **Slow iOS Builds**: The iOS workflow built all 3 architectures sequentially on a single runner. (Fix: split iOS into a parallel matrix and assemble the `.xcframework` at the end).
6. **No Aggregated Status Check**: It's hard to set GitHub branch protection rules when you have dozens of matrix jobs. (Fix: add a `ci-ok` job, but do it _safely_ without the `paths-ignore` trap).
7. **Missing Cross-Platform Dart Tests**: Tests were mainly running on Linux. (Fix: explicitly test integration on Windows, macOS, and Linux).
8. **Missing Concurrency Control**: Pushing multiple commits queued up redundant workflow runs. (Fix: add `concurrency: cancel-in-progress` to workflows).

### Codebase / Rust Engine

9. **Incremental Compilation Cache**: Live editing was slow because the engine was dropping its cache on every keystroke. (Fix: Implement `Source::replace` and input memoization so `comemo` caches layout calculations between compilations).
