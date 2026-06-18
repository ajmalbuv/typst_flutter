import 'package:flutter_test/flutter_test.dart';
import 'package:typst_flutter/typst_flutter.dart';

void main() {
  group('TypstException', () {
    test('stores message', () {
      const e = TypstException('something broke');
      expect(e.message, equals('something broke'));
    });

    test('toString() includes class name and message', () {
      const e = TypstException('disk full');
      expect(e.toString(), equals('TypstException: disk full'));
    });

    test('implements Exception', () {
      const e = TypstException('test');
      expect(e, isA<Exception>());
    });

    test('can be caught as Exception', () {
      Object? caught;
      try {
        throw const TypstException('catch me');
      } on Exception catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstException>());
      expect((caught as TypstException).message, equals('catch me'));
    });

    test('const constructor produces identical instances', () {
      const a = TypstException('same');
      const b = TypstException('same');
      expect(identical(a, b), isTrue);
    });

    test('empty message', () {
      const e = TypstException('');
      expect(e.message, isEmpty);
      expect(e.toString(), equals('TypstException: '));
    });

    test('message with special characters', () {
      const e = TypstException('line1\nline2\ttab');
      expect(e.message, equals('line1\nline2\ttab'));
      expect(e.toString(), equals('TypstException: line1\nline2\ttab'));
    });
  });

  group('TypstCompileException', () {
    test('stores message', () {
      const e = TypstCompileException('compile failed');
      expect(e.message, equals('compile failed'));
    });

    test('defaults diagnostics to empty list', () {
      const e = TypstCompileException('failed');
      expect(e.diagnostics, isEmpty);
    });

    test('stores provided diagnostics', () {
      const diag = TypstDiagnostic(
        severity: TypstSeverity.error,
        message: 'unknown variable',
        hints: [],
      );
      const e = TypstCompileException('failed', diagnostics: [diag]);
      expect(e.diagnostics, hasLength(1));
      expect(e.diagnostics.first.message, equals('unknown variable'));
    });

    test('inherits from TypstException', () {
      const e = TypstCompileException('test');
      expect(e, isA<TypstException>());
    });

    test('implements Exception', () {
      const e = TypstCompileException('test');
      expect(e, isA<Exception>());
    });

    test('can be caught as TypstException', () {
      Object? caught;
      try {
        throw const TypstCompileException('catch as base');
      } on TypstException catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstCompileException>());
    });

    test('can be caught as Exception', () {
      Object? caught;
      try {
        throw const TypstCompileException('catch as exception');
      } on Exception catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstCompileException>());
    });

    test('const constructor produces identical instances', () {
      const a = TypstCompileException('same');
      const b = TypstCompileException('same');
      expect(identical(a, b), isTrue);
    });

    group('toString()', () {
      test('with empty diagnostics falls back to super.toString()', () {
        const e = TypstCompileException('Compilation failed');
        expect(e.toString(), equals('TypstException: Compilation failed'));
      });

      test('with single error diagnostic (no location)', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'unknown variable: x',
              hints: [],
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('Typst Compilation Errors:'));
        expect(result, contains('[ERROR] unknown variable: x'));
        // No location prefix when spanStart is null
        expect(result, isNot(contains('\u2014')));
      });

      test('with single error diagnostic that has location', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'unexpected token',
              hints: [],
              spanStart: TypstSourceLocation(line: 5, column: 12),
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('[ERROR] 5:12 \u2014 unexpected token'));
      });

      test('with error diagnostic that has both spanStart and spanEnd', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'bad range',
              hints: [],
              spanStart: TypstSourceLocation(line: 3, column: 1),
              spanEnd: TypstSourceLocation(line: 3, column: 10),
            ),
          ],
        );
        final result = e.toString();
        // Only spanStart is used in the format string
        expect(result, contains('[ERROR] 3:1 \u2014 bad range'));
      });

      test('with single hint', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'unknown variable: x',
              hints: ['Did you mean: y?'],
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('[ERROR] unknown variable: x'));
        expect(result, contains('  Hint: Did you mean: y?'));
      });

      test('with multiple hints', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'missing argument',
              hints: [
                'Add required argument: name',
                'See documentation for details',
              ],
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('  Hint: Add required argument: name'));
        expect(result, contains('  Hint: See documentation for details'));
      });

      test('with warning severity', () {
        const e = TypstCompileException(
          'compiled with warnings',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.warning,
              message: 'unused variable: z',
              hints: [],
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('[WARNING] unused variable: z'));
      });

      test('with multiple diagnostics of mixed severity', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'syntax error',
              hints: [],
              spanStart: TypstSourceLocation(line: 1, column: 1),
            ),
            TypstDiagnostic(
              severity: TypstSeverity.warning,
              message: 'deprecated function',
              hints: ['Use newFunc() instead'],
              spanStart: TypstSourceLocation(line: 10, column: 5),
            ),
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'missing semicolon',
              hints: [],
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('Typst Compilation Errors:'));
        expect(result, contains('[ERROR] 1:1 \u2014 syntax error'));
        expect(result, contains('[WARNING] 10:5 \u2014 deprecated function'));
        expect(result, contains('  Hint: Use newFunc() instead'));
        expect(result, contains('[ERROR] missing semicolon'));
      });

      test('output is trimmed (no trailing whitespace)', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'test error',
              hints: [],
            ),
          ],
        );
        final result = e.toString();
        expect(result, equals(result.trim()));
      });

      test('location at line 1 column 1', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'first char error',
              hints: [],
              spanStart: TypstSourceLocation(line: 1, column: 1),
            ),
          ],
        );
        expect(e.toString(), contains('[ERROR] 1:1 \u2014 first char error'));
      });

      test('location with large line and column numbers', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'deep error',
              hints: [],
              spanStart: TypstSourceLocation(line: 9999, column: 256),
            ),
          ],
        );
        expect(e.toString(), contains('[ERROR] 9999:256 \u2014 deep error'));
      });

      test('diagnostic message with special characters', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'expected "}" but found EOF',
              hints: [],
            ),
          ],
        );
        expect(e.toString(), contains('[ERROR] expected "}" but found EOF'));
      });

      test('hint with special characters', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'parse error',
              hints: ['Try adding a closing "}" bracket'],
            ),
          ],
        );
        expect(
          e.toString(),
          contains('  Hint: Try adding a closing "}" bracket'),
        );
      });

      test('diagnostic with empty message', () {
        const e = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: '',
              hints: [],
            ),
          ],
        );
        final result = e.toString();
        expect(result, contains('[ERROR]'));
      });

      test('diagnostic with empty hints list vs hints present', () {
        const noHints = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'err',
              hints: [],
            ),
          ],
        );
        const withHints = TypstCompileException(
          'failed',
          diagnostics: [
            TypstDiagnostic(
              severity: TypstSeverity.error,
              message: 'err',
              hints: ['fix it'],
            ),
          ],
        );
        expect(noHints.toString(), isNot(contains('Hint:')));
        expect(withHints.toString(), contains('Hint: fix it'));
      });
    });
  });

  group('TypstRenderException', () {
    test('stores message', () {
      const e = TypstRenderException('render failed');
      expect(e.message, equals('render failed'));
    });

    test('toString() includes class name and message', () {
      const e = TypstRenderException('SVG export error');
      expect(e.toString(), equals('TypstRenderException: SVG export error'));
    });

    test('inherits from TypstException', () {
      const e = TypstRenderException('test');
      expect(e, isA<TypstException>());
    });

    test('implements Exception', () {
      const e = TypstRenderException('test');
      expect(e, isA<Exception>());
    });

    test('can be caught as TypstException', () {
      Object? caught;
      try {
        throw const TypstRenderException('catch me');
      } on TypstException catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstRenderException>());
    });

    test('can be caught as Exception', () {
      Object? caught;
      try {
        throw const TypstRenderException('catch me');
      } on Exception catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstRenderException>());
    });

    test('const constructor produces identical instances', () {
      const a = TypstRenderException('same');
      const b = TypstRenderException('same');
      expect(identical(a, b), isTrue);
    });

    test('toString() differs from TypstException toString()', () {
      const render = TypstRenderException('problem');
      const base = TypstException('problem');
      expect(render.toString(), isNot(equals(base.toString())));
      expect(render.toString(), contains('TypstRenderException'));
      expect(base.toString(), contains('TypstException'));
    });

    test('empty message', () {
      const e = TypstRenderException('');
      expect(e.message, isEmpty);
      expect(e.toString(), equals('TypstRenderException: '));
    });
  });

  group('TypstLibraryNotFoundException', () {
    test('stores message', () {
      const e = TypstLibraryNotFoundException('lib not found');
      expect(e.message, equals('lib not found'));
    });

    test('toString() includes class name and message', () {
      const e = TypstLibraryNotFoundException('libtypst_flutter.so missing');
      expect(
        e.toString(),
        equals('TypstLibraryNotFoundException: libtypst_flutter.so missing'),
      );
    });

    test('implements Exception', () {
      const e = TypstLibraryNotFoundException('test');
      expect(e, isA<Exception>());
    });

    test('does NOT extend TypstException', () {
      const e = TypstLibraryNotFoundException('test');
      expect(e, isNot(isA<TypstException>()));
    });

    test('can be caught as Exception', () {
      Object? caught;
      try {
        throw const TypstLibraryNotFoundException('gone');
      } on Exception catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstLibraryNotFoundException>());
    });

    test('cannot be caught as TypstException', () {
      Object? caughtAsTypst;
      Object? caughtAsException;
      try {
        throw const TypstLibraryNotFoundException('gone');
      } on TypstException catch (e) {
        caughtAsTypst = e;
      } on Exception catch (e) {
        caughtAsException = e;
      }
      expect(caughtAsTypst, isNull);
      expect(caughtAsException, isA<TypstLibraryNotFoundException>());
    });

    test('const constructor produces identical instances', () {
      const a = TypstLibraryNotFoundException('same');
      const b = TypstLibraryNotFoundException('same');
      expect(identical(a, b), isTrue);
    });

    test('empty message', () {
      const e = TypstLibraryNotFoundException('');
      expect(e.message, isEmpty);
      expect(e.toString(), equals('TypstLibraryNotFoundException: '));
    });

    test('message with path separators', () {
      const e = TypstLibraryNotFoundException(
        r'C:\Users\dev\libs\typst_flutter.dll not found',
      );
      expect(
        e.message,
        equals(r'C:\Users\dev\libs\typst_flutter.dll not found'),
      );
    });
  });

  group('Exception hierarchy', () {
    test('TypstCompileException is caught by TypstException handler', () {
      Object? caught;
      try {
        throw const TypstCompileException('compile err');
      } on TypstException catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstCompileException>());
    });

    test('TypstRenderException is caught by TypstException handler', () {
      Object? caught;
      try {
        throw const TypstRenderException('render err');
      } on TypstException catch (e) {
        caught = e;
      }
      expect(caught, isA<TypstRenderException>());
    });

    test(
      'TypstLibraryNotFoundException is NOT caught by TypstException handler',
      () {
        Object? caught;
        try {
          throw const TypstLibraryNotFoundException('lib err');
        } on TypstException {
          caught = 'wrong handler';
        } on Exception catch (e) {
          caught = e;
        }
        expect(caught, isA<TypstLibraryNotFoundException>());
      },
    );

    test('all exception types are catchable as Exception', () {
      for (final exception in <Exception>[
        const TypstException('a'),
        const TypstCompileException('b'),
        const TypstRenderException('c'),
        const TypstLibraryNotFoundException('d'),
      ]) {
        Object? caught;
        try {
          throw exception;
        } on Exception catch (e) {
          caught = e;
        }
        expect(
          caught,
          isNotNull,
          reason: '${exception.runtimeType} not caught',
        );
      }
    });
  });
}
