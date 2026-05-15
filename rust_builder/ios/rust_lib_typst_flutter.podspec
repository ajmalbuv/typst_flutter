#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint rust_lib_typst_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'rust_lib_typst_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Native Typst typesetting compiler for Flutter (Rust FFI bridge).'
  s.description      = <<-DESC
    Pre-built native library that embeds the Typst typesetting compiler in
    Flutter apps via Rust FFI. No WASM or server required. Download the
    pre-built binary with `dart run typst_flutter:setup`.
  DESC
  s.homepage         = 'https://github.com/ajmalbuv/typst_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ajmal' => 'ajmalbuv@gmail.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.swift_version = '5.0'

  # ── Pre-built binary detection ──────────────────────────────────────────────
  #
  # When `dart run typst_flutter:setup` has been run, the fat static library
  # lives at:
  #   {package_root}/.typst_flutter_prebuilt/ios/librust_lib_typst_flutter.a
  #
  # PODS_TARGET_SRCROOT points to the pod's source root inside the Pods project,
  # which is typically .../Pods/rust_lib_typst_flutter.
  # We navigate from there to the package root.

  prebuilt_lib = File.join(__dir__, '../../.typst_flutter_prebuilt/ios/librust_lib_typst_flutter.a')

  if File.exist?(prebuilt_lib)
    # ── Pre-built path ────────────────────────────────────────────────────────
    # Use the pre-built fat static library directly. No Rust compilation needed.
    s.vendored_libraries = prebuilt_lib

    s.pod_target_xcconfig = {
      'DEFINES_MODULE'                      => 'YES',
      # Flutter.framework does not contain an i386 slice.
      'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
      # Force-load to ensure all symbols (including Typst internals) are linked.
      'OTHER_LDFLAGS' => "-force_load #{prebuilt_lib}",
    }
  else
    # ── Cargokit fallback ─────────────────────────────────────────────────────
    # Pre-built binary not found. Build from Rust source via Cargokit.
    # Requires Rust to be installed on the build machine (e.g. CI with
    # `rustup target add aarch64-apple-ios`).

    s.script_phase = {
      :name               => 'Build Rust library (typst_flutter)',
      :script             => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../rust rust_lib_typst_flutter',
      :execution_position => :before_compile,
      :input_files        => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
      :output_files       => ["${BUILT_PRODUCTS_DIR}/librust_lib_typst_flutter.a"],
    }

    s.pod_target_xcconfig = {
      'DEFINES_MODULE'                       => 'YES',
      'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
      'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librust_lib_typst_flutter.a',
    }
  end
end
