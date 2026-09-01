# Issues and Planned Improvements

1. **Linux arm64 Release Target**: Add `aarch64-unknown-linux-gnu` target to `.github/workflows/release.yml`.
2. **Incremental Compilation Cache**: Implement `Source::edit` and memoization to reuse AST layout state across keystrokes.
3. **Aggregated Status Gate**: Add an explicit `ci-ok` status check job to simplify GitHub branch protection rules across matrix combinations.
4. **iOS Build Matrix**: Parallelize iOS device and simulator architecture compilation before assembling `.xcframework`.
