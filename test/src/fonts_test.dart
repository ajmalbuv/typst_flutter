import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/typst_flutter.dart';

void main() {
  group('FontSource.bytes', () {
    test('is a FontSource subtype', () {
      const source = FontSource.bytes([]);
      expect(source, isA<FontSource>());
    });

    test('load() returns the exact list passed in', () async {
      final font1 = Uint8List.fromList([1, 2, 3]);
      final font2 = Uint8List.fromList([4, 5, 6]);
      final data = [font1, font2];
      final source = FontSource.bytes(data);

      final result = await source.load();

      expect(result, same(data));
    });

    test('load() works with an empty list', () async {
      const source = FontSource.bytes([]);

      final result = await source.load();

      expect(result, isEmpty);
      expect(result, isA<List<Uint8List>>());
    });

    test('load() works with a single font', () async {
      final font = Uint8List.fromList([0x00, 0x01, 0x00, 0x00]);
      final source = FontSource.bytes([font]);

      final result = await source.load();

      expect(result, hasLength(1));
      expect(result.first, same(font));
    });

    test('load() works with multiple fonts', () async {
      final font1 = Uint8List.fromList([10, 20]);
      final font2 = Uint8List.fromList([30, 40]);
      final font3 = Uint8List.fromList([50, 60]);
      final source = FontSource.bytes([font1, font2, font3]);

      final result = await source.load();

      expect(result, hasLength(3));
      expect(result[0], same(font1));
      expect(result[1], same(font2));
      expect(result[2], same(font3));
    });

    test('same data => equal', () {
      final font = Uint8List.fromList([1, 2, 3]);
      final source1 = FontSource.bytes([font]);
      final source2 = FontSource.bytes([font]);

      expect(source1, equals(source2));
      expect(source1.hashCode, equals(source2.hashCode));
    });

    test('equal byte content in separate Uint8Lists => equal', () {
      final source1 = FontSource.bytes([
        Uint8List.fromList([1, 2, 3]),
      ]);
      final source2 = FontSource.bytes([
        Uint8List.fromList([1, 2, 3]),
      ]);

      expect(source1, equals(source2));
    });

    test('different data => not equal', () {
      final source1 = FontSource.bytes([
        Uint8List.fromList([1, 2, 3]),
      ]);
      final source2 = FontSource.bytes([
        Uint8List.fromList([4, 5, 6]),
      ]);

      expect(source1, isNot(equals(source2)));
    });

    test('different list lengths => not equal', () {
      final font = Uint8List.fromList([1, 2, 3]);
      final source1 = FontSource.bytes([font]);
      final source2 = FontSource.bytes([font, font]);

      expect(source1, isNot(equals(source2)));
    });

    test('empty vs non-empty => not equal', () {
      const source1 = FontSource.bytes([]);
      final source2 = FontSource.bytes([
        Uint8List.fromList([1]),
      ]);

      expect(source1, isNot(equals(source2)));
    });

    test('bytes is not equal to none', () {
      const bytesSource = FontSource.bytes([]);
      const noneSource = FontSource.none();

      expect(bytesSource, isNot(equals(noneSource)));
    });
  });

  group('FontSource.none', () {
    test('is a FontSource subtype', () {
      const source = FontSource.none();
      expect(source, isA<FontSource>());
    });

    test('load() returns an empty list', () async {
      const source = FontSource.none();

      final result = await source.load();

      expect(result, isEmpty);
      expect(result, isA<List<Uint8List>>());
    });

    test('can be constructed as const', () {
      const source = FontSource.none();
      expect(source, isNotNull);
    });

    test('two none() instances are equal', () {
      const source1 = FontSource.none();
      const source2 = FontSource.none();

      expect(source1, equals(source2));
      expect(source1.hashCode, equals(source2.hashCode));
    });

    test('const none() instances are identical', () {
      const source1 = FontSource.none();
      const source2 = FontSource.none();

      expect(identical(source1, source2), isTrue);
    });

    test('none is not equal to bytes with empty list', () {
      const noneSource = FontSource.none();
      const bytesSource = FontSource.bytes([]);

      expect(noneSource, isNot(equals(bytesSource)));
    });
  });

  group('FontSource.assets', () {
    test('can be constructed', () {
      final paths = ['assets/font.ttf'].toList();
      final source = FontSource.assets(paths);
      expect(source, isNotNull);
    });

    test('is a FontSource subtype', () {
      const source = FontSource.assets(['assets/font.ttf']);
      expect(source, isA<FontSource>());
    });

    test('same paths => equal', () {
      const source1 = FontSource.assets(['assets/font.ttf']);
      const source2 = FontSource.assets(['assets/font.ttf']);

      expect(source1, equals(source2));
      expect(source1.hashCode, equals(source2.hashCode));
    });

    test('same paths in same order => equal', () {
      const source1 = FontSource.assets(['a.ttf', 'b.ttf', 'c.ttf']);
      const source2 = FontSource.assets(['a.ttf', 'b.ttf', 'c.ttf']);

      expect(source1, equals(source2));
    });

    test('different paths => not equal', () {
      const source1 = FontSource.assets(['assets/font1.ttf']);
      const source2 = FontSource.assets(['assets/font2.ttf']);

      expect(source1, isNot(equals(source2)));
    });

    test('different path order => not equal', () {
      const source1 = FontSource.assets(['a.ttf', 'b.ttf']);
      const source2 = FontSource.assets(['b.ttf', 'a.ttf']);

      expect(source1, isNot(equals(source2)));
    });

    test('different list lengths => not equal', () {
      const source1 = FontSource.assets(['a.ttf']);
      const source2 = FontSource.assets(['a.ttf', 'b.ttf']);

      expect(source1, isNot(equals(source2)));
    });

    test('empty asset paths can be constructed', () {
      const source = FontSource.assets([]);
      expect(source, isNotNull);
    });

    test('two empty asset sources are equal', () {
      const source1 = FontSource.assets([]);
      const source2 = FontSource.assets([]);

      expect(source1, equals(source2));
    });

    test('assets is not equal to none', () {
      const assetsSource = FontSource.assets([]);
      const noneSource = FontSource.none();

      expect(assetsSource, isNot(equals(noneSource)));
    });

    test('assets is not equal to bytes', () {
      const assetsSource = FontSource.assets([]);
      const bytesSource = FontSource.bytes([]);

      expect(assetsSource, isNot(equals(bytesSource)));
    });

    testWidgets('load() fetches bytes from rootBundle', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final key = utf8.decode(message!.buffer.asUint8List());
            if (key == 'assets/font1.ttf') {
              return ByteData.view(Uint8List.fromList([1, 2, 3]).buffer);
            } else if (key == 'assets/font2.ttf') {
              return ByteData.view(Uint8List.fromList([4, 5, 6]).buffer);
            }
            return null;
          });

      const source = FontSource.assets([
        'assets/font1.ttf',
        'assets/font2.ttf',
      ]);
      final results = await source.load();

      expect(results, hasLength(2));
      expect(results[0], equals([1, 2, 3]));
      expect(results[1], equals([4, 5, 6]));

      // Clear the mock handler
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });
  });

  group('FontSource cross-variant equality', () {
    test('none, bytes, and assets are all mutually unequal', () {
      const none = FontSource.none();
      const bytes = FontSource.bytes([]);
      const assets = FontSource.assets([]);

      expect(none, isNot(equals(bytes)));
      expect(none, isNot(equals(assets)));
      expect(bytes, isNot(equals(assets)));
    });
  });
}
