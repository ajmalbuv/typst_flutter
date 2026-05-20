# Set the shells for each platform

set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

# --- Tasks ---

# Dart format all relevant directories
fmt:
    dart format lib example rust_builder integration_test bin
# Apply Dart fixes
fix:
    dart fix --apply
# Flutter clean + remove local Android build caches
clean:
    flutter clean
    {{ if os() == "windows" { "if (Test-Path android/.gradle) { Remove-Item -Recurse -Force android/.gradle }; " + "if (Test-Path android/.kotlin) { Remove-Item -Recurse -Force android/.kotlin }; " + "if (Test-Path android/build) { Remove-Item -Recurse -Force android/build }" } else { "rm -rfv android/.gradle android/.kotlin android/build" } }}
# Deep clean including global caches
clean-deep:
    flutter clean
    {{ if os() == "windows" { "$paths = @('android/.gradle', 'android/.kotlin','android/build', \"$env:USERPROFILE/.gradle\", \"$env:USERPROFILE/.kotlin\"); " + "foreach ($p in $paths) { if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue } }" } else { "rm -rfv android/.gradle android/.kotlin android/build ~/.gradle ~/.kotlin" } }}
    dart pub cache clean
# Run integration tests (crucial for FFI)
test-integration:
    flutter test integration_test/simple_test.dart
# Run native Rust tests
test-rust:
    cd rust && cargo test
# Pull dependencies for all packages
get:
    flutter pub get
    cd example && flutter pub get
    cd rust_builder && flutter pub get
# Generate FRB bindings
gen:
    flutter_rust_bridge_codegen generate
# Full preparation for a PR
prep: fmt fix get gen
