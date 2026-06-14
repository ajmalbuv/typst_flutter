import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Defines a set of files (images, data files, included `.typ` files) to
/// make available to the Typst compiler's virtual file system.
///
/// The key in every map is the **virtual path** — exactly the string you
/// write in Typst markup. For example, if your markup contains
/// `#image("logo.png")` the key must be `"logo.png"`.
///
/// Example:
/// ```dart
/// FileSource.assets({
///   'logo.png':   'assets/images/logo.png',
///   'data.csv':   'assets/data/sales.csv',
///   'chapter2.typ': 'assets/typst/chapter2.typ',
/// })
/// ```
abstract class FileSource extends Equatable {
  /// Base constructor.
  const FileSource();

  /// Load files from Flutter assets.
  ///
  /// [pathMap] maps virtual path (as used in markup) → Flutter asset path.
  const factory FileSource.assets(Map<String, String> pathMap) =
      _AssetFileSource;

  /// Load files from raw byte data already in memory.
  ///
  /// [files] maps virtual path (as used in markup) → raw file bytes.
  const factory FileSource.bytes(Map<String, Uint8List> files) =
      _BytesFileSource;

  /// No additional files — the compiler cannot resolve any external file
  /// references. Typst will return an error if the markup references any
  /// file (images, includes, etc.).
  const factory FileSource.none() = _NoneFileSource;

  /// Loads all files into memory and returns them as a map of
  /// virtual path → bytes.
  @internal
  Future<Map<String, Uint8List>> load();
}

@immutable
class _AssetFileSource extends FileSource {
  const _AssetFileSource(this._pathMap);
  final Map<String, String> _pathMap;

  @override
  Future<Map<String, Uint8List>> load() async {
    final result = <String, Uint8List>{};
    for (final entry in _pathMap.entries) {
      final data = await rootBundle.load(entry.value);
      result[entry.key] = data.buffer.asUint8List();
    }
    return result;
  }

  @override
  List<Object?> get props => [_pathMap];
}

@immutable
class _BytesFileSource extends FileSource {
  const _BytesFileSource(this._files);
  final Map<String, Uint8List> _files;

  @override
  Future<Map<String, Uint8List>> load() async => Map.unmodifiable(_files);

  @override
  List<Object?> get props => [_files];
}

@immutable
class _NoneFileSource extends FileSource {
  const _NoneFileSource();

  @override
  Future<Map<String, Uint8List>> load() async => const {};

  @override
  List<Object?> get props => [];
}
