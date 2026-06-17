# Set the shells for each platform
set shell := ["sh", "-c"]
set windows-shell := ["powershell.exe", "-NoProfile", "-Command"]

# Chaining operator: powershell.exe uses ; while sh uses &&
and := if os() == "windows" { ";" } else { "&&" }

# --- Tasks ---

# Dart format all relevant directories
fmt:
    dart format .
# Apply Dart fixes
fix:
    dart fix --apply
# Flutter clean + remove local Android build caches
clean:
    flutter clean
    cd example {{ and }} flutter clean
    {{ if os() == "windows" { "$paths = @('android/.gradle', 'android/.kotlin', 'android/build', 'example/android/.gradle', 'example/android/.kotlin', 'example/android/build'); " + "foreach ($p in $paths) { if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue } }" } else { "rm -rfv android/.gradle android/.kotlin android/build example/android/.gradle example/android/.kotlin example/android/build" } }}
# Deep clean including global caches
clean-deep: clean
    {{ if os() == "windows" { "$paths = @(\"$env:USERPROFILE/.gradle\", \"$env:USERPROFILE/.kotlin\"); " + "foreach ($p in $paths) { if (Test-Path $p) { Remove-Item -Recurse -Force $p -ErrorAction SilentlyContinue } }" } else { "rm -rfv ~/.gradle ~/.kotlin" } }}
    dart pub cache clean
# Build for all 4 Android architectures and copy to jniLibs
build-android:
    {{ if os() == "windows" { "$targets = @('aarch64-linux-android', 'armv7-linux-androideabi', 'i686-linux-android', 'x86_64-linux-android'); " + "$abis = @('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64'); " + "for ($i=0; $i -lt $targets.Length; $i++) { " + "Write-Host \"Building for $($targets[$i])...\"; " + "cd rust; cargo ndk -t $($targets[$i]) build --release; cd ..; " + "$src = \"rust/target/$($targets[$i])/release/libtypst_flutter.so\"; " + "$dest = \"android/src/main/jniLibs/$($abis[$i])/\"; " + "if (!(Test-Path $dest)) { New-Item -ItemType Directory -Force -Path $dest | Out-Null }; " + "if (Test-Path $src) { " + "Copy-Item -Path $src -Destination $dest -Force; " + "Write-Host \"  [OK] Copied to $dest\"; " + "} else { " + "Write-Error \"  [ERROR] File not found: $src\"; " + "}" + "}" } else { "targets=('aarch64-linux-android' 'armv7-linux-androideabi' 'i686-linux-android' 'x86_64-linux-android'); " + "abis=('arm64-v8a' 'armeabi-v7a' 'x86' 'x86_64'); " + "for i in \"${!targets[@]}\"; do " + "echo \"Building for ${targets[$i]}...\"; " + "(cd rust && cargo ndk -t ${targets[$i]} build --release); " + "src=\"rust/target/${targets[$i]}/release/libtypst_flutter.so\"; " + "dest=\"android/src/main/jniLibs/${abis[$i]}/\"; " + "mkdir -p \"$dest\"; " + "if [ -f \"$src\" ]; then " + "cp \"$src\" \"$dest\"; " + "echo \"  [OK] Copied to $dest\"; " + "else " + "echo \"  [ERROR] File not found: $src\"; " + "fi; " + "done" } }}
# Run Dart tests with expanded output
test: build-host
    flutter test -r expanded
# Run Dart tests with coverage
test-coverage: build-host
    flutter test --coverage
# Build the native library for the current host OS so tests can run
build-host:
    {{ if os() == "windows" { "cd rust; cargo build --release; cd ..; if (!(Test-Path .typst_flutter_prebuilt/windows)) { New-Item -ItemType Directory -Force -Path .typst_flutter_prebuilt/windows | Out-Null }; Copy-Item rust/target/release/typst_flutter.dll .typst_flutter_prebuilt/windows/typst_flutter.dll -Force" } else if os() == "macos" { "(cd rust && cargo build --release) && mkdir -p .typst_flutter_prebuilt/macos && xcodebuild -create-xcframework -library rust/target/release/libtypst_flutter.a -output .typst_flutter_prebuilt/macos/typst_flutter.xcframework" } else { "(cd rust && cargo build --release) && mkdir -p .typst_flutter_prebuilt/linux && cp rust/target/release/libtypst_flutter.so .typst_flutter_prebuilt/linux/libtypst_flutter.so" } }}
# Run integration tests (crucial for FFI)
test-integration: build-host
    cd example {{ and }} flutter test integration_test/simple_test.dart
# Run native Rust tests
test-rust:
    cd rust {{ and }} cargo test
# Pull dependencies for all packages
get:
    flutter pub get
    cd example {{ and }} flutter pub get
    cd rust_builder {{ and }} flutter pub get
# Generate FRB bindings
gen:
    flutter_rust_bridge_codegen generate
# Full preparation for a PR
prep: fmt fix get gen test-rust lint-rust
# Rust linting with clippy
lint-rust:
    cd rust {{ and }} cargo clippy --all-targets --all-features -- -D warnings
# Rust format
fmt-rust:
    cd rust {{ and }} cargo fmt --all
# Rust format check
fmt-rust-check:
    cd rust {{ and }} cargo fmt --all -- --check
# Rust dependency audit
audit-rust:
    cd rust {{ and }} cargo audit
