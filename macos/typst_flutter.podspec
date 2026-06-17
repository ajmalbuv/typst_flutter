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
  s.swift_version = '5.0'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load "$(PODS_TARGET_SRCROOT)/../.typst_flutter_prebuilt/macos/libtypst_flutter.a"',
  }
end
