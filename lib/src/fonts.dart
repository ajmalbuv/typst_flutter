import 'package:equatable/equatable.dart';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';

/// Defines where the Typst compiler should look for additional fonts.
///
/// **Note:** The compiler already bundles the following core fonts by default
/// for basic text, code, and math rendering:
/// - `Libertinus Serif`
/// - `DejaVu Sans Mono`
/// - `NewCM Math`
///
/// You only need to use [FontSource] to provide custom brand fonts or emoji
/// fonts that are not included above.
abstract class FontSource extends Equatable {
  /// Base constructor for [FontSource].
  const FontSource();

  /// Load custom fonts from Flutter assets.
  const factory FontSource.assets(List<String> assetPaths) = _AssetFontSource;

  /// Load custom fonts from raw byte data.
  const factory FontSource.bytes(List<Uint8List> data) = _BytesFontSource;

  /// Do not provide any additional fonts (only use the Typst built-ins).
  const factory FontSource.none() = _NoneFontSource;

  /// Loads the font data into memory.
  @internal
  Future<List<Uint8List>> load();
}

@immutable
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

  @override
  List<Object?> get props => [assetPaths];
}

@immutable
class _BytesFontSource extends FontSource {
  const _BytesFontSource(this.data);
  final List<Uint8List> data;

  @override
  @internal
  Future<List<Uint8List>> load() async => data;

  @override
  List<Object?> get props => [data];
}

@immutable
class _NoneFontSource extends FontSource {
  const _NoneFontSource();

  @override
  @internal
  Future<List<Uint8List>> load() async => [];

  @override
  List<Object?> get props => [];
}
