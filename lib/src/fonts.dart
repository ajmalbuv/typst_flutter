import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Defines where the Typst compiler should look for fonts.
// ignore: one_member_abstracts
abstract class FontSource {
  /// Base constructor for [FontSource].
  const FontSource();

  /// Load fonts from Flutter assets.
  factory FontSource.assets(List<String> assetPaths) = _AssetFontSource;

  /// Load fonts from raw byte data.
  factory FontSource.bytes(List<Uint8List> data) = _BytesFontSource;

  /// Do not provide any additional fonts (only Typst built-ins).
  factory FontSource.none() = _NoneFontSource;

  /// Loads the font data into memory.
  @internal
  Future<List<Uint8List>> load();
}

class _AssetFontSource extends FontSource {
  const _AssetFontSource(this.assetPaths);
  final List<String> assetPaths;

  @override
  @internal
  Future<List<Uint8List>> load() async {
    final results = <Uint8List>[];
    for (final path in assetPaths) {
      final data = await rootBundle.load(path);
      results.add(data.buffer.asUint8List());
    }
    return results;
  }
}

class _BytesFontSource extends FontSource {
  const _BytesFontSource(this.data);
  final List<Uint8List> data;

  @override
  @internal
  Future<List<Uint8List>> load() async => data;
}

class _NoneFontSource extends FontSource {
  const _NoneFontSource();

  @override
  @internal
  Future<List<Uint8List>> load() async => [];
}
