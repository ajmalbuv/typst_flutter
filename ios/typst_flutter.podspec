#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
# Run `pod lib lint typst_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'typst_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Native Typst compiler for Flutter via Rust FFI.'
  s.description      = <<-DESC
    Embeds the Typst typesetting compiler natively in Flutter apps via Rust
    FFI. Compile Typst markup to PDF or rendered images on iOS with no WASM,
    no WebView, and no server required.
    Run `dart run typst_flutter:setup` once after `flutter pub get`.
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
  # When `dart run typst_flutter:setup` has been run, the XCFramework
  # is at {package_root}/.typst_flutter_prebuilt/ios/typst_flutter.xcframework.
  # __dir__ is the directory containing this podspec (the ios/ directory),
  # so we navigate one level up to the package root.

  prebuilt_xcframework = File.join(
    __dir__, '../.typst_flutter_prebuilt/ios/typst_flutter.xcframework'
  )

  if File.exist?(prebuilt_xcframework)
    # ── Pre-built path ────────────────────────────────────────────────────────
    s.vendored_frameworks = prebuilt_xcframework
    s.pod_target_xcconfig = {
      'DEFINES_MODULE' => 'YES',
    }
  else
    # ── Cargokit fallback ─────────────────────────────────────────────────────
    # Builds the Rust crate from source. Requires Rust + rustup on the machine.
    s.script_phase = {
      :name               => 'Build Rust library (typst_flutter)',
      :script             => 'sh "$PODS_TARGET_SRCROOT/../../rust_builder/cargokit/build_pod.sh" ../rust typst_flutter',
      :execution_position => :before_compile,
      :input_files        => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
      :output_files       => ['${BUILT_PRODUCTS_DIR}/libtypst_flutter.a'],
    }
    s.pod_target_xcconfig = {
      'DEFINES_MODULE'                       => 'YES',
      'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
      'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libtypst_flutter.a',
    }
  end
end
