import 'dart:ffi';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:typst_flutter/src/exceptions.dart';

/// Helper for loading the native typst_flutter library.
class PlatformLoader {
  static const String _libName = 'typst_flutter';

  /// Loads the [DynamicLibrary] for the current platform.
  static DynamicLibrary load() {
    if (Platform.isIOS) {
      return DynamicLibrary.process();
    }

    try {
      return DynamicLibrary.open(_libraryPath);
    } on Object catch (e) {
      // If direct open fails, try to find it in the executable directory
      // (Windows/Linux) or in the Frameworks directory (macOS).
      try {
        return DynamicLibrary.open(_fallbackPath);
      } on Object catch (_) {
        throw TypstLibraryNotFoundException(
          'Could not find native library $_libName. '
          'Ensure you have run "dart run typst_flutter:setup" or '
          'built the library manually. Error: $e',
        );
      }
    }
  }

  static String get _libraryPath {
    if (Platform.isAndroid) return 'lib$_libName.so';
    if (Platform.isLinux) return 'lib$_libName.so';
    if (Platform.isWindows) return '$_libName.dll';
    if (Platform.isMacOS) return 'lib$_libName.dylib';
    throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
  }

  static String get _fallbackPath {
    final executableDir = File(Platform.resolvedExecutable).parent.path;

    if (Platform.isWindows) {
      return p.join(executableDir, '$_libName.dll');
    }
    if (Platform.isLinux) {
      return p.join(executableDir, 'lib', 'lib$_libName.so');
    }
    if (Platform.isMacOS) {
      // macOS apps often have libs in ../Frameworks
      return p.join(executableDir, '..', 'Frameworks', 'lib$_libName.dylib');
    }

    return _libraryPath;
  }
}
