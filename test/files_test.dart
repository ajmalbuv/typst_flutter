import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/typst_flutter.dart';

void main() {
  group('FileSource.bytes', () {
    test('load() returns the exact map passed in', () async {
      final data = Uint8List.fromList([1, 2, 3]);
      final source = FileSource.bytes({'image.png': data});
      final loaded = await source.load();

      expect(loaded['image.png'], equals(data));
    });

    test('load() returns an unmodifiable map', () async {
      final source = FileSource.bytes({
        'a.txt': Uint8List.fromList([10]),
      });
      final loaded = await source.load();

      expect(
        () => loaded['new.txt'] = Uint8List(0),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('works with empty map', () async {
      const source = FileSource.bytes({});
      final loaded = await source.load();

      expect(loaded, isEmpty);
    });

    test('works with single entry', () async {
      final bytes = Uint8List.fromList([42]);
      final source = FileSource.bytes({'only.bin': bytes});
      final loaded = await source.load();

      expect(loaded.length, equals(1));
      expect(loaded.containsKey('only.bin'), isTrue);
      expect(loaded['only.bin'], equals(bytes));
    });

    test('works with multiple entries', () async {
      final a = Uint8List.fromList([1, 2]);
      final b = Uint8List.fromList([3, 4, 5]);
      final c = Uint8List.fromList([]);
      final source = FileSource.bytes({'a.png': a, 'b.dat': b, 'c.bin': c});
      final loaded = await source.load();

      expect(loaded.length, equals(3));
      expect(loaded['a.png'], equals(a));
      expect(loaded['b.dat'], equals(b));
      expect(loaded['c.bin'], equals(c));
    });

    test('two instances with same data are equal', () {
      final data = Uint8List.fromList([1, 2, 3]);
      final a = FileSource.bytes({'file.png': data});
      final b = FileSource.bytes({'file.png': data});

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances with different data are not equal', () {
      final a = FileSource.bytes({
        'file.png': Uint8List.fromList([1]),
      });
      final b = FileSource.bytes({
        'file.png': Uint8List.fromList([2]),
      });

      expect(a, isNot(equals(b)));
    });

    test('two instances with different keys are not equal', () {
      final data = Uint8List.fromList([1]);
      final a = FileSource.bytes({'a.png': data});
      final b = FileSource.bytes({'b.png': data});

      expect(a, isNot(equals(b)));
    });
  });

  group('FileSource.none', () {
    test('load() returns empty map', () async {
      const source = FileSource.none();
      final loaded = await source.load();

      expect(loaded, isEmpty);
      expect(loaded, isA<Map<String, Uint8List>>());
    });

    test('const constructor works', () {
      const a = FileSource.none();
      const b = FileSource.none();

      // Both are const, so they share identity.
      expect(identical(a, b), isTrue);
    });

    test('can be constructed dynamically', () {
      const source = FileSource.none();
      expect(source, isNotNull);
    });

    test('two none() instances are equal', () {
      // Non-const instantiations still compare equal via Equatable.
      const a = FileSource.none();
      const b = FileSource.none();

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('FileSource.assets', () {
    test('can be constructed dynamically', () {
      final map = Map<String, String>.of({
        '/images/logo.png': 'assets/logo.png',
      });
      final source = FileSource.assets(map);

      expect(source, isNotNull);
    });

    test('two instances with same paths are equal', () {
      const a = FileSource.assets({
        '/images/logo.png': 'assets/logo.png',
        '/data/info.json': 'assets/info.json',
      });
      const b = FileSource.assets({
        '/images/logo.png': 'assets/logo.png',
        '/data/info.json': 'assets/info.json',
      });

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two instances with different paths are not equal', () {
      const a = FileSource.assets({'/img.png': 'assets/a.png'});
      const b = FileSource.assets({'/img.png': 'assets/b.png'});

      expect(a, isNot(equals(b)));
    });

    test('two instances with different keys are not equal', () {
      const a = FileSource.assets({'/a.png': 'assets/x.png'});
      const b = FileSource.assets({'/b.png': 'assets/x.png'});

      expect(a, isNot(equals(b)));
    });

    test('empty assets map is valid', () {
      const source = FileSource.assets({});

      expect(source, isNotNull);
    });

    testWidgets('load() fetches bytes from rootBundle', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', (message) async {
            final key = utf8.decode(message!.buffer.asUint8List());
            if (key == 'assets/a.png') {
              return ByteData.view(Uint8List.fromList([10, 20]).buffer);
            } else if (key == 'assets/b.txt') {
              return ByteData.view(Uint8List.fromList([30, 40]).buffer);
            }
            return null;
          });

      const source = FileSource.assets({
        '/virtual/a.png': 'assets/a.png',
        '/virtual/b.txt': 'assets/b.txt',
      });
      final loaded = await source.load();

      expect(loaded.length, equals(2));
      expect(loaded['/virtual/a.png'], equals([10, 20]));
      expect(loaded['/virtual/b.txt'], equals([30, 40]));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });
  });

  group('FileSource general', () {
    test('bytes() is a subtype of FileSource', () {
      final source = FileSource.bytes({'f': Uint8List(0)});

      expect(source, isA<FileSource>());
    });

    test('none() is a subtype of FileSource', () {
      const source = FileSource.none();

      expect(source, isA<FileSource>());
    });

    test('assets() is a subtype of FileSource', () {
      const source = FileSource.assets({'/f': 'assets/f'});

      expect(source, isA<FileSource>());
    });

    test('different FileSource types are not equal', () {
      const none = FileSource.none();
      const bytesEmpty = FileSource.bytes({});
      const assetsEmpty = FileSource.assets({});

      expect(none, isNot(equals(bytesEmpty)));
      expect(none, isNot(equals(assetsEmpty)));
      expect(bytesEmpty, isNot(equals(assetsEmpty)));
    });

    test('bytes() can hold large binary data', () async {
      final largeData = Uint8List(1024 * 1024); // 1 MB of zeros
      final source = FileSource.bytes({'big.bin': largeData});
      final loaded = await source.load();

      expect(loaded['big.bin']!.length, equals(1024 * 1024));
    });

    test('bytes() preserves exact byte values', () async {
      final data = Uint8List.fromList(List.generate(256, (i) => i));
      final source = FileSource.bytes({'all_bytes.bin': data});
      final loaded = await source.load();

      final result = loaded['all_bytes.bin']!;
      for (var i = 0; i < 256; i++) {
        expect(result[i], equals(i));
      }
    });

    test('none() load() returns same empty result on repeated calls', () async {
      const source = FileSource.none();
      final first = await source.load();
      final second = await source.load();

      expect(first, isEmpty);
      expect(second, isEmpty);
    });

    test('bytes() load() can be called multiple times', () async {
      final source = FileSource.bytes({
        'f.bin': Uint8List.fromList([7, 8, 9]),
      });
      final first = await source.load();
      final second = await source.load();

      expect(first['f.bin'], equals(second['f.bin']));
    });
  });
}
