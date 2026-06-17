#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint typst_flutter.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'typst_flutter'
  s.version          = '1.0.0'
  s.summary          = 'Typst compiler natively in Flutter via Rust FFI.'
  s.description      = 'Embed the Typst typesetting compiler natively in Flutter via Rust FFI.'
  s.homepage         = 'https://github.com/ajmalbuv/typst_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ajmal' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'

  # Tell CocoaPods to bundle the pre-built macOS dynamic library
  s.vendored_libraries = '../.typst_flutter_prebuilt/macos/libtypst_flutter.dylib'
end
